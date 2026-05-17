"""
JobBus Backend — Settings Router (v2).

SMTP + AI Provider + Contact Search + Campaign Defaults + Email Style.
"""

from __future__ import annotations

import logging
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from middleware.auth_middleware import get_current_user
from services.credential_service import get_credential_service
from models.schemas import SMTPCredentialCreate, SMTPCredentialStatus
from database import get_supabase_admin

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/settings", tags=["settings"])


# ─────────────────────────────────────────────────────────────
# Pydantic models for new settings endpoints
# ─────────────────────────────────────────────────────────────

class ProviderKeyRequest(BaseModel):
    field: str = Field(..., description=(
        "groq_key | openai_key | gemini_key | "
        "hunter_key | apollo_key | rocketreach_key | ollama_base_url"
    ))
    value: str = Field(..., min_length=1, max_length=2048)


class AIProviderPreference(BaseModel):
    ai_provider: str = Field(..., alias="ai_provider", description="groq | gemini | openai | ollama")
    model: str = Field("auto", description="auto | fast | quality | or raw model ID")

    model_config = {"populate_by_name": True}


class SearchProviderPreference(BaseModel):
    search_provider: str = Field(..., alias="search_provider", description="hunter | apollo | rocketreach")

    model_config = {"populate_by_name": True}


class EmailStyleRequest(BaseModel):
    signature_name: Optional[str] = None
    signature_title: Optional[str] = None
    signature_linkedin: Optional[str] = None
    custom_instructions: Optional[str] = None


class CampaignDefaultsRequest(BaseModel):
    send_delay_seconds: Optional[int] = Field(None, ge=60, le=3600)
    max_emails_per_day: Optional[int] = Field(None, ge=1, le=100)
    business_hours_only: Optional[bool] = None


# ─────────────────────────────────────────────────────────────
# SMTP (existing endpoints preserved)
# ─────────────────────────────────────────────────────────────

@router.get("/smtp/status", response_model=SMTPCredentialStatus)
async def get_smtp_status(user: dict = Depends(get_current_user)):
    """Check SMTP credential configuration status (no secrets exposed)."""
    return get_credential_service().get_status(user["user_id"])


@router.post("/smtp/configure")
async def configure_smtp(
    request: SMTPCredentialCreate,
    user: dict = Depends(get_current_user),
):
    """Store encrypted SMTP credentials."""
    get_credential_service().store(user["user_id"], request)
    return {"message": "SMTP credentials saved successfully"}


@router.delete("/smtp")
async def delete_smtp(user: dict = Depends(get_current_user)):
    """Delete stored SMTP credentials."""
    get_credential_service().delete(user["user_id"])
    return {"message": "SMTP credentials deleted"}


@router.post("/smtp/test")
async def test_smtp(user: dict = Depends(get_current_user)):
    """Test SMTP connectivity by sending a test email to self."""
    from services.smtp_sender import get_smtp_sender

    try:
        creds = get_credential_service().get_decrypted(user["user_id"])
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    sender = get_smtp_sender()
    result = await sender.send(
        user_id=user["user_id"],
        to_email=creds["smtp_user"],
        subject="JobBus — SMTP Test ✓",
        body="Your email configuration is working correctly. You're all set!",
    )

    if result.success:
        return {"message": "Test email sent successfully!", "to": creds["smtp_user"]}
    else:
        raise HTTPException(
            status_code=400,
            detail=f"SMTP test failed: {result.error_message}",
        )


# ─────────────────────────────────────────────────────────────
# Provider Keys — Save / Delete / Status / Test
# ─────────────────────────────────────────────────────────────

