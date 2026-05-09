"""
JobBus Backend — Admin Service.

Admin-only operations: user management, activity monitoring, and invite management.
"""

from __future__ import annotations


from typing import Optional
from database import get_supabase_admin
from models.schemas import AdminUserListItem, AdminUserActivity


class AdminService:
    """Admin operations — user management and monitoring."""

    @staticmethod
    def list_users() -> list[AdminUserListItem]:
        """List all registered users with summary stats."""
        supabase = get_supabase_admin()
        result = supabase.table("user_profiles").select("*").order("created_at", desc=True).execute()

        users = []
        for row in result.data:
            # Get campaign stats for each user
            stats = AdminService._get_user_stats(row["user_id"])
            users.append(AdminUserListItem(
                user_id=row["user_id"],
                display_name=row["display_name"],
                email=row.get("email", ""),
                mode=row.get("mode", "beginner"),
                is_active=row.get("is_active", True),
                is_admin=row.get("is_admin", False),
                last_login_at=row.get("last_login_at"),
                campaigns_count=stats.get("campaigns_count", 0),
                total_sent=stats.get("total_sent", 0),
                created_at=row["created_at"],
            ))
        return users

    @staticmethod
    def get_user_activity(user_id: str) -> AdminUserActivity:
        """Get detailed activity for a specific user."""
        supabase = get_supabase_admin()

        profile = supabase.table("user_profiles").select("*").eq("user_id", user_id).execute()
        if not profile.data:
            raise ValueError(f"User {user_id} not found")

        row = profile.data[0]
        stats = AdminService._get_user_stats(user_id)

        return AdminUserActivity(
            user_id=row["user_id"],
            display_name=row["display_name"],
            last_login_at=row.get("last_login_at"),
            campaigns_count=stats.get("campaigns_count", 0),
            total_sent=stats.get("total_sent", 0),
            total_replies=stats.get("total_replies", 0),
            total_interviews=stats.get("total_interviews", 0),
            active_campaigns=stats.get("active_campaigns", 0),
        )

    @staticmethod
    def deactivate_user(user_id: str) -> None:
        """Deactivate a user (blocks API access)."""
        supabase = get_supabase_admin()
        supabase.table("user_profiles").update(
            {"is_active": False}
        ).eq("user_id", user_id).execute()

    @staticmethod
    def reactivate_user(user_id: str) -> None:
        """Reactivate a previously deactivated user."""
        supabase = get_supabase_admin()
        supabase.table("user_profiles").update(
            {"is_active": True}
        ).eq("user_id", user_id).execute()

    @staticmethod
    def _get_user_stats(user_id: str) -> dict:
        """Get campaign stats for a user."""
        supabase = get_supabase_admin()
        try:
            campaigns = supabase.table("campaigns").select("id, status").eq("user_id", user_id).execute()
            campaign_ids = [c["id"] for c in campaigns.data] if campaigns.data else []

            total_sent = 0
            total_replies = 0
            total_interviews = 0
            active_campaigns = 0

            for c in (campaigns.data or []):
                if c["status"] in ("sending", "reviewing", "approved"):
                    active_campaigns += 1

            if campaign_ids:
                contacts = supabase.table("campaign_contacts").select(
                    "status"
                ).in_("campaign_id", campaign_ids).execute()

                for contact in (contacts.data or []):
                    if contact["status"] == "sent":
                        total_sent += 1
                    elif contact["status"] == "replied":
                        total_sent += 1
                        total_replies += 1
                    elif contact["status"] == "interview":
                        total_sent += 1
                        total_replies += 1
                        total_interviews += 1

            return {
                "campaigns_count": len(campaigns.data) if campaigns.data else 0,
                "total_sent": total_sent,
                "total_replies": total_replies,
                "total_interviews": total_interviews,
                "active_campaigns": active_campaigns,
            }
        except Exception:
            # Tables may not exist yet during early setup
            return {"campaigns_count": 0, "total_sent": 0, "total_replies": 0,
                    "total_interviews": 0, "active_campaigns": 0}
