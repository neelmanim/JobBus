"""
JobBus Backend — Campaign Engine.

Orchestrates the full outreach lifecycle:
  Resume → Signals → Score → Angle → Draft → Approve → Send → Follow-up
"""

from __future__ import annotations


from datetime import datetime, timezone
from typing import Optional

from database import get_supabase_admin
from models.enums import CampaignStatus, ContactStatus
from models.schemas import CampaignResponse, CampaignCreate, CampaignAnalytics


class CampaignEngine:
    """Orchestrates campaign lifecycle from creation to completion."""

    def create_campaign(self, user_id: str, campaign: CampaignCreate) -> CampaignResponse:
        """Create a new campaign."""
        supabase = get_supabase_admin()
        data = {
            "user_id": user_id,
            "name": campaign.name,
            "status": CampaignStatus.DRAFT.value,
            "opportunity_id": campaign.opportunity_id,
        }
        result = supabase.table("campaigns").insert(data).execute()
        row = result.data[0]
        return CampaignResponse(
            id=row["id"],
            name=row["name"],
            status=CampaignStatus(row["status"]),
            created_at=row["created_at"],
        )

    def list_campaigns(self, user_id: str) -> list[CampaignResponse]:
        """List all campaigns for a user."""
        supabase = get_supabase_admin()
        result = supabase.table("campaigns").select("*").eq(
            "user_id", user_id
        ).order("created_at", desc=True).execute()

        campaigns = []
        for row in result.data:
            stats = self._get_campaign_stats(row["id"])
            campaigns.append(CampaignResponse(
                id=row["id"],
                name=row["name"],
                status=CampaignStatus(row["status"]),
                contacts_count=stats["contacts_count"],
                sent_count=stats["sent"],
                reply_count=stats["replied"],
                interview_count=stats["interviews"],
                bounce_count=stats["bounced"],
                created_at=row["created_at"],
            ))
        return campaigns

    def get_campaign(self, campaign_id: str, user_id: str) -> Optional[CampaignResponse]:
        """Get a single campaign."""
        supabase = get_supabase_admin()
        result = supabase.table("campaigns").select("*").eq(
            "id", campaign_id
        ).eq("user_id", user_id).execute()

        if not result.data:
            return None

        row = result.data[0]
        stats = self._get_campaign_stats(row["id"])
        return CampaignResponse(
            id=row["id"],
            name=row["name"],
            status=CampaignStatus(row["status"]),
            contacts_count=stats["contacts_count"],
            sent_count=stats["sent"],
            reply_count=stats["replied"],
            interview_count=stats["interviews"],
            bounce_count=stats["bounced"],
            created_at=row["created_at"],
        )

    def update_status(self, campaign_id: str, user_id: str, new_status: CampaignStatus) -> CampaignResponse:
        """Update campaign status."""
        supabase = get_supabase_admin()
        result = supabase.table("campaigns").update(
            {"status": new_status.value}
        ).eq("id", campaign_id).eq("user_id", user_id).execute()

        if not result.data:
            raise ValueError(f"Campaign {campaign_id} not found")

        row = result.data[0]
        return CampaignResponse(
            id=row["id"],
            name=row["name"],
            status=CampaignStatus(row["status"]),
            created_at=row["created_at"],
        )

    def add_contacts(self, campaign_id: str, contact_ids: list[str]) -> int:
        """Add contacts to a campaign."""
        supabase = get_supabase_admin()
        data = [
            {
                "campaign_id": campaign_id,
                "contact_id": cid,
                "status": ContactStatus.PENDING.value,
            }
            for cid in contact_ids
        ]
        result = supabase.table("campaign_contacts").insert(data).execute()
        return len(result.data) if result.data else 0

    def update_contact_status(self, campaign_id: str, contact_id: str, status: ContactStatus) -> None:
        """Update a contact's status within a campaign."""
        supabase = get_supabase_admin()
        supabase.table("campaign_contacts").update(
            {"status": status.value}
        ).eq("campaign_id", campaign_id).eq("contact_id", contact_id).execute()

    def get_analytics(self, campaign_id: str) -> CampaignAnalytics:
        """Get campaign analytics."""
        stats = self._get_campaign_stats(campaign_id)

        sent = stats["sent"]
        reply_rate = stats["replied"] / sent if sent > 0 else 0
        bounce_rate = stats["bounced"] / sent if sent > 0 else 0
        interview_rate = stats["interviews"] / sent if sent > 0 else 0

        return CampaignAnalytics(
            sent=sent,
            replied=stats["replied"],
            bounced=stats["bounced"],
            interviews=stats["interviews"],
            no_response=stats["no_response"],
            reply_rate=round(reply_rate, 3),
            bounce_rate=round(bounce_rate, 3),
            interview_conversion=round(interview_rate, 3),
        )

    def _get_campaign_stats(self, campaign_id: str) -> dict:
        """Get contact status counts for a campaign."""
        supabase = get_supabase_admin()
        try:
            result = supabase.table("campaign_contacts").select(
                "status"
            ).eq("campaign_id", campaign_id).execute()

            contacts = result.data or []
            stats = {
                "contacts_count": len(contacts),
                "sent": 0,
                "replied": 0,
                "bounced": 0,
                "interviews": 0,
                "no_response": 0,
                "pending": 0,
            }

            for c in contacts:
                s = c.get("status", "pending")
                if s == "sent":
                    stats["sent"] += 1
                elif s == "replied":
                    stats["sent"] += 1
                    stats["replied"] += 1
                elif s == "bounced":
                    stats["sent"] += 1
                    stats["bounced"] += 1
                elif s == "interview":
                    stats["sent"] += 1
                    stats["replied"] += 1
                    stats["interviews"] += 1
                elif s == "no_response":
                    stats["sent"] += 1
                    stats["no_response"] += 1
                else:
                    stats["pending"] += 1

            return stats
        except Exception:
            return {"contacts_count": 0, "sent": 0, "replied": 0, "bounced": 0,
                    "interviews": 0, "no_response": 0, "pending": 0}
