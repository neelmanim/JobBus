"""
JobBus Backend — Admin Router.

Admin-only endpoints for user management and monitoring.
"""

from __future__ import annotations


from fastapi import APIRouter, Depends, HTTPException

from middleware.auth_middleware import require_admin
from services.admin_service import AdminService
from services.auth_service import InviteService
from models.schemas import AdminUserListItem, AdminUserActivity


router = APIRouter(prefix="/api/admin", tags=["admin"])


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
