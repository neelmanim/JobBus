"""
JobBus Backend — Auth Service.

Handles invite code management and user profile creation.
Supabase handles the actual Google SSO — this service manages
the invite-only gate and user profiles layer.
"""

from __future__ import annotations


import secrets
import string
from datetime import datetime, timedelta, timezone
from typing import Optional

from database import get_supabase_admin
from models.schemas import InviteCodeResponse, InviteValidationResult, UserProfileResponse
from models.enums import UserMode


class InviteService:
    """Manages invite code creation, validation, and redemption."""

    CODE_LENGTH = 8
    CODE_CHARS = string.ascii_uppercase + string.digits

    @staticmethod
    def _generate_code() -> str:
        """Generate a random invite code (8 chars, uppercase + digits)."""
        return "".join(secrets.choice(InviteService.CODE_CHARS) for _ in range(InviteService.CODE_LENGTH))

    @staticmethod
    def create_code(
        created_by: str,
        note: Optional[str] = None,
        expires_in_days: Optional[int] = None,
    ) -> InviteCodeResponse:
        """Create a single invite code."""
        supabase = get_supabase_admin()

        expires_at = None
        if expires_in_days is not None:
            expires_at = (datetime.now(timezone.utc) + timedelta(days=expires_in_days)).isoformat()

        code = InviteService._generate_code()
        data = {
            "code": code,
            "created_by": created_by,
            "used": False,
            "note": note,
            "expires_at": expires_at,
        }

        result = supabase.table("invites").insert(data).execute()
        row = result.data[0]
        return InviteCodeResponse(
            id=row["id"],
            code=row["code"],
            created_by=row["created_by"],
            used=row["used"],
            used_by=row.get("used_by"),
            note=row.get("note"),
            expires_at=row.get("expires_at"),
            created_at=row["created_at"],
        )

    @staticmethod
    def create_bulk(
        count: int,
        created_by: str,
        note: Optional[str] = None,
        expires_in_days: Optional[int] = None,
    ) -> list[InviteCodeResponse]:
        """Create a batch of invite codes."""
        return [
            InviteService.create_code(created_by, note=note, expires_in_days=expires_in_days)
            for _ in range(count)
        ]

    @staticmethod
    def validate(code: Optional[str]) -> InviteValidationResult:
        """Validate an invite code for signup."""
        if not code:
            return InviteValidationResult(valid=False, reason="No invite code provided")

        supabase = get_supabase_admin()
        result = supabase.table("invites").select("*").eq("code", code.upper().strip()).execute()

        if not result.data:
            return InviteValidationResult(valid=False, reason="Invite code not found")

        invite = result.data[0]

        if invite["used"]:
            return InviteValidationResult(valid=False, reason="Invite code already used")

        if invite.get("expires_at"):
            expires = datetime.fromisoformat(invite["expires_at"].replace("Z", "+00:00"))
            if expires < datetime.now(timezone.utc):
                return InviteValidationResult(valid=False, reason="Invite code has expired")

        return InviteValidationResult(valid=True)

    @staticmethod
    def mark_used(code: str, used_by: str) -> None:
        """Mark an invite code as used."""
        supabase = get_supabase_admin()
        supabase.table("invites").update({
            "used": True,
            "used_by": used_by,
            "used_at": datetime.now(timezone.utc).isoformat(),
        }).eq("code", code.upper().strip()).execute()

    @staticmethod
    def list_codes(created_by: Optional[str] = None) -> list[InviteCodeResponse]:
        """List invite codes, optionally filtered by creator."""
        supabase = get_supabase_admin()
        query = supabase.table("invites").select("*").order("created_at", desc=True)
        if created_by:
            query = query.eq("created_by", created_by)
        result = query.execute()
        return [
            InviteCodeResponse(
                id=row["id"],
                code=row["code"],
                created_by=row["created_by"],
                used=row["used"],
                used_by=row.get("used_by"),
                note=row.get("note"),
                expires_at=row.get("expires_at"),
                created_at=row["created_at"],
            )
            for row in result.data
        ]


class UserService:
    """Manages user profiles (separate from Supabase auth.users)."""

    @staticmethod
    def create_profile(
        user_id: str,
        email: str,
        display_name: str,
        avatar_url: Optional[str] = None,
        invite_code: Optional[str] = None,
        mode: UserMode = UserMode.BEGINNER,
    ) -> UserProfileResponse:
        """Create a new user profile after SSO."""
        supabase = get_supabase_admin()

        # Check for existing profile
        existing = supabase.table("user_profiles").select("*").eq("user_id", user_id).execute()
        if existing.data:
            # Return existing profile (idempotent)
            row = existing.data[0]
            # Update last login
            supabase.table("user_profiles").update({
                "last_login_at": datetime.now(timezone.utc).isoformat(),
            }).eq("user_id", user_id).execute()
            return UserService._row_to_response(row)

        data = {
            "user_id": user_id,
            "email": email,
            "display_name": display_name,
            "avatar_url": avatar_url,
            "mode": mode.value,
            "is_admin": False,
            "is_active": True,
            "last_login_at": datetime.now(timezone.utc).isoformat(),
        }

        result = supabase.table("user_profiles").insert(data).execute()
        row = result.data[0]

        # Mark invite code as used
        if invite_code:
            InviteService.mark_used(invite_code, used_by=user_id)

        return UserService._row_to_response(row)

    @staticmethod
    def get_profile(user_id: str) -> Optional[UserProfileResponse]:
        """Get a user's profile."""
        supabase = get_supabase_admin()
        result = supabase.table("user_profiles").select("*").eq("user_id", user_id).execute()
        if not result.data:
            return None
        return UserService._row_to_response(result.data[0])

    @staticmethod
    def update_mode(user_id: str, mode: UserMode) -> UserProfileResponse:
        """Toggle user mode between beginner and advanced."""
        supabase = get_supabase_admin()
        result = supabase.table("user_profiles").update(
            {"mode": mode.value}
        ).eq("user_id", user_id).execute()
        return UserService._row_to_response(result.data[0])

    @staticmethod
    def update_login(user_id: str) -> None:
        """Update last login timestamp."""
        supabase = get_supabase_admin()
        supabase.table("user_profiles").update({
            "last_login_at": datetime.now(timezone.utc).isoformat(),
        }).eq("user_id", user_id).execute()

    @staticmethod
    def _row_to_response(row: dict) -> UserProfileResponse:
        return UserProfileResponse(
            user_id=row["user_id"],
            display_name=row["display_name"],
            avatar_url=row.get("avatar_url"),
            email=row.get("email", ""),
            mode=UserMode(row.get("mode", "beginner")),
            is_admin=row.get("is_admin", False),
            is_active=row.get("is_active", True),
            last_login_at=row.get("last_login_at"),
            created_at=row["created_at"],
        )
