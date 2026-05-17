"""
JobBus Backend — Contacts Router.

CRUD for contacts + contact search via provider waterfall.
This is the missing router that blocked the Step 3 workflow.
"""

from __future__ import annotations

import re
import logging
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel, EmailStr, Field
from typing import Optional
import csv
import io

from middleware.auth_middleware import get_current_user
from services.credential_service import get_credential_service
from providers.search.factory import get_search_provider, waterfall_search
from providers.search.base import classify_persona
from database import get_supabase_admin

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/contacts", tags=["contacts"])


# ─────────────────────────────────────────────────────────────
# Pydantic models
# ─────────────────────────────────────────────────────────────

class ContactCreate(BaseModel):
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field("", max_length=100)
    email: str = Field(..., description="Contact email address")
    title: str = Field("", max_length=200)
    company: str = Field("", max_length=200)
    linkedin_url: Optional[str] = None
    opportunity_id: Optional[str] = None
    persona_type: Optional[str] = None

    def model_post_init(self, __context):
        # Auto-classify persona if not provided
        if not self.persona_type and self.title:
            self.persona_type = classify_persona(self.title)


class ContactResponse(BaseModel):
    id: str
    first_name: str
    last_name: str
    email: str
    title: str
    company: str
    persona_type: str
    source: str
    confidence_score: Optional[float] = None
    linkedin_url: Optional[str] = None
    opportunity_id: Optional[str] = None


class FindContactRequest(BaseModel):
    opportunity_id: Optional[str] = None  # None is valid — campaign may not have an opportunity
    company: str
    domain: str
    target_titles: Optional[list[str]] = None
    limit: int = Field(5, ge=1, le=10)
    use_waterfall: bool = True  # try all providers if primary fails


class FindContactResponse(BaseModel):
    contacts: list[ContactResponse]
    provider_used: str
    total_found: int
    saved_count: int


# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _validate_email(email: str) -> bool:
    return bool(_EMAIL_RE.match(email.strip()))


def _row_to_contact(row: dict) -> ContactResponse:
    return ContactResponse(
        id=row["id"],
        first_name=row.get("first_name", ""),
        last_name=row.get("last_name", ""),
        email=row["email"],
        title=row.get("title", ""),
        company=row.get("company", ""),
        persona_type=row.get("persona_type", "other"),
        source=row.get("source", "manual"),
        confidence_score=row.get("confidence_score"),
        linkedin_url=row.get("linkedin_url"),
        opportunity_id=row.get("opportunity_id"),
    )


# ─────────────────────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────────────────────

