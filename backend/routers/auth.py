"""
JobBus Backend — Auth Router.

Endpoints for invite validation, user registration, and onboarding.
"""

from __future__ import annotations


from fastapi import APIRouter, Depends, HTTPException, status

from middleware.auth_middleware import get_current_user, require_admin
from services.auth_service import InviteService, UserService
from models.schemas import (
    InviteCodeCreate, InviteCodeResponse, InviteValidationResult,
    UserProfileResponse, UserModeUpdate, OnboardingComplete,
)


router = APIRouter(prefix="/api/auth", tags=["auth"])


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


@router.post("/register", response_model=UserProfileResponse)
async def register_user(
    invite_code: str,
    user: dict = Depends(get_current_user),
):
    """Register after SSO login with an invite code."""
    # Validate invite
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


@router.post("/me/onboarding", response_model=UserProfileResponse)
async def complete_onboarding(
    request: OnboardingComplete,
    user: dict = Depends(get_current_user),
):
    """Complete onboarding with Gemini API key setup."""
    from services.credential_service import get_credential_service

    # Store Gemini API key in user_secrets
    supabase = __import__("database").get_supabase_admin()
    cred_service = get_credential_service()
    supabase.table("user_secrets").upsert({
        "user_id": user["user_id"],
        "gemini_key_encrypted": cred_service._encrypt(request.gemini_api_key),
    }).execute()

    # Update mode
    return UserService.update_mode(user["user_id"], request.mode)
