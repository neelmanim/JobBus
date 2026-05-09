"""
JobBus Backend — Opportunities Router.

Job search, scoring, and opportunity management.
"""

from __future__ import annotations


from fastapi import APIRouter, Depends, HTTPException

from middleware.auth_middleware import get_current_user
from services.opportunity_scorer import OpportunityScorer
from services.signal_collectors import JSearchCollector
from services.resume_analyzer import get_resume_profile
from models.schemas import OpportunityResponse, OpportunityScore
from database import get_supabase_admin


router = APIRouter(prefix="/api/opportunities", tags=["opportunities"])
scorer = OpportunityScorer()


@router.get("/search")
async def search_opportunities(
    query: str,
    location: str = "",
    remote_only: bool = False,
    user: dict = Depends(get_current_user),
):
    """Search for job opportunities and score them."""
    # Get resume profile for scoring
    profile = get_resume_profile(user["user_id"])
    if not profile:
        raise HTTPException(status_code=400, detail="Upload a resume first")

    # Collect signals
    collector = JSearchCollector()
    jobs = await collector.search_jobs(query=query, location=location, remote_only=remote_only)

    if not jobs:
        return {"opportunities": [], "message": "No opportunities found. Try different search terms."}

    # Score each opportunity
    resume_dict = {
        "name": profile.name,
        "role": profile.role,
        "skills": profile.skills,
        "achievements": profile.achievements,
    }

    scored = scorer.get_top_picks(jobs, resume_dict, max_count=20)

    # Save opportunities to DB
    supabase = get_supabase_admin()
    saved = []
    for opp in scored:
        score_result = opp.pop("_score")
        data = {
            "user_id": user["user_id"],
            "company_name": opp.get("company_name", ""),
            "role_title": opp.get("role_title", ""),
            "job_url": opp.get("job_url"),
            "score": score_result.total,
            "tier": score_result.tier.value,
            "signals": opp.get("signals", {}),
            "recommended_angle": OpportunityScorer.recommend_angle(
                score_result, opp.get("signals", {})
            ).value,
            "status": "discovered",
        }
        result = supabase.table("opportunities").insert(data).execute()
        if result.data:
            saved.append(result.data[0])

    return {"opportunities": saved, "count": len(saved)}


@router.get("/")
async def list_opportunities(
    tier: str = None,
    user: dict = Depends(get_current_user),
):
    """List saved opportunities."""
    supabase = get_supabase_admin()
    query = supabase.table("opportunities").select("*").eq(
        "user_id", user["user_id"]
    ).order("score", desc=True)

    if tier:
        query = query.eq("tier", tier)

    result = query.execute()
    return {"opportunities": result.data or []}


@router.get("/{opportunity_id}")
async def get_opportunity(opportunity_id: str, user: dict = Depends(get_current_user)):
    """Get a single opportunity with full scoring details."""
    supabase = get_supabase_admin()
    result = supabase.table("opportunities").select("*").eq(
        "id", opportunity_id
    ).eq("user_id", user["user_id"]).execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="Opportunity not found")
    return result.data[0]
