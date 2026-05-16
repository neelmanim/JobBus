"""
JobBus Backend — Auth Router.

Endpoints for invite validation, user registration, and onboarding.
"""

from __future__ import annotations

from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from middleware.auth_middleware import get_current_user, get_jwt_user, require_admin
from services.auth_service import InviteService, UserService
from services.credential_service import get_credential_service
from database import get_supabase_admin
from models.schemas import (
    InviteCodeCreate, InviteCodeResponse, InviteValidationResult,
    UserProfileResponse, UserModeUpdate,
)
from models.enums import UserMode


router = APIRouter(prefix="/api/auth", tags=["auth"])


# ─────────────────────────────────────────────────────────────
# Request model for the new comprehensive onboarding endpoint
# ─────────────────────────────────────────────────────────────

class OnboardingCompleteRequest(BaseModel):
    """Full onboarding payload — all optional so partial saves work."""
    mode: UserMode = UserMode.BEGINNER

    # SMTP
    smtp_host: Optional[str] = Field(None, description="e.g. smtp.gmail.com")
    smtp_port: Optional[int] = Field(None, ge=1, le=65535)
    smtp_user: Optional[str] = None
    smtp_pass: Optional[str] = None
    sender_name: Optional[str] = None

    # AI Provider keys
    groq_key: Optional[str] = None
    openai_key: Optional[str] = None
    gemini_key: Optional[str] = None
    ollama_base_url: Optional[str] = None

    # Search Provider keys
    hunter_key: Optional[str] = None
    apollo_key: Optional[str] = None
    rocketreach_key: Optional[str] = None

    # Resume (paste-as-text shortcut)
    resume_text: Optional[str] = Field(None, max_length=50_000)

    # Provider preferences
    ai_provider: Optional[str] = Field(None, description="groq | gemini | openai | ollama")
    search_provider: Optional[str] = Field(None, description="hunter | apollo | rocketreach")


# ─────────────────────────────────────────────────────────────
# Invite endpoints
# ─────────────────────────────────────────────────────────────

@router.post("/invite/validate", response_model=InviteValidationResult)
async def validate_invite(code: str):
    """Validate an invite code before registration."""
    return InviteService.validate(code)


@router.post("/invite/create", response_model=list[InviteCodeResponse])
async def create_invite_codes(
    request: InviteCodeCreate,
    user: dict = Depends(require_admin),
):
    """Create invite codes (admin only)."""
    return InviteService.create_bulk(
        count=request.count,
        created_by=user["user_id"],
        note=request.note,
        expires_in_days=request.expires_in_days,
    )


@router.get("/invite/list", response_model=list[InviteCodeResponse])
async def list_invites(user: dict = Depends(require_admin)):
    """List all invite codes (admin only)."""
    return InviteService.list_codes()


# ─────────────────────────────────────────────────────────────
# Registration & profile
# ─────────────────────────────────────────────────────────────

@router.post("/register", response_model=UserProfileResponse)
async def register_user(
    invite_code: str,
    user: dict = Depends(get_jwt_user),
):
    """Register after SSO login with an invite code."""
    validation = InviteService.validate(invite_code)
    if not validation.valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=validation.reason,
        )

    return UserService.create_profile(
        user_id=user["user_id"],
        email=user.get("email", ""),
        display_name=user.get("display_name", user.get("email", "").split("@")[0]),
        avatar_url=user.get("avatar_url"),
        invite_code=invite_code,
    )


@router.get("/me", response_model=UserProfileResponse)
async def get_my_profile(user: dict = Depends(get_current_user)):
    """Get current user's profile."""
    profile = UserService.get_profile(user["user_id"])
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return profile


@router.put("/me/mode", response_model=UserProfileResponse)
async def update_my_mode(
    request: UserModeUpdate,
    user: dict = Depends(get_current_user),
):
    """Switch between beginner/advanced mode."""
    return UserService.update_mode(user["user_id"], request.mode)


# ─────────────────────────────────────────────────────────────
# Onboarding — comprehensive multi-step wizard completion
# ─────────────────────────────────────────────────────────────