@router.get("/", response_model=list[ContactResponse])
async def list_contacts(
    opportunity_id: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    """List all contacts for the current user, optionally filtered by opportunity."""
    supabase = get_supabase_admin()
    q = supabase.table("contacts").select("*").eq("user_id", user["user_id"])
    if opportunity_id:
        q = q.eq("opportunity_id", opportunity_id)
    result = q.order("created_at", desc=True).execute()
    return [_row_to_contact(r) for r in result.data]


@router.post("/", response_model=ContactResponse, status_code=201)
async def create_contact(
    request: ContactCreate,
    user: dict = Depends(get_current_user),
):
    """Manually add a single contact."""
    if not _validate_email(request.email):
        raise HTTPException(status_code=422, detail="Invalid email address format")

    supabase = get_supabase_admin()

    # Deduplicate: check if email already exists for this user
    existing = supabase.table("contacts").select("id").eq("user_id", user["user_id"]).eq("email", request.email.lower()).execute()
    if existing.data:
        raise HTTPException(status_code=409, detail="A contact with this email already exists")

    insert_data = {
        "user_id": user["user_id"],
        "first_name": request.first_name,
        "last_name": request.last_name,
        "email": request.email.lower().strip(),
        "title": request.title,
        "company": request.company,
        "linkedin_url": request.linkedin_url,
        "persona_type": request.persona_type or classify_persona(request.title),
        "source": "manual",
        "opportunity_id": request.opportunity_id,
    }

    result = supabase.table("contacts").insert(insert_data).execute()
    return _row_to_contact(result.data[0])


@router.post("/bulk", response_model=list[ContactResponse], status_code=201)
async def bulk_create_contacts(
    contacts: list[ContactCreate],
    user: dict = Depends(get_current_user),
):
    """Add multiple contacts at once (manual paste / CSV paste)."""
    if not contacts:
        raise HTTPException(status_code=422, detail="No contacts provided")
    if len(contacts) > 200:
        raise HTTPException(status_code=422, detail="Maximum 200 contacts per bulk import")

    supabase = get_supabase_admin()
    user_id = user["user_id"]

    # Get existing emails to deduplicate
    existing_result = supabase.table("contacts").select("email").eq("user_id", user_id).execute()
    existing_emails = {r["email"].lower() for r in existing_result.data}

    to_insert = []
    skipped = 0
    for c in contacts:
        email = c.email.lower().strip()
        if not _validate_email(email) or email in existing_emails:
            skipped += 1
            continue
        existing_emails.add(email)
        to_insert.append({
            "user_id": user_id,
            "first_name": c.first_name,
            "last_name": c.last_name,
            "email": email,
            "title": c.title,
            "company": c.company,
            "linkedin_url": c.linkedin_url,
            "persona_type": c.persona_type or classify_persona(c.title),
            "source": "manual",
            "opportunity_id": c.opportunity_id,
        })

    if not to_insert:
        raise HTTPException(status_code=409, detail=f"All {skipped} contacts already exist or have invalid emails")

    result = supabase.table("contacts").insert(to_insert).execute()
    return [_row_to_contact(r) for r in result.data]


@router.post("/import-csv", response_model=list[ContactResponse], status_code=201)
async def import_csv(
    file: UploadFile = File(...),
    opportunity_id: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    """Import contacts from a CSV file. Expects: first_name, last_name, email, title, company."""
    if not file.filename or not file.filename.endswith(".csv"):
        raise HTTPException(status_code=422, detail="Only CSV files are supported")

    content = await file.read()
    try:
        text = content.decode("utf-8-sig")  # handle BOM
    except UnicodeDecodeError:
        text = content.decode("latin-1")

    reader = csv.DictReader(io.StringIO(text))
    contacts = []
    for row in reader:
        email = row.get("email") or row.get("Email") or row.get("EMAIL") or ""
        if not _validate_email(email):
            continue
        contacts.append(ContactCreate(
            first_name=row.get("first_name") or row.get("First Name") or "",
            last_name=row.get("last_name") or row.get("Last Name") or "",
            email=email,
            title=row.get("title") or row.get("Title") or "",
            company=row.get("company") or row.get("Company") or "",
            linkedin_url=row.get("linkedin_url") or row.get("LinkedIn") or None,
            opportunity_id=opportunity_id,
        ))

    if not contacts:
        raise HTTPException(status_code=422, detail="No valid contacts found in CSV")

    return await bulk_create_contacts(contacts, user)


@router.delete("/{contact_id}")
async def delete_contact(contact_id: str, user: dict = Depends(get_current_user)):
    """Delete a contact."""
    supabase = get_supabase_admin()
    result = supabase.table("contacts").select("id").eq("id", contact_id).eq("user_id", user["user_id"]).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Contact not found")
    supabase.table("contacts").delete().eq("id", contact_id).execute()
    return {"deleted": contact_id}


@router.post("/find", response_model=FindContactResponse)
async def find_contact(
    request: FindContactRequest,
    user: dict = Depends(get_current_user),
):
    """
    Find contacts at a company using the waterfall search cascade.
    Hunter → Apollo → RocketReach — uses first provider that returns results.
    Results are saved to the contacts table automatically.
    """
    if request.use_waterfall:
        results, provider_used = await waterfall_search(
            user=user,
            company=request.company,
            domain=request.domain,
            target_titles=request.target_titles,
            limit=request.limit,
        )
    else:
        provider = get_search_provider(user)
        results = await provider.find_contacts(
            company=request.company,
            domain=request.domain,
            target_titles=request.target_titles,
            limit=request.limit,
        )
        provider_used = provider.provider_name

    if not results:
        return FindContactResponse(
            contacts=[], provider_used=provider_used, total_found=0, saved_count=0
        )

    # Save found contacts to DB (deduplicate on email)
    supabase = get_supabase_admin()
    user_id = user["user_id"]

    existing_result = supabase.table("contacts").select("email").eq("user_id", user_id).execute()
    existing_emails = {r["email"].lower() for r in existing_result.data}

    to_insert = []
    for r in results:
        email = r.email.lower()
        if email in existing_emails:
            continue
        existing_emails.add(email)
        to_insert.append({
            "user_id": user_id,
            "opportunity_id": request.opportunity_id,
            "first_name": r.first_name,
            "last_name": r.last_name,
            "email": email,
            "title": r.title,
            "company": r.company,
            "linkedin_url": r.linkedin_url,
            "persona_type": r.persona_type,
            "source": r.source,
            "confidence_score": r.confidence_score,
            "search_provider": r.source,
        })

    saved = 0
    saved_ids  = []
    saved_rows = []
    if to_insert:
        insert_result = supabase.table("contacts").insert(to_insert).execute()
        saved_rows = insert_result.data or []
        saved = len(saved_rows)
        saved_ids = [r["id"] for r in saved_rows]

    # Build the full contacts list to return:
    # Newly saved rows + any existing rows that matched (skipped deduplication)
    existing_rows_used = [
        r for r in existing_result.data
        if r.get("email", "").lower() in {x["email"].lower() for x in (to_insert or [])}
    ] if not saved_ids else []

    # Fetch any existing contacts for this opportunity that were already saved
    already_saved_q = supabase.table("contacts").select("*").eq("user_id", user_id)
    if request.opportunity_id:
        already_saved_q = already_saved_q.eq("opportunity_id", request.opportunity_id)
    elif saved_ids:
        already_saved_q = already_saved_q.in_("id", saved_ids)
    already_saved = already_saved_q.execute().data or []

    # Combine: new saves + previously existing for this opp
    # Prefer saved_rows (have full data) and fall back to already_saved
    all_rows = saved_rows if saved_rows else already_saved

    return FindContactResponse(
        contacts=[_row_to_contact(r) for r in all_rows],
        provider_used=provider_used,
        total_found=len(results),
        saved_count=saved,
    )
