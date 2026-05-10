"""
JobBus Backend — Admin Service.

Admin-only operations: user management, system config, and usage analytics.
"""

from __future__ import annotations

import logging
from typing import Any, Optional
from database import get_supabase_admin
from models.schemas import AdminUserListItem, AdminUserActivity

logger = logging.getLogger(__name__)

# Keys that contain secrets — mask in GET responses
_SECRET_KEYS = {"system_groq_key", "system_hunter_key"}


class AdminService:
    """Admin operations — user management, config, and monitoring."""

    # ─────────────────────────────────────────────────────────
    # User management
    # ─────────────────────────────────────────────────────────

    @staticmethod
    def list_users() -> list[AdminUserListItem]:
        """List all registered users with summary stats."""
        supabase = get_supabase_admin()
        result = supabase.table("user_profiles").select("*").order("created_at", desc=True).execute()

        users = []
        for row in result.data:
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
                    s = contact["status"]
                    if s in ("sent", "replied", "interview"):
                        total_sent += 1
                    if s in ("replied", "interview"):
                        total_replies += 1
                    if s == "interview":
                        total_interviews += 1

            return {
                "campaigns_count": len(campaigns.data) if campaigns.data else 0,
                "total_sent": total_sent,
                "total_replies": total_replies,
                "total_interviews": total_interviews,
                "active_campaigns": active_campaigns,
            }
        except Exception:
            return {"campaigns_count": 0, "total_sent": 0, "total_replies": 0,
                    "total_interviews": 0, "active_campaigns": 0}

    # ─────────────────────────────────────────────────────────
    # System config  (system_config table: key / value rows)
    # ─────────────────────────────────────────────────────────

    @staticmethod
    def get_system_config(mask_secrets: bool = True) -> dict[str, str]:
        """
        Read all rows from system_config and return as a flat dict.
        Secret keys are masked if mask_secrets=True.
        """
        supabase = get_supabase_admin()
        try:
            rows = supabase.table("system_config").select("key, value").execute()
            config: dict[str, str] = {}
            for row in (rows.data or []):
                k = row["key"]
                v = row.get("value", "")
                if mask_secrets and k in _SECRET_KEYS and v:
                    # Show first 8 chars then *** so admins can tell a key is set
                    config[k] = v[:8] + "***" if len(v) > 8 else "***"
                else:
                    config[k] = v
            return config
        except Exception as exc:
            logger.error("get_system_config error: %s", exc)
            return {}

    @staticmethod
    def save_system_config(updates: dict[str, str]) -> None:
        """
        Upsert key/value pairs into system_config.
        Each key is a separate row (key, value schema).
        """
        supabase = get_supabase_admin()
        rows = [{"key": k, "value": v} for k, v in updates.items() if v is not None]
        if not rows:
            return
        try:
            supabase.table("system_config").upsert(rows, on_conflict="key").execute()
        except Exception as exc:
            logger.error("save_system_config error: %s", exc)
            raise

    # ─────────────────────────────────────────────────────────
    # Platform usage analytics
    # ─────────────────────────────────────────────────────────

    @staticmethod
    def get_platform_usage() -> dict[str, Any]:
        """
        Aggregate platform-wide stats:
        - total users, campaigns, emails sent, contacts
        - overall reply rate
        - top 10 users leaderboard by emails sent
        """
        supabase = get_supabase_admin()

        total_users = 0
        total_campaigns = 0
        total_contacts = 0
        total_sent = 0
        total_replies = 0
        top_users: list[dict] = []

        try:
            # Users
            users_res = supabase.table("user_profiles").select("user_id, display_name, email").execute()
            all_users = users_res.data or []
            total_users = len(all_users)

            # Campaigns
            campaigns_res = supabase.table("campaigns").select("id, user_id, status").execute()
            all_campaigns = campaigns_res.data or []
            total_campaigns = len(all_campaigns)
            campaign_ids = [c["id"] for c in all_campaigns]

            # Contact / email stats
            if campaign_ids:
                contacts_res = supabase.table("campaign_contacts").select(
                    "campaign_id, status"
                ).in_("campaign_id", campaign_ids).execute()

                user_campaign_map: dict[str, str] = {c["id"]: c["user_id"] for c in all_campaigns}
                user_stats: dict[str, dict] = {}

                for cc in (contacts_res.data or []):
                    total_contacts += 1
                    uid = user_campaign_map.get(cc["campaign_id"], "unknown")
                    if uid not in user_stats:
                        user_stats[uid] = {"sent": 0, "replies": 0, "campaigns": 0}
                    s = cc["status"]
                    if s in ("sent", "replied", "interview"):
                        total_sent += 1
                        user_stats[uid]["sent"] += 1
                    if s in ("replied", "interview"):
                        total_replies += 1
                        user_stats[uid]["replies"] += 1

                # Campaign counts per user
                for c in all_campaigns:
                    uid = c["user_id"]
                    if uid not in user_stats:
                        user_stats[uid] = {"sent": 0, "replies": 0, "campaigns": 0}
                    user_stats[uid]["campaigns"] += 1

                # Build leaderboard
                user_lookup = {u["user_id"]: u for u in all_users}
                top_users = sorted(
                    [
                        {
                            "user_id": uid,
                            "display_name": user_lookup.get(uid, {}).get("display_name", "Unknown"),
                            "email": user_lookup.get(uid, {}).get("email", ""),
                            "emails_sent": s["sent"],
                            "replies": s["replies"],
                            "campaigns": s["campaigns"],
                        }
                        for uid, s in user_stats.items()
                        if uid in user_lookup
                    ],
                    key=lambda x: x["emails_sent"],
                    reverse=True,
                )[:10]

        except Exception as exc:
            logger.error("get_platform_usage error: %s", exc)

        reply_rate = round(total_replies / total_sent * 100, 1) if total_sent > 0 else None

        return {
            "total_users": total_users,
            "total_campaigns": total_campaigns,
            "total_emails_sent": total_sent,
            "total_contacts": total_contacts,
            "reply_rate": reply_rate,
            "top_users": top_users,
        }
