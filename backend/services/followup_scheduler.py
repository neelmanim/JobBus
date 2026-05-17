"""
JobBus — Follow-up Auto-Sender.

Runs as a background daemon thread inside the FastAPI process.
Every hour it checks the follow_ups table for pending follow-ups
where scheduled_at <= NOW() and sends them via the user's SMTP.

No external scheduler (Railway cron, Celery) required.
"""

from __future__ import annotations

import logging
import threading
import time
import asyncio
from datetime import datetime, timezone

logger = logging.getLogger(__name__)


def _get_due_followups(supabase) -> list[dict]:
    """Fetch all pending follow-ups that are due (scheduled_at <= now)."""
    now = datetime.now(timezone.utc).isoformat()
    result = supabase.table("follow_ups").select(
        "*, contacts(email, first_name, last_name)"
    ).eq("status", "pending").lte("scheduled_at", now).execute()
    return result.data or []


async def _send_followup(supabase, followup: dict) -> bool:
    """Send a single follow-up email and update its status."""
    from services.smtp_sender import get_smtp_sender

    contact = followup.get("contacts") or {}
    to_email = contact.get("email", "")
    to_name  = contact.get("first_name", "")

    if not to_email:
        logger.warning(f"Follow-up {followup['id']} has no contact email — skipping")
        supabase.table("follow_ups").update({"status": "cancelled"}).eq("id", followup["id"]).execute()
        return False

    try:
        sender = get_smtp_sender()
        result = await sender.send(
            user_id=followup["user_id"],
            to_email=to_email,
            to_name=to_name,
            subject=followup["subject"],
            body=followup["body"],
        )
        status = "sent" if result.success else "failed"
        supabase.table("follow_ups").update({
            "status": status,
            "sent_at": datetime.now(timezone.utc).isoformat(),
        }).eq("id", followup["id"]).execute()
        return result.success
    except Exception as e:
        logger.error(f"Follow-up send error for {followup['id']}: {e}")
        supabase.table("follow_ups").update({"status": "failed"}).eq("id", followup["id"]).execute()
        return False


async def process_due_followups() -> dict:
    """Process all due follow-ups. Returns summary dict. Safe to call anytime."""
    from database import get_supabase_admin
    supabase = get_supabase_admin()

    due = _get_due_followups(supabase)
    if not due:
        return {"processed": 0, "sent": 0, "failed": 0}

    sent = failed = 0
    for followup in due:
        success = await _send_followup(supabase, followup)
        if success:
            sent += 1
        else:
            failed += 1

    logger.info(f"Follow-up batch: {sent} sent, {failed} failed out of {len(due)} due")
    return {"processed": len(due), "sent": sent, "failed": failed}


def _scheduler_loop(interval_seconds: int = 3600):
    """Runs in a daemon thread. Checks for due follow-ups every `interval_seconds`."""
    logger.info(f"Follow-up scheduler started (interval={interval_seconds}s)")
    while True:
        try:
            # Run the async processor in a new event loop for this thread
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            result = loop.run_until_complete(process_due_followups())
            loop.close()
            if result["processed"] > 0:
                logger.info(f"Scheduler processed: {result}")
        except Exception as e:
            logger.error(f"Follow-up scheduler error: {e}")
        time.sleep(interval_seconds)


def start_followup_scheduler(interval_seconds: int = 3600):
    """Start the follow-up scheduler as a background daemon thread.

    Call this once from FastAPI startup. The daemon thread will be
    killed automatically when the main process exits.
    """
    thread = threading.Thread(
        target=_scheduler_loop,
        args=(interval_seconds,),
        daemon=True,
        name="followup-scheduler",
    )
    thread.start()
    logger.info("Follow-up scheduler thread started")
    return thread
