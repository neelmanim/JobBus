"""
JobBus Backend — Campaign Router.

Campaign lifecycle endpoints: create, manage contacts, generate drafts, send.
"""

from __future__ import annotations


from fastapi import APIRouter, Depends, HTTPException, status

from middleware.auth_middleware import get_current_user
from services.campaign_engine import CampaignEngine
from services.credential_service import get_credential_service
from models.schemas import CampaignCreate, CampaignResponse, CampaignAnalytics
from models.enums import CampaignStatus, ContactStatus
from database import get_supabase_admin


router = APIRouter(prefix="/api/campaigns", tags=["campaigns"])
engine = CampaignEngine()


@router.post("/", response_model=CampaignResponse)
async def create_campaign(
    request: CampaignCreate,
    user: dict = Depends(get_current_user),
):
    """Create a new campaign."""
    return engine.create_campaign(user["user_id"], request)


@router.get("/", response_model=list[CampaignResponse])
async def list_campaigns(user: dict = Depends(get_current_user)):
    """List all campaigns for the current user."""
    return engine.list_campaigns(user["user_id"])


@router.get("/{campaign_id}", response_model=CampaignResponse)
async def get_campaign(campaign_id: str, user: dict = Depends(get_current_user)):
    """Get a specific campaign."""
    campaign = engine.get_campaign(campaign_id, user["user_id"])
    if not campaign:
        raise HTTPException(status_code=404, detail="Campaign not found")
    return campaign


@router.put("/{campaign_id}/status")
async def update_campaign_status(
    campaign_id: str,
    new_status: CampaignStatus,
    user: dict = Depends(get_current_user),
):
    """Update campaign status (e.g., draft → reviewing → approved → sending)."""
    try:
        return engine.update_status(campaign_id, user["user_id"], new_status)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/{campaign_id}/contacts")
async def add_campaign_contacts(
    campaign_id: str,
    contact_ids: list[str],
    user: dict = Depends(get_current_user),
):
    """Add contacts to a campaign."""
    # Verify campaign ownership
    campaign = engine.get_campaign(campaign_id, user["user_id"])
    if not campaign:
        raise HTTPException(status_code=404, detail="Campaign not found")

    added = engine.add_contacts(campaign_id, contact_ids)
    return {"added": added}


@router.get("/{campaign_id}/analytics", response_model=CampaignAnalytics)
async def get_campaign_analytics(
    campaign_id: str,
    user: dict = Depends(get_current_user),
):
    """Get campaign analytics."""
    campaign = engine.get_campaign(campaign_id, user["user_id"])
    if not campaign:
        raise HTTPException(status_code=404, detail="Campaign not found")
    return engine.get_analytics(campaign_id)
