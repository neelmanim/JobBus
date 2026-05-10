"""
JobBus Backend — Admin Router.

Admin-only endpoints: user management, platform config, and usage analytics.
"""

from __future__ import annotations

from typing import Any, Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from middleware.auth_middleware import require_admin
from services.admin_service import AdminService
from services.auth_service import InviteService
from models.schemas import AdminUserListItem, AdminUserActivity


router = APIRouter(prefix="/api/admin", tags=["admin"])


# ─────────────────────────────────────────────────────────────
# Request/response models
# ─────────────────────────────────────────────────────────────

class SystemConfigUpdate(BaseModel):
    """Platform-wide configuration update."""
    system_groq_key: Optional[str] = Field(None, description="System-level Groq fallback key")
    system_hunter_key: Optional[str] = Field(None, description="System-level Hunter fallback key")
    max_emails_per_user_per_day: Optional[str] = Field(None, description="Integer as string")
    enable_follow_ups: Optional[str] = Field(None, description="'true' | 'false'")
    enable_ollama: Optional[str] = Field(None, description="'true' | 'false'")


class PlatformUsageResponse(BaseModel):
    """Aggregate platform usage stats."""
    total_users: int = 0
    total_campaigns: int = 0
    total_emails_sent: int = 0
    total_contacts: int = 0
    reply_rate: Optional[float] = None
    top_users: list[dict[str, Any]] = []


# ─────────────────────────────────────────────────────────────
# User management
# ─────────────────────────────────────────────────────────────

@router.get("/users", response_model=list[AdminUserListItem])
async def list_users(user: dict = Depends(require_admin)):
    """List all registered users with stats."""
    return AdminService.list_users()


@router.get("/users/{user_id}/activity", response_model=AdminUserActivity)
async def get_user_activity(user_id: str, user: dict = Depends(require_admin)):
    """Get detailed activity for a specific user."""
    try:
        return AdminService.get_user_activity(user_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="User not found")


@router.post("/users/{user_id}/deactivate")
async def deactivate_user(user_id: str, user: dict = Depends(require_admin)):
    """Deactivate a user (blocks their API access)."""
    if user_id == user["user_id"]:
        raise HTTPException(status_code=400, detail="Cannot deactivate yourself")
    AdminService.deactivate_user(user_id)
    return {"message": f"User {user_id} deactivated"}


@router.post("/users/{user_id}/reactivate")
async def reactivate_user(user_id: str, user: dict = Depends(require_admin)):
    """Reactivate a deactivated user."""
    AdminService.reactivate_user(user_id)
    return {"message": f"User {user_id} reactivated"}


# ─────────────────────────────────────────────────────────────
# Platform configuration  (system_config table)
# ─────────────────────────────────────────────────────────────

CONFIG_KEYS = {
    "system_groq_key",
    "system_hunter_key",
    "max_emails_per_user_per_day",
    "enable_follow_ups",
    "enable_ollama",
}


@router.get("/config")
async def get_platform_config(user: dict = Depends(require_admin)):
    """
    Read system-wide configuration from system_config table.
    Sensitive key values are returned masked (first 8 chars + ***).
    """
    return AdminService.get_system_config(mask_secrets=True)


@router.put("/config")
async def save_platform_config(
    request: SystemConfigUpdate,
    user: dict = Depends(require_admin),
):
    """
    Upsert system-wide configuration rows.
    Only non-None fields in the request are written.
    """
    updates: dict[str, str] = {}
    for key in CONFIG_KEYS:
        val = getattr(request, key, None)
        if val is not None:
            updates[key] = val

    if not updates:
        raise HTTPException(status_code=400, detail="No config fields provided")

    AdminService.save_system_config(updates)
    return {"message": "Config saved", "updated_keys": list(updates.keys())}


# ─────────────────────────────────────────────────────────────
# Platform usage analytics
# ─────────────────────────────────────────────────────────────

@router.get("/usage", response_model=PlatformUsageResponse)
async def get_platform_usage(user: dict = Depends(require_admin)):
    """
    Return aggregate platform-wide usage statistics.
    Includes total users, campaigns, emails sent, contacts found,
    reply rate, and a leaderboard of top users by emails sent.
    """
    return AdminService.get_platform_usage()
