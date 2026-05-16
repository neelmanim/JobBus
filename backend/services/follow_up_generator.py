"""
JobBus Backend — Follow-up Generator.

Generates tone-varied follow-up emails with smart scheduling and cancel rules.
Supports all AI providers (Gemini, Groq, OpenAI) via httpx REST — no SDK imports.
"""

from __future__ import annotations


import json
import re
import random
from datetime import datetime, timedelta, timezone
from typing import Optional

from database import get_supabase_admin
from services.email_writer import _call_ai
from models.enums import OutcomeType


class MaxFollowUpsReached(Exception):
    pass


class FollowUpGenerator:
    """Generates follow-up emails with different tone from initial."""

    MAX_FOLLOWUPS = 2
    FOLLOWUP_1_DELAY_DAYS = (3, 4)
    FOLLOWUP_2_DELAY_DAYS = (5, 7)

    PROMPT_TEMPLATE = """Write a follow-up email. This is follow-up #{sequence} for a cold outreach.

RULES:
- Under 80 words
- Different tone from the initial email
- Do NOT repeat the initial email's opening
- Do NOT repeat the same achievement
- Be shorter and more casual than the initial
- End with a question
- No "just following up" or "checking in" — be specific
- Reference something new or add a different angle

INITIAL EMAIL SUBJECT: {initial_subject}
INITIAL EMAIL OPENING (DO NOT REPEAT): {initial_opening}

CANDIDATE: {candidate_name}, {candidate_role}
RECIPIENT: {recipient_name} at {company}
ACHIEVEMENT TO USE (different from initial): {achievement}

Return ONLY JSON: {{"subject": "Re: ...", "body": "..."}}"""

    def __init__(self, api_key: str, provider: str = "gemini"):
        """Initialize with a provider key and name.

        Args:
            api_key: Decrypted API key for the provider.
            provider: One of "gemini" (default), "groq", "openai".
        """
        self._api_key = api_key
        self._provider = provider

    async def generate_followup(
        self,
        initial_draft: dict,
        sequence: int,
        resume_profile: dict,
        contact: dict = None,
        previous_followup_sent: datetime = None,
    ) -> dict:
        """Generate a follow-up email.

        Args:
            initial_draft: The original sent email
            sequence: 1 or 2
            resume_profile: Candidate profile
            contact: Recipient info
            previous_followup_sent: When the previous follow-up was sent

        Returns:
            Dict with subject, body, scheduled_at
        """
        if sequence > self.MAX_FOLLOWUPS:
            raise MaxFollowUpsReached(f"Maximum {self.MAX_FOLLOWUPS} follow-ups allowed")

        # Calculate schedule
        if sequence == 1:
            base_time = datetime.fromisoformat(str(initial_draft.get("sent_at", datetime.now(timezone.utc))))
            delay = random.randint(*self.FOLLOWUP_1_DELAY_DAYS)
        else:
            base_time = previous_followup_sent or datetime.now(timezone.utc)
            delay = random.randint(*self.FOLLOWUP_2_DELAY_DAYS)

        scheduled_at = base_time + timedelta(days=delay)

        # Pick a different achievement
        achievements = resume_profile.get("achievements", [])
        initial_body = initial_draft.get("body", "")
        available = [a for a in achievements if a[:20].lower() not in initial_body.lower()]
        achievement = random.choice(available) if available else (achievements[0] if achievements else "")

        prompt = self.PROMPT_TEMPLATE.format(
            sequence=sequence,
            initial_subject=initial_draft.get("subject", ""),
            initial_opening=initial_body[:100],
            candidate_name=resume_profile.get("name", ""),
            candidate_role=resume_profile.get("role", ""),
            recipient_name=(contact or {}).get("first_name", "there"),
            company=(contact or {}).get("company", "your company"),
            achievement=achievement,
        )

        raw = await _call_ai(self._provider, self._api_key, prompt)
        raw = raw.strip()
        json_match = re.search(r"\{.*\}", raw, re.DOTALL)
        if json_match:
            raw = json_match.group(0)

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = {"subject": f"Re: {initial_draft.get('subject', '')}", "body": raw}

        return {
            "subject": data.get("subject", ""),
            "body": data.get("body", ""),
            "sequence": sequence,
            "scheduled_at": scheduled_at,
            "initial_draft_id": initial_draft.get("id"),
        }


class FollowUpManager:
    """Manages follow-up scheduling, cancellation, and recommendations."""

    def schedule_followup(self, draft_id: str, contact_id: str, user_id: str,
                          scheduled_at: datetime, subject: str, body: str, sequence: int) -> dict:
        """Schedule a follow-up email."""
        supabase = get_supabase_admin()
        data = {
            "user_id": user_id,
            "initial_draft_id": draft_id,
            "contact_id": contact_id,
            "subject": subject,
            "body": body,
            "sequence": sequence,
            "scheduled_at": scheduled_at.isoformat(),
            "status": "pending",
        }
        result = supabase.table("follow_ups").insert(data).execute()
        return result.data[0] if result.data else data

    def get_pending_followups(self, draft_id: str = None, user_id: str = None) -> list[dict]:
        """Get pending follow-ups, filtered by draft or user."""
        supabase = get_supabase_admin()
        query = supabase.table("follow_ups").select("*").eq("status", "pending")
        if draft_id:
            query = query.eq("initial_draft_id", draft_id)
        if user_id:
            query = query.eq("user_id", user_id)
        result = query.order("scheduled_at").execute()
        return result.data or []

    def cancel_followups(self, draft_id: str = None, contact_id: str = None) -> int:
        """Cancel pending follow-ups (on reply, bounce, etc.)."""
        supabase = get_supabase_admin()
        query = supabase.table("follow_ups").update(
            {"status": "cancelled"}
        ).eq("status", "pending")
        if draft_id:
            query = query.eq("initial_draft_id", draft_id)
        if contact_id:
            query = query.eq("contact_id", contact_id)
        result = query.execute()
        return len(result.data) if result.data else 0

    def record_outcome(self, draft_id: str, outcome_type: str) -> None:
        """Record an outcome and auto-cancel follow-ups if needed."""
        if outcome_type in (OutcomeType.REPLY.value, OutcomeType.BOUNCE.value, OutcomeType.INTERVIEW.value):
            self.cancel_followups(draft_id=draft_id)

    def should_followup(self, opportunity_score: float) -> dict:
        """Recommend whether to follow up based on opportunity score."""
        if opportunity_score >= 60:
            return {"recommended": True, "reason": "Strong alignment — follow-up recommended"}
        elif opportunity_score >= 40:
            return {"recommended": True, "reason": "Moderate alignment — one follow-up suggested"}
        else:
            return {"recommended": False, "reason": "Weak alignment — consider skipping follow-up"}
