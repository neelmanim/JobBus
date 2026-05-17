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


# Job board URLs are not company domains — return empty so the outreach modal
# forces the user to type the actual company domain (e.g. google.com, stripe.com)
_JOB_BOARD_DOMAINS = {
    "linkedin.com", "indeed.com", "glassdoor.com", "remotive.com",
    "arbeitnow.com", "jsearch.p.rapidapi.com", "ziprecruiter.com",
    "lever.co", "greenhouse.io", "workable.com", "jobs.ashbyhq.com",
    "wellfound.com", "angel.co", "himalayas.app", "themuse.com",
}


def _extract_domain(url: str) -> str:
    """Extract bare company domain from a URL.

    Returns empty string for known job board URLs (linkedin.com, indeed.com,
    etc.) since those are the job board's domain, not the hiring company's.
    The outreach modal needs the *company* domain (e.g. google.com, stripe.com)
    for Hunter/Apollo contact search.
    """
    if not url:
        return ""
    try:
        from urllib.parse import urlparse
        parsed = urlparse(url)
        host = (parsed.netloc or parsed.path).replace("www.", "").split("/")[0].lower()
        # Don't return job board domains — they're useless for contact search
        if any(host == jb or host.endswith("." + jb) for jb in _JOB_BOARD_DOMAINS):
            return ""
        return host
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
    # ── Cache check: skip API if fresh results exist (< 6 hours old) ──────────
    supabase = get_supabase_admin()
    cache_cutoff = (
        __import__("datetime").datetime.utcnow()
        - __import__("datetime").timedelta(hours=6)
    ).isoformat()

    cached = supabase.table("opportunities").select("*") \
        .eq("user_id", user["user_id"]) \
        .eq("search_query", query.lower().strip()) \
        .gte("updated_at", cache_cutoff) \
        .order("score", desc=True) \
        .execute()

    if cached.data and len(cached.data) >= 3:
        rows = []
        for row in cached.data:
            row["company"] = row.get("company_name", "")
            row["title"]   = row.get("role_title", "")
            row["url"]     = row.get("job_url", "")
            row["domain"]  = _extract_domain(row.get("job_url", ""))
            rows.append(row)
        return {"opportunities": rows, "count": len(rows), "source": "cache"}

    # ── Cache miss: call external API ─────────────────────────────────────────
    # Resume improves scoring quality but is NOT a hard gate anymore.
    profile = get_resume_profile(user["user_id"])
    resume_dict = {
        "name":         profile.name   if profile else "",
        "role":         profile.role   if profile else query,
        "skills":       profile.skills if profile else [],
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

    # Persist opportunities to DB using explicit deduplication (no upsert constraint needed)
    saved = []
    logger = __import__("logging").getLogger(__name__)

    for opp in scored:
        score_result = opp.pop("_score")
        job_url = (opp.get("job_url") or "").strip()
        data = {
            "user_id":      user["user_id"],
            "search_query": query.lower().strip(),   # for cache lookup
            "company_name": opp.get("company_name", ""),
            "role_title":   opp.get("role_title", ""),
            "job_url":      job_url or None,
            "score":        score_result.total,
            "tier":         score_result.tier.value,
            "signals":      opp.get("signals", {}),
            "recommended_angle": OpportunityScorer.recommend_angle(
                score_result, opp.get("signals", {})
            ).value,
            "status":    "discovered",
            "location":  opp.get("location", ""),
            "is_remote": opp.get("is_remote", False),
            "source":    opp.get("source", source),
        }
        try:
            if job_url:
                existing = supabase.table("opportunities").select("id") \
                    .eq("user_id", user["user_id"]).eq("job_url", job_url).execute()
            else:
                existing = supabase.table("opportunities").select("id") \
                    .eq("user_id", user["user_id"]) \
                    .eq("company_name", data["company_name"]) \
                    .eq("role_title",   data["role_title"]).execute()

            if existing.data:
                result = supabase.table("opportunities").update(data) \
                    .eq("id", existing.data[0]["id"]).execute()
            else:
                result = supabase.table("opportunities").insert(data).execute()

            if result.data:
                row = result.data[0]
                row["company"] = row.get("company_name", "")
                row["title"]   = row.get("role_title", "")
                row["url"]     = row.get("job_url", "")
                row["domain"]  = _extract_domain(row.get("job_url", ""))
                saved.append(row)
            else:
                opp["company"] = opp.get("company_name", "")
                opp["title"]   = opp.get("role_title", "")
                opp["url"]     = opp.get("job_url", "")
                opp["domain"]  = _extract_domain(opp.get("job_url", ""))
                opp["score"]   = data["score"]
                opp["tier"]    = data["tier"]
                saved.append(opp)

        except Exception as e:
            logger.warning(f"DB write failed for opportunity, returning in-memory: {e}")
            opp["company"] = opp.get("company_name", "")
            opp["title"]   = opp.get("role_title", "")
            opp["url"]     = job_url
            opp["domain"]  = _extract_domain(job_url)
            opp["score"]   = data["score"]
            opp["tier"]    = data["tier"]
            saved.append(opp)

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


# ── Manual job entry ──────────────────────────────────────────────────────────

from pydantic import BaseModel


class ManualJobEntry(BaseModel):
    role_title: str
    company_name: str
    job_url: str = ""
    location: str = ""
    is_remote: bool = False
    notes: str = ""


@router.post("/manual")
async def add_manual_opportunity(
    body: ManualJobEntry,
    user: dict = Depends(get_current_user),
):
    """Add a job opportunity manually (paste from any job board).

    Useful when:
    - LinkedIn guest API is rate-limited
    - User found a role on Indeed / company careers page
    - User wants to track a specific job regardless of search

    The job is scored against the user's resume profile (if available).
    """
    from services.resume_analyzer import get_resume_profile

    profile = get_resume_profile(user["user_id"])
    resume_dict = {
        "name":         profile.name   if profile else "",
        "role":         profile.role   if profile else body.role_title,
        "skills":       profile.skills if profile else [],
        "achievements": profile.achievements if profile else [],
    }

    # Build a minimal job dict and score it
    job = {
        "role_title":          body.role_title,
        "company_name":        body.company_name,
        "job_url":             body.job_url,
        "location":            body.location,
        "is_remote":           body.is_remote,
        "description_snippet": body.notes,
        "source":              "manual",
        "signals": {"hiring": True, "role_match_keywords": []},
    }

    scored_list = scorer.get_top_picks([job], resume_dict, max_count=1)
    if not scored_list:
        # Score failed — insert with score 0
        score_total = 0
        tier_value  = "low"
        angle_value = "direct_value"
    else:
        scored_job   = scored_list[0]
        score_result = scored_job.pop("_score")
        score_total  = score_result.total
        tier_value   = score_result.tier.value
        angle_value  = OpportunityScorer.recommend_angle(score_result, {}).value

    job_url = body.job_url.strip() or None
    data = {
        "user_id":           user["user_id"],
        "search_query":      body.role_title.lower().strip(),
        "company_name":      body.company_name,
        "role_title":        body.role_title,
        "job_url":           job_url,
        "score":             score_total,
        "tier":              tier_value,
        "signals":           {"hiring": True, "manual_entry": True},
        "recommended_angle": angle_value,
        "status":            "discovered",
        "location":          body.location,
        "is_remote":         body.is_remote,
        "source":            "manual",
    }

    supabase = get_supabase_admin()
    try:
        result = supabase.table("opportunities").insert(data).execute()
        if result.data:
            row = result.data[0]
            row["company"] = row.get("company_name", "")
            row["title"]   = row.get("role_title", "")
            row["url"]     = row.get("job_url", "")
            row["domain"]  = _extract_domain(row.get("job_url", ""))
            return {"opportunity": row, "source": "manual"}
    except Exception as e:
        import logging
        logging.getLogger(__name__).warning(f"Manual entry DB write failed: {e}")

    # Return in-memory even if DB write failed
    data["company"] = data["company_name"]
    data["title"]   = data["role_title"]
    data["url"]     = body.job_url
    data["domain"]  = _extract_domain(body.job_url)
    return {"opportunity": data, "source": "manual"}
