"""
JobBus Backend — Campaign Router (v2).

Full campaign lifecycle: create → contacts → generate-drafts →
approve/reject → send (with sandbox guard) → pause/resume/stop → outcomes.
"""

from __future__ import annotations

import logging
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from middleware.auth_middleware import get_current_user
from services.campaign_engine import CampaignEngine
from services.credential_service import get_credential_service
from models.schemas import CampaignCreate, CampaignResponse, CampaignAnalytics
from models.enums import CampaignStatus, ContactStatus
from database import get_supabase_admin
from providers.ai.factory import get_ai_provider

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/campaigns", tags=["campaigns"])
engine = CampaignEngine()


# ─────────────────────────────────────────────────────────────
# Pydantic models for new endpoints
# ─────────────────────────────────────────────────────────────

class DraftGenerateRequest(BaseModel):
    contact_ids: Optional[list[str]] = None  # None = all contacts in campaign
    regenerate: bool = False                  # overwrite existing unapproved drafts
    tone: str = Field("professional", description="professional | warm | direct | storytelling")
    custom_instructions: Optional[str] = None


class DraftApprovalRequest(BaseModel):
    draft_id: str
    action: str = Field(..., description="approve | reject | edit")
    edited_subject: Optional[str] = None
    edited_body: Optional[str] = None
    rejection_reason: Optional[str] = None


class OutcomeRequest(BaseModel):
    contact_id: str
    outcome: str = Field(..., description="replied | interview | bounced | unsubscribed | no_response")
    notes: Optional[str] = None


class SendStartRequest(BaseModel):
    dry_run: bool = True  # Default TRUE = sandbox, must explicitly set False


class CampaignStatusUpdate(BaseModel):
    status: CampaignStatus


class CampaignSettingsUpdate(BaseModel):
    sandbox_mode: Optional[bool] = None
    send_delay_seconds: Optional[int] = None
    max_per_day: Optional[int] = None
    business_hours_only: Optional[bool] = None
    outreach_angle: Optional[str] = None


# ─────────────────────────────────────────────────────────────
# Core CRUD (existing, preserved)
# ─────────────────────────────────────────────────────────────

@router.post("/", response_model=CampaignResponse)
async def create_campaign(
    request: CampaignCreate,
    user: dict = Depends(get_current_user),
):
    """Create a new campaign."""
    return engine.create_campaign(user["user_id"], request)


@router.get("/", response_model=list[CampaignResponse])
async def list_campaigns(user: dict = Depends(get_current_user)):
    """List all campaigns for the current user."""
    return engine.list_campaigns(user["user_id"])


@router.get("/{campaign_id}", response_model=CampaignResponse)
async def get_campaign(campaign_id: str, user: dict = Depends(get_current_user)):
    """Get a specific campaign."""
    campaign = engine.get_campaign(campaign_id, user["user_id"])
    if not campaign:
        raise HTTPException(status_code=404, detail="Campaign not found")
    return campaign


@router.put("/{campaign_id}/status")
async def update_campaign_status(
    campaign_id: str,
    body: CampaignStatusUpdate,
    user: dict = Depends(get_current_user),
):
    """Update campaign status."""
    try:
        return engine.update_status(campaign_id, user["user_id"], body.status)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.get("/{campaign_id}/analytics", response_model=CampaignAnalytics)
async def get_campaign_analytics(
    campaign_id: str,
    user: dict = Depends(get_current_user),
):
    """Get campaign analytics."""
    campaign = engine.get_campaign(campaign_id, user["user_id"])
    if not campaign:
        raise HTTPException(status_code=404, detail="Campaign not found")
    return engine.get_analytics(campaign_id)


# ─────────────────────────────────────────────────────────────
# Draft Generation
# ─────────────────────────────────────────────────────────────

