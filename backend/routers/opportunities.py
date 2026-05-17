"""
JobBus Backend — Opportunities Router.

Job search, scoring, and opportunity management.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from middleware.auth_middleware import get_current_user
from services.opportunity_scorer import OpportunityScorer
from services.signal_collectors import search_jobs_auto
from services.resume_analyzer import get_resume_profile
from database import get_supabase_admin


router = APIRouter(prefix="/api/opportunities", tags=["opportunities"])
scorer = OpportunityScorer()


def _extract_domain(url: str) -> str:
    """Extract bare domain from a URL, e.g. 'https://stripe.com/jobs/123' → 'stripe.com'."""
    if not url:
        return ""
    try:
        from urllib.parse import urlparse
        parsed = urlparse(url)
        host = parsed.netloc or parsed.path
        # strip www.
        return host.replace("www.", "").split("/")[0]
    except Exception:
        return ""



@router.get("/search")
async def search_opportunities(
    query: str,
    location: str = "",
    remote_only: bool = False,
    user: dict = Depends(get_current_user),
):
    """Search for job opportunities and score them.

    Works without a resume — scoring uses the query as the role when no
    resume profile exists.  Resume improves match quality but is not required.
    """
    # Resume improves scoring quality but is NOT a hard gate anymore.
    profile = get_resume_profile(user["user_id"])
    resume_dict = {
        "name": profile.name if profile else "",
        "role": profile.role if profile else query,   # fall back to search query
        "skills": profile.skills if profile else [],
        "achievements": profile.achievements if profile else [],
    }

    # Waterfall: JSearch (premium) → Remotive (free, always available)
    jobs, source = await search_jobs_auto(query=query, location=location)

    if not jobs:
        return {
            "opportunities": [],
            "source": source,
            "message": "No opportunities found. Try different search terms.",
        }

    # Score each opportunity against the resume (or the query itself)
    scored = scorer.get_top_picks(jobs, resume_dict, max_count=20)

    # Persist opportunities to DB
    supabase = get_supabase_admin()
    saved = []
    for opp in scored:
        score_result = opp.pop("_score")
        job_url = opp.get("job_url") or ""
        data = {
            "user_id": user["user_id"],
            "company_name": opp.get("company_name", ""),
            "role_title": opp.get("role_title", ""),
            "job_url": job_url or None,  # store NULL not empty string
            "score": score_result.total,
            "tier": score_result.tier.value,
            "signals": opp.get("signals", {}),
            "recommended_angle": OpportunityScorer.recommend_angle(
                score_result, opp.get("signals", {})
            ).value,
            "status": "discovered",
            "location": opp.get("location", ""),
            "is_remote": opp.get("is_remote", False),
            "source": opp.get("source", source),
        }
        try:
            if job_url:
                result = supabase.table("opportunities").upsert(
                    data,
                    on_conflict="user_id,job_url",
                ).execute()
            else:
                # No URL — insert only if company+role combo not already saved
                existing = supabase.table("opportunities").select("id") \
                    .eq("user_id", user["user_id"]) \
                    .eq("company_name", data["company_name"]) \
                    .eq("role_title", data["role_title"]) \
                    .execute()
                if existing.data:
                    result = supabase.table("opportunities").update(data) \
                        .eq("id", existing.data[0]["id"]).execute()
                else:
                    result = supabase.table("opportunities").insert(data).execute()
            if result.data:
                row = result.data[0]
                # Add UI-friendly aliases so frontend opp.company / opp.title resolve
                row["company"] = row.get("company_name", "")
                row["title"] = row.get("role_title", "")
                row["url"] = row.get("job_url", "")
                row["domain"] = _extract_domain(row.get("job_url", ""))
                saved.append(row)
        except Exception as e:
            import logging
            logging.getLogger(__name__).warning(f"Failed to save opportunity: {e}")
            continue

    return {"opportunities": saved, "count": len(saved), "source": source}


@router.get("/")
async def list_opportunities(
    tier: str = None,
    user: dict = Depends(get_current_user),
):
    """List all saved opportunities for the current user, newest first."""
    supabase = get_supabase_admin()
    q = (
        supabase.table("opportunities")
        .select("*")
        .eq("user_id", user["user_id"])
        .order("score", desc=True)
    )

    if tier:
        q = q.eq("tier", tier)

    result = q.execute()
    rows = []
    for row in (result.data or []):
        row["company"] = row.get("company_name", "")
        row["title"]   = row.get("role_title", "")
        row["url"]     = row.get("job_url", "")
        row["domain"]  = _extract_domain(row.get("job_url", ""))
        rows.append(row)
    return {"opportunities": rows}


@router.get("/{opportunity_id}")
async def get_opportunity(opportunity_id: str, user: dict = Depends(get_current_user)):
    """Get a single opportunity with full details."""
    supabase = get_supabase_admin()
    result = (
        supabase.table("opportunities")
        .select("*")
        .eq("id", opportunity_id)
        .eq("user_id", user["user_id"])
        .execute()
    )

    if not result.data:
        raise HTTPException(status_code=404, detail="Opportunity not found")
    return result.data[0]


@router.patch("/{opportunity_id}/status")
async def update_opportunity_status(
    opportunity_id: str,
    body: dict,
    user: dict = Depends(get_current_user),
):
    """Update opportunity status (discovered → applied → interviewing → offer/rejected)."""
    allowed = {"discovered", "saved", "applied", "interviewing", "offer", "rejected"}
    status = body.get("status", "")
    if status not in allowed:
        raise HTTPException(status_code=400, detail=f"Invalid status. Allowed: {allowed}")

    supabase = get_supabase_admin()
    result = (
        supabase.table("opportunities")
        .update({"status": status})
        .eq("id", opportunity_id)
        .eq("user_id", user["user_id"])
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Opportunity not found")
    return result.data[0]