@router.get("/providers/status")
async def get_provider_status(user: dict = Depends(get_current_user)):
    """
    Return which provider keys are configured.
    Returns booleans — no secrets are ever returned.
    Also returns user's current AI and search provider preference.
    """
    cred = get_credential_service()
    key_status = cred.get_provider_status(user["user_id"])

    supabase = get_supabase_admin()
    profile_result = supabase.table("user_profiles").select(
        "ai_provider, ai_model, search_provider"
    ).eq("user_id", user["user_id"]).single().execute()
    profile = profile_result.data or {}

    # Check if a system-level Groq key is configured (enables Beginner mode)
    system_groq_result = supabase.table("system_config").select("value").eq("key", "system_groq_key").execute()
    system_groq_available = bool(
        system_groq_result.data and system_groq_result.data[0].get("value")
    )

    return {
        **key_status,
        "ai_provider": profile.get("ai_provider", "groq"),
        "ai_model": profile.get("ai_model", "auto"),
        "search_provider": profile.get("search_provider", "hunter"),
        "system_groq_available": system_groq_available,
    }


@router.post("/providers/key")
async def save_provider_key(
    request: ProviderKeyRequest,
    user: dict = Depends(get_current_user),
):
    """Save an encrypted API key for any provider."""
    valid_fields = {
        "groq_key", "openai_key", "gemini_key",
        "hunter_key", "apollo_key", "rocketreach_key",
        "ollama_base_url",
    }
    if request.field not in valid_fields:
        raise HTTPException(
            status_code=422,
            detail=f"Unknown provider field. Valid options: {valid_fields}"
        )

    get_credential_service().store_provider_key(
        user_id=user["user_id"],
        field=request.field,
        value=request.value,
    )
    return {"message": f"{request.field.replace('_', ' ').title()} saved successfully"}


@router.delete("/providers/key/{field}")
async def delete_provider_key(field: str, user: dict = Depends(get_current_user)):
    """Remove a stored provider key."""
    get_credential_service().store_provider_key(
        user_id=user["user_id"],
        field=field,
        value="",  # store empty = effectively delete
    )
    return {"message": f"{field} cleared"}


@router.post("/providers/test")
async def test_provider(
    field: str,  # groq_key | hunter_key | etc.
    user: dict = Depends(get_current_user),
):
    """
    Test connectivity for a specific provider using the stored key.
    Returns success/failure without exposing the key.
    """
    cred = get_credential_service()
    user_id = user["user_id"]

    provider_map = {
        "groq_key": _test_groq,
        "openai_key": _test_openai,
        "gemini_key": _test_gemini,
        "hunter_key": _test_hunter,
        "apollo_key": _test_apollo,
        "rocketreach_key": _test_rocketreach,
        "ollama_base_url": _test_ollama,
    }

    test_fn = provider_map.get(field)
    if not test_fn:
        raise HTTPException(status_code=422, detail=f"Unknown provider: {field}")

    try:
        key_or_url = cred.get_decrypted_field(user_id, field)
        if not key_or_url:
            raise HTTPException(status_code=400, detail="No key stored for this provider")

        ok = await test_fn(key_or_url)
        if ok:
            return {"success": True, "message": "Connection successful!"}
        else:
            return {"success": False, "message": "Connection test failed — check your API key"}
    except HTTPException:
        raise
    except Exception as e:
        return {"success": False, "message": str(e)}


# ─────────────────────────────────────────────────────────────
# Provider Preferences
# ─────────────────────────────────────────────────────────────

@router.put("/ai-provider")
async def set_ai_provider(
    request: AIProviderPreference,
    user: dict = Depends(get_current_user),
):
    """Set user's preferred AI provider and model tier."""
    valid_providers = {"groq", "gemini", "openai", "ollama"}
    if request.ai_provider not in valid_providers:
        raise HTTPException(status_code=422, detail=f"Provider must be one of: {valid_providers}")

    supabase = get_supabase_admin()
    supabase.table("user_profiles").update({
        "ai_provider": request.ai_provider,
        "ai_model": request.model,
    }).eq("user_id", user["user_id"]).execute()

    return {"ai_provider": request.ai_provider, "ai_model": request.model}