@router.post("/{campaign_id}/generate-drafts")
async def generate_drafts(
    campaign_id: str,
    request: DraftGenerateRequest,
    user: dict = Depends(get_current_user),
):
    """
    Generate personalized email drafts for contacts in this campaign.
    Uses the user's configured AI provider (Groq → Gemini → OpenAI fallback).
    """
    supabase = get_supabase_admin()
    user_id = user["user_id"]

    # Verify campaign ownership
    campaign_result = supabase.table("campaigns").select("*").eq(
        "id", campaign_id
    ).eq("user_id", user_id).single().execute()
    if not campaign_result.data:
        raise HTTPException(status_code=404, detail="Campaign not found")

    campaign = campaign_result.data

    # Get contacts for this campaign
    contacts_query = supabase.table("contacts").select("*").eq("user_id", user_id)
    if request.contact_ids:
        contacts_query = contacts_query.in_("id", request.contact_ids)
    else:
        # Default: all contacts linked to this campaign via opportunity
        if campaign.get("opportunity_id"):
            contacts_query = contacts_query.eq("opportunity_id", campaign["opportunity_id"])
    contacts = contacts_query.execute().data

    if not contacts:
        raise HTTPException(
            status_code=400,
            detail="No contacts found. Add contacts to the campaign first."
        )

    # Skip contacts that already have approved drafts (unless regenerate=True)
    if not request.regenerate:
        existing_draft_result = supabase.table("email_drafts").select(
            "contact_id"
        ).eq("campaign_id", campaign_id).eq("status", "approved").execute()
        approved_contact_ids = {r["contact_id"] for r in existing_draft_result.data}
        contacts = [c for c in contacts if c["id"] not in approved_contact_ids]
        if not contacts:
            return {
                "generated": 0,
                "message": "All contacts already have approved drafts. Use regenerate=true to overwrite."
            }

    # Get AI provider
    try:
        ai = get_ai_provider(user)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Get user profile for signature/style
    profile_result = supabase.table("user_profiles").select(
        "signature_name, signature_title, signature_linkedin, custom_instructions"
    ).eq("user_id", user_id).single().execute()
    profile = profile_result.data or {}

    # Get opportunity context
    opportunity = None
    if campaign.get("opportunity_id"):
        opp_result = supabase.table("opportunities").select("*").eq(
            "id", campaign["opportunity_id"]
        ).single().execute()
        opportunity = opp_result.data

    generated_count = 0
    errors = []

    for contact in contacts:
        try:
            system_prompt = _build_system_prompt(profile, request.tone)
            user_prompt = _build_user_prompt(contact, campaign, opportunity, request.custom_instructions)

            result = await ai.generate(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                temperature=0.75,
                max_tokens=800,
            )

            # Parse subject and body from AI output
            subject, body = _parse_email_output(result.text, contact, campaign)

            # Score the draft
            quality_score, quality_issues = _score_draft(subject, body, contact, profile)

            # Save to email_drafts
            draft_data = {
                "campaign_id": campaign_id,
                "contact_id": contact["id"],
                "user_id": user_id,
                "subject": subject,
                "body": body,
                "status": "draft",
                "quality_score": quality_score,
                "quality_issues": quality_issues,
                "ai_model": result.model,
                "ai_provider": result.provider,
            }

            # Upsert: replace existing draft for same contact/campaign if regenerating
            if request.regenerate:
                existing = supabase.table("email_drafts").select("id").eq(
                    "campaign_id", campaign_id
                ).eq("contact_id", contact["id"]).execute()
                if existing.data:
                    supabase.table("email_drafts").update(draft_data).eq(
                        "id", existing.data[0]["id"]
                    ).execute()
                else:
                    supabase.table("email_drafts").insert(draft_data).execute()
            else:
                supabase.table("email_drafts").insert(draft_data).execute()

            generated_count += 1

        except Exception as e:
            logger.error(f"Draft generation failed for contact {contact['id']}: {e}")
            errors.append({"contact_id": contact["id"], "error": str(e)})

    return {
        "generated": generated_count,
        "failed": len(errors),
        "errors": errors if errors else None,
        "message": f"Generated {generated_count} draft(s) using {ai.provider_name} ({ai.model})",
    }


# ─────────────────────────────────────────────────────────────
# Draft Management
# ─────────────────────────────────────────────────────────────