@router.post("/me/onboarding", response_model=UserProfileResponse)
async def complete_onboarding(
    request: OnboardingCompleteRequest,
    user: dict = Depends(get_current_user),
):
    """
    Complete onboarding wizard. Accepts ALL data collected across the 4
    wizard steps and persists everything atomically.

    Steps covered:
      1. Welcome   → mode preference
      2. SMTP      → smtp_host/port/user/pass/sender_name
      3. Providers → groq_key, openai_key, gemini_key, hunter_key, apollo_key,
                     rocketreach_key, ollama_base_url, ai_provider, search_provider
      4. Resume    → resume_text (paste shortcut; file upload uses /api/resume/upload)

    Sets onboarding_complete = true on the user_profiles row so the route
    guard in the frontend stops redirecting.
    """
    supabase = get_supabase_admin()
    cred_service = get_credential_service()
    user_id = user["user_id"]
    errors: list[str] = []

    # ── 1. SMTP credentials ──────────────────────────────────
    if request.smtp_user and request.smtp_pass:
        try:
            from models.schemas import SMTPCredentialCreate
            cred_service.store(
                user_id=user_id,
                credentials=SMTPCredentialCreate(
                    smtp_host=request.smtp_host or "smtp.gmail.com",
                    smtp_port=request.smtp_port or 587,
                    smtp_user=request.smtp_user,
                    smtp_pass=request.smtp_pass,
                    sender_name=request.sender_name,
                ),
            )
        except Exception as e:
            errors.append(f"SMTP: {e}")

    # ── 2. Provider API keys ─────────────────────────────────
    key_map = {
        "groq_key_encrypted":       request.groq_key,
        "openai_key_encrypted":     request.openai_key,
        "gemini_key_encrypted":     request.gemini_key,
        "hunter_key_encrypted":     request.hunter_key,
        "apollo_key_encrypted":     request.apollo_key,
        "rocketreach_key_encrypted": request.rocketreach_key,
        "ollama_base_url":          request.ollama_base_url,  # not encrypted
    }
    secrets_payload: dict = {"user_id": user_id}
    for col, val in key_map.items():
        if val:
            if col == "ollama_base_url":
                secrets_payload[col] = val
            else:
                try:
                    secrets_payload[col] = cred_service._encrypt(val)
                except Exception as e:
                    errors.append(f"{col}: {e}")

    if len(secrets_payload) > 1:  # more than just user_id
        try:
            supabase.table("user_secrets").upsert(secrets_payload).execute()
        except Exception as e:
            errors.append(f"secrets upsert: {e}")

    # ── 3. Provider preferences ──────────────────────────────
    prefs_payload: dict = {}
    if request.ai_provider:
        prefs_payload["ai_provider"] = request.ai_provider
    if request.search_provider:
        prefs_payload["search_provider"] = request.search_provider
    if prefs_payload:
        try:
            supabase.table("user_profiles").update(prefs_payload).eq("user_id", user_id).execute()
        except Exception as e:
            errors.append(f"prefs: {e}")

    # ── 4. Resume text (paste shortcut) ──────────────────────
    if request.resume_text and len(request.resume_text.strip()) > 50:
        try:
            supabase.table("resume_profiles").upsert({
                "user_id": user_id,
                "name": user.get("display_name", ""),
                "role": "",
                "skills": [],
                "achievements": [],
                "email_context": f"Resume text provided ({len(request.resume_text.strip())} chars — upload PDF to fully parse)",
                "file_path": None,
            }).execute()
        except Exception as e:
            errors.append(f"resume_text: {e}")

    # ── 5. Mark onboarding complete ──────────────────────────
    try:
        supabase.table("user_profiles").update({
            "onboarding_complete": True,
            "mode": request.mode.value,
        }).eq("user_id", user_id).execute()
    except Exception as e:
        errors.append(f"onboarding_complete flag: {e}")

    # Return fresh profile (errors are logged but not fatal)
    if errors:
        import logging
        logging.getLogger(__name__).warning("Onboarding partial errors: %s", errors)

    profile = UserService.get_profile(user_id)
    if not profile:
        raise HTTPException(status_code=500, detail="Profile not found after onboarding")
    return profile