@router.put("/search-provider")
async def set_search_provider(
    request: SearchProviderPreference,
    user: dict = Depends(get_current_user),
):
    """Set user's preferred contact search provider."""
    valid_providers = {"hunter", "apollo", "rocketreach"}
    if request.search_provider not in valid_providers:
        raise HTTPException(status_code=422, detail=f"Provider must be one of: {valid_providers}")

    supabase = get_supabase_admin()
    supabase.table("user_profiles").update({
        "search_provider": request.search_provider,
    }).eq("user_id", user["user_id"]).execute()

    return {"search_provider": request.search_provider}


# ─────────────────────────────────────────────────────────────
# Email Style & Signature
# ─────────────────────────────────────────────────────────────

@router.get("/email-style")
async def get_email_style(user: dict = Depends(get_current_user)):
    """Get user's email style preferences and signature."""
    supabase = get_supabase_admin()
    result = supabase.table("user_profiles").select(
        "signature_name, signature_title, signature_linkedin, custom_instructions"
    ).eq("user_id", user["user_id"]).single().execute()
    return result.data or {}


@router.put("/email-style")
async def update_email_style(
    request: EmailStyleRequest,
    user: dict = Depends(get_current_user),
):
    """Update email style preferences and signature."""
    update_data = {k: v for k, v in request.model_dump().items() if v is not None}
    if not update_data:
        raise HTTPException(status_code=422, detail="No fields to update")

    supabase = get_supabase_admin()
    supabase.table("user_profiles").update(update_data).eq("user_id", user["user_id"]).execute()
    return {"message": "Email style updated", "updated": list(update_data.keys())}


# ─────────────────────────────────────────────────────────────
# Campaign Defaults
# ─────────────────────────────────────────────────────────────

@router.get("/campaign-defaults")
async def get_campaign_defaults(user: dict = Depends(get_current_user)):
    """Get user's default campaign send settings."""
    supabase = get_supabase_admin()
    result = supabase.table("user_profiles").select(
        "send_delay_seconds, max_emails_per_day, business_hours_only"
    ).eq("user_id", user["user_id"]).single().execute()
    return result.data or {}


@router.put("/campaign-defaults")
async def update_campaign_defaults(
    request: CampaignDefaultsRequest,
    user: dict = Depends(get_current_user),
):
    """Update default campaign send settings."""
    update_data = {k: v for k, v in request.model_dump().items() if v is not None}
    if not update_data:
        raise HTTPException(status_code=422, detail="No fields to update")

    supabase = get_supabase_admin()
    supabase.table("user_profiles").update(update_data).eq("user_id", user["user_id"]).execute()
    return {"message": "Campaign defaults updated", "updated": list(update_data.keys())}


# ─────────────────────────────────────────────────────────────
# Provider connection test helpers
# ─────────────────────────────────────────────────────────────

async def _test_groq(key: str) -> bool:
    from providers.ai.groq_provider import GroqAIProvider
    return await GroqAIProvider(key).test_connection()


async def _test_openai(key: str) -> bool:
    from providers.ai.openai_provider import OpenAIProvider
    return await OpenAIProvider(key).test_connection()


async def _test_gemini(key: str) -> bool:
    from providers.ai.gemini_provider import GeminiAIProvider
    return await GeminiAIProvider(key).test_connection()


async def _test_hunter(key: str) -> bool:
    from providers.search.hunter import HunterSearchProvider
    return await HunterSearchProvider(key).test_connection()


async def _test_apollo(key: str) -> bool:
    from providers.search.apollo import ApolloSearchProvider
    return await ApolloSearchProvider(key).test_connection()


async def _test_rocketreach(key: str) -> bool:
    from providers.search.rocketreach import RocketReachSearchProvider
    return await RocketReachSearchProvider(key).test_connection()


async def _test_ollama(url: str) -> bool:
    from providers.ai.ollama_provider import OllamaProvider
    return await OllamaProvider(base_url=url).test_connection()