@router.get("/{campaign_id}/drafts")
async def list_drafts(
    campaign_id: str,
    status: Optional[str] = None,  # draft | approved | rejected | sent
    user: dict = Depends(get_current_user),
):
    """List all email drafts for a campaign with quality scores and contact info."""
    supabase = get_supabase_admin()

    # Verify ownership
    campaign = supabase.table("campaigns").select("id").eq(
        "id", campaign_id
    ).eq("user_id", user["user_id"]).single().execute()
    if not campaign.data:
        raise HTTPException(status_code=404, detail="Campaign not found")

    q = supabase.table("email_drafts").select(
        "*, contacts(first_name, last_name, email, title, company, persona_type)"
    ).eq("campaign_id", campaign_id)
    if status:
        q = q.eq("status", status)

    result = q.order("created_at", desc=True).execute()
    return result.data


@router.post("/{campaign_id}/drafts/approve")
async def approve_or_reject_draft(
    campaign_id: str,
    request: DraftApprovalRequest,
    user: dict = Depends(get_current_user),
):
    """Approve, reject, or apply edits to a specific draft."""
    supabase = get_supabase_admin()
    user_id = user["user_id"]

    # Verify draft belongs to this user and campaign
    draft_result = supabase.table("email_drafts").select("*").eq(
        "id", request.draft_id
    ).eq("campaign_id", campaign_id).eq("user_id", user_id).single().execute()

    if not draft_result.data:
        raise HTTPException(status_code=404, detail="Draft not found")

    draft = draft_result.data

    if request.action == "approve":
        update_data = {"status": "approved"}
        if request.edited_subject:
            update_data["subject"] = request.edited_subject
        if request.edited_body:
            update_data["body"] = request.edited_body
            # Re-score if body was edited
            _, issues = _score_draft(
                update_data.get("subject", draft["subject"]),
                request.edited_body,
                {},
                {},
            )
            update_data["quality_issues"] = issues

    elif request.action == "reject":
        update_data = {
            "status": "rejected",
            "rejection_reason": request.rejection_reason,
        }
    elif request.action == "edit":
        update_data = {}
        if request.edited_subject:
            update_data["subject"] = request.edited_subject
        if request.edited_body:
            update_data["body"] = request.edited_body
        if not update_data:
            raise HTTPException(status_code=422, detail="Provide edited_subject or edited_body")
    else:
        raise HTTPException(status_code=422, detail=f"Unknown action: {request.action}")

    supabase.table("email_drafts").update(update_data).eq("id", request.draft_id).execute()
    return {"draft_id": request.draft_id, "action": request.action, "status": update_data.get("status", draft["status"])}


# ─────────────────────────────────────────────────────────────
# Send Controls
# ─────────────────────────────────────────────────────────────

@router.post("/{campaign_id}/send/start")
async def start_send(
    campaign_id: str,
    request: SendStartRequest,
    user: dict = Depends(get_current_user),
):
    """
    Start sending approved drafts.
    SAFETY: dry_run=True by default — must explicitly set dry_run=False to send.
    Also checks sandbox_mode flag on the campaign.
    """
    supabase = get_supabase_admin()
    user_id = user["user_id"]

    campaign_result = supabase.table("campaigns").select("*").eq(
        "id", campaign_id
    ).eq("user_id", user_id).single().execute()
    if not campaign_result.data:
        raise HTTPException(status_code=404, detail="Campaign not found")

    campaign = campaign_result.data

    # Safety gate 1: check campaign sandbox mode
    if campaign.get("sandbox_mode", True):
        return {
            "blocked": True,
            "reason": "Sandbox mode is ON. Disable it in Campaign Settings before sending live emails.",
            "dry_run": True,
        }

    # Safety gate 2: explicit dry_run flag
    if request.dry_run:
        # Count approved drafts and return pre-flight info
        approved = supabase.table("email_drafts").select(
            "id", count="exact"
        ).eq("campaign_id", campaign_id).eq("status", "approved").execute()

        return {
            "dry_run": True,
            "approved_drafts": approved.count,
            "message": f"Pre-flight check: {approved.count} approved drafts ready. Set dry_run=false to send.",
        }

    # Verify SMTP is configured
    cred = get_credential_service()
    try:
        cred.get_decrypted(user_id)
    except Exception:
        raise HTTPException(
            status_code=400,
            detail="SMTP not configured. Go to Settings → Email to add your SMTP credentials."
        )

    # Get approved drafts
    drafts_result = supabase.table("email_drafts").select(
        "*, contacts(email, first_name)"
    ).eq("campaign_id", campaign_id).eq("status", "approved").execute()

    if not drafts_result.data:
        raise HTTPException(
            status_code=400,
            detail="No approved drafts. Approve at least one draft before sending."
        )

    # Update campaign status to sending
    supabase.table("campaigns").update({"status": "sending"}).eq("id", campaign_id).execute()

    # Queue sends (background task dispatch)
    from services.smtp_sender import get_smtp_sender
    sender = get_smtp_sender()

    sent = 0
    failed = 0
    for draft in drafts_result.data:
        contact_email = (draft.get("contacts") or {}).get("email", "")
        contact_name = (draft.get("contacts") or {}).get("first_name", "")
        try:
            result = await sender.send(
                user_id=user_id,
                to_email=contact_email,
                to_name=contact_name,
                subject=draft["subject"],
                body=draft["body"],
            )
            status = "sent" if result.success else "failed"
            supabase.table("email_drafts").update({"status": status}).eq("id", draft["id"]).execute()
            if result.success:
                sent += 1
            else:
                failed += 1
        except Exception as e:
            logger.error(f"Send failed for draft {draft['id']}: {e}")
            failed += 1

    return {
        "sent": sent,
        "failed": failed,
        "total": len(drafts_result.data),
    }


@router.post("/{campaign_id}/send/pause")
async def pause_campaign(campaign_id: str, user: dict = Depends(get_current_user)):
    """Pause a sending campaign."""
    return _update_send_status(campaign_id, user["user_id"], "paused")


@router.post("/{campaign_id}/send/resume")
async def resume_campaign(campaign_id: str, user: dict = Depends(get_current_user)):
    """Resume a paused campaign."""
    return _update_send_status(campaign_id, user["user_id"], "sending")


@router.post("/{campaign_id}/send/stop")
async def stop_campaign(campaign_id: str, user: dict = Depends(get_current_user)):
    """Stop a campaign permanently (stops all unsent drafts)."""
    result = _update_send_status(campaign_id, user["user_id"], "completed")
    # Cancel unsent drafts
    supabase = get_supabase_admin()
    supabase.table("email_drafts").update({"status": "cancelled"}).eq(
        "campaign_id", campaign_id
    ).eq("status", "approved").execute()
    return result


def _update_send_status(campaign_id: str, user_id: str, new_status: str) -> dict:
    supabase = get_supabase_admin()
    result = supabase.table("campaigns").select("id").eq(
        "id", campaign_id
    ).eq("user_id", user_id).single().execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Campaign not found")
    supabase.table("campaigns").update({"status": new_status}).eq("id", campaign_id).execute()
    return {"campaign_id": campaign_id, "status": new_status}


# ─────────────────────────────────────────────────────────────
# Outcomes
# ─────────────────────────────────────────────────────────────

@router.post("/{campaign_id}/outcomes")
async def record_outcome(
    campaign_id: str,
    request: OutcomeRequest,
    user: dict = Depends(get_current_user),
):
    """Record an outcome for a contact (replied, interview, bounced, etc.)."""
    supabase = get_supabase_admin()
    valid_outcomes = {"replied", "interview", "bounced", "unsubscribed", "no_response"}
    if request.outcome not in valid_outcomes:
        raise HTTPException(status_code=422, detail=f"Invalid outcome. Use: {valid_outcomes}")

    # Update the sent draft's status and contact status
    supabase.table("email_drafts").update({
        "status": request.outcome,
        "outcome_notes": request.notes,
    }).eq("campaign_id", campaign_id).eq("contact_id", request.contact_id).execute()

    return {
        "campaign_id": campaign_id,
        "contact_id": request.contact_id,
        "outcome": request.outcome,
    }


@router.get("/{campaign_id}/outcomes")
async def list_outcomes(
    campaign_id: str,
    user: dict = Depends(get_current_user),
):
    """Get all outcomes for a campaign."""
    supabase = get_supabase_admin()
    outcome_statuses = ("replied", "interview", "bounced", "unsubscribed", "no_response")

    result = supabase.table("email_drafts").select(
        "id, contact_id, status, outcome_notes, sent_at, contacts(first_name, last_name, email, company)"
    ).eq("campaign_id", campaign_id).in_("status", outcome_statuses).execute()

    return result.data


# ─────────────────────────────────────────────────────────────
# Campaign settings update
# ─────────────────────────────────────────────────────────────

@router.patch("/{campaign_id}/settings")
async def update_campaign_settings(
    campaign_id: str,
    request: CampaignSettingsUpdate,
    user: dict = Depends(get_current_user),
):
    """Update sandbox mode, delay, daily limit, business hours for a campaign."""
    supabase = get_supabase_admin()
    campaign = supabase.table("campaigns").select("id").eq(
        "id", campaign_id
    ).eq("user_id", user["user_id"]).single().execute()
    if not campaign.data:
        raise HTTPException(status_code=404, detail="Campaign not found")

    update_data = {k: v for k, v in request.model_dump().items() if v is not None}
    if not update_data:
        raise HTTPException(status_code=422, detail="No fields to update")

    supabase.table("campaigns").update(update_data).eq("id", campaign_id).execute()
    return {"campaign_id": campaign_id, "updated": list(update_data.keys())}


# ─────────────────────────────────────────────────────────────
# Contact management (enhanced)
# ─────────────────────────────────────────────────────────────

@router.get("/{campaign_id}/contacts")
async def get_campaign_contacts(
    campaign_id: str,
    user: dict = Depends(get_current_user),
):
    """Get all contacts associated with a campaign."""
    supabase = get_supabase_admin()

    # Verify campaign ownership
    campaign_result = supabase.table("campaigns").select(
        "opportunity_id"
    ).eq("id", campaign_id).eq("user_id", user["user_id"]).single().execute()
    if not campaign_result.data:
        raise HTTPException(status_code=404, detail="Campaign not found")

    campaign = campaign_result.data

    # Find contacts linked via campaign_contacts join table or opportunity_id
    cc_result = supabase.table("campaign_contacts").select(
        "contact_id"
    ).eq("campaign_id", campaign_id).execute()

    contact_ids = [r["contact_id"] for r in (cc_result.data or [])]

    # Also include contacts linked via opportunity_id
    if not contact_ids and campaign.get("opportunity_id"):
        opp_contacts = supabase.table("contacts").select("id").eq(
            "opportunity_id", campaign["opportunity_id"]
        ).eq("user_id", user["user_id"]).execute()
        contact_ids = [r["id"] for r in (opp_contacts.data or [])]

    if not contact_ids:
        return []

    contacts_result = supabase.table("contacts").select("*").in_(
        "id", contact_ids
    ).execute()
    return contacts_result.data or []



@router.post("/{campaign_id}/contacts")
async def add_campaign_contacts(
    campaign_id: str,
    contact_ids: list[str],
    user: dict = Depends(get_current_user),
):
    """Add contacts to a campaign."""
    campaign = engine.get_campaign(campaign_id, user["user_id"])
    if not campaign:
        raise HTTPException(status_code=404, detail="Campaign not found")
    added = engine.add_contacts(campaign_id, contact_ids)
    return {"added": added}


# ─────────────────────────────────────────────────────────────
# AI helpers — draft generation
# ─────────────────────────────────────────────────────────────

def _build_system_prompt(profile: dict, tone: str) -> str:
    name = profile.get("signature_name", "the candidate")
    title_hint = f"a {profile.get('signature_title', 'job seeker')}" if profile.get("signature_title") else "a job seeker"
    instructions = profile.get("custom_instructions", "")

    tone_guide = {
        "professional": "formal, respectful, outcome-focused",
        "warm": "friendly, personal, conversational",
        "direct": "short, punchy, executive-style",
        "storytelling": "narrative-driven, engaging, specific anecdotes",
    }.get(tone, "professional")

    return f"""You are an elite career coach helping {name} ({title_hint}) write cold outreach emails.

Tone: {tone_guide}.
Goal: Get a response / short call — NOT sell, NOT spam.
Rules:
- Maximum 150 words
- One specific compliment or hook based on the company/role
- One clear ask (15-min call OR referral to right person)
- No generic phrases: "I hope this finds you well", "I am writing to", "Please find attached"
- No buzzwords: "synergy", "leverage", "passionate", "proactive"
- Output format: Subject: [subject line]\\n\\n[email body]
{f'- Additional instructions: {instructions}' if instructions else ''}"""


def _build_user_prompt(contact: dict, campaign: dict, opportunity: dict | None, custom: str | None) -> str:
    company = contact.get("company", "the company")
    contact_name = contact.get("first_name", "there")
    title = contact.get("title", "")
    persona = contact.get("persona_type", "other")

    role = ""
    if opportunity:
        role = f"Role target: {opportunity.get('role', '')} at {opportunity.get('company', company)}\n"

    persona_hint = {
        "hiring_manager": "They likely make hiring decisions. Focus on your direct value to their team.",
        "recruiter": "They screen candidates. Lead with hard skills and availability.",
        "founder": "They care about ROI and culture fit. Be concise and high-signal.",
        "lead": "Peer-level. Focus on collaboration or learning from them.",
        "other": "Keep it professional and curious.",
    }.get(persona, "")

    return f"""Write an outreach email with these details:

Recipient: {contact_name} — {title} at {company}
{role}Persona: {persona_hint}
Campaign context: {campaign.get('description', campaign.get('name', ''))}
{f'Special instruction: {custom}' if custom else ''}

Remember: Subject + Body. Max 150 words total."""


def _parse_email_output(text: str, contact: dict, campaign: dict) -> tuple[str, str]:
    """Parse 'Subject: ...\n\nBody...' format from AI output."""
    text = text.strip()
    subject = ""
    body = text

    if text.lower().startswith("subject:"):
        lines = text.split("\n")
        subject_line = lines[0][len("subject:"):].strip()
        subject = subject_line
        body = "\n".join(lines[1:]).strip()
        # Remove leading blank lines
        body = body.lstrip("\n").strip()
    
    if not subject:
        # Generate fallback subject
        subject = f"Quick question — {contact.get('company', 'your company')}"

    return subject, body


def _score_draft(subject: str, body: str, contact: dict, profile: dict) -> tuple[float, list]:
    """Simple heuristic quality scorer. Returns (score 0-100, list of issues)."""
    issues = []
    score = 100.0

    # Check length
    word_count = len(body.split())
    if word_count > 200:
        issues.append({"type": "length", "message": f"Too long ({word_count} words). Keep under 150."})
        score -= 20

    # Check banned phrases
    banned = [
        "i hope this finds you well",
        "i am writing to",
        "please find attached",
        "leverage",
        "synergy",
        "passionate about",
        "reach out to me",
    ]
    text_lower = (subject + " " + body).lower()
    for phrase in banned:
        if phrase in text_lower:
            issues.append({"type": "generic_phrase", "message": f'Avoid generic phrase: "{phrase}"'})
            score -= 10

    # Subject line checks
    if len(subject) > 60:
        issues.append({"type": "subject_length", "message": "Subject too long (>60 chars)"})
        score -= 5
    if "?" in subject:
        pass  # Questions are good
    if subject.isupper():
        issues.append({"type": "subject_case", "message": "Subject is ALL CAPS — looks spammy"})
        score -= 15

    # Check for personalization signals
    company = contact.get("company", "")
    name = contact.get("first_name", "")
    if company and company.lower() not in body.lower():
        issues.append({"type": "personalization", "message": "Company name not mentioned in body"})
        score -= 10
    if name and name.lower() not in body.lower():
        issues.append({"type": "personalization", "message": "Recipient name not used"})
        score -= 5

    # Check for a call-to-action
    cta_signals = ["call", "chat", "connect", "15 min", "quick", "question", "thoughts", "open to"]
    if not any(s in body.lower() for s in cta_signals):
        issues.append({"type": "cta", "message": "No clear call-to-action found"})
        score -= 15

    return max(0.0, score), issues
