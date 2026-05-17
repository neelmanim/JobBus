"""
JobBus Backend — Signal Collectors.

Gathers external signals for opportunity scoring:
  - JSearch: Job postings from RapidAPI (premium, requires JSEARCH_API_KEY)
  - Remotive: Free remote jobs — NO key needed (automatic fallback)
  - FundingCollector / CompanyInfoCollector: stubs for future enrichment
"""

from __future__ import annotations

import re
from typing import Optional
import httpx

from config import get_settings


class JSearchCollector:
    """Collects job postings from JSearch (RapidAPI). Requires JSEARCH_API_KEY."""

    BASE_URL = "https://jsearch.p.rapidapi.com"

    def __init__(self, api_key: str = None):
        settings = get_settings()
        self.api_key = api_key or settings.jsearch_api_key or ""
        self.headers = {
            "X-RapidAPI-Key": self.api_key,
            "X-RapidAPI-Host": "jsearch.p.rapidapi.com",
        }

    @property
    def has_key(self) -> bool:
        return bool(self.api_key)

    async def search_jobs(
        self,
        query: str,
        location: str = "",
        page: int = 1,
        num_pages: int = 1,
        date_posted: str = "month",
        remote_only: bool = False,
    ) -> list[dict]:
        """Search JSearch. Returns [] silently if no key configured."""
        if not self.api_key:
            return []

        params = {
            "query": f"{query} {location}".strip(),
            "page": str(page),
            "num_pages": str(num_pages),
            "date_posted": date_posted,
        }
        if remote_only:
            params["remote_jobs_only"] = "true"

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                response = await client.get(
                    f"{self.BASE_URL}/search",
                    headers=self.headers,
                    params=params,
                )
                response.raise_for_status()
                data = response.json()

            jobs = data.get("data", [])
            return [self._normalize(job) for job in jobs]

        except httpx.HTTPError:
            return []

    @staticmethod
    def _normalize(job: dict) -> dict:
        return {
            "job_url": job.get("job_apply_link") or job.get("job_google_link", ""),
            "role_title": job.get("job_title", ""),
            "company_name": job.get("employer_name", ""),
            "company_logo": job.get("employer_logo"),
            "location": job.get("job_city", "") + ", " + job.get("job_state", ""),
            "is_remote": job.get("job_is_remote", False),
            "posted_at": job.get("job_posted_at_datetime_utc"),
            "description_snippet": (job.get("job_description", ""))[:300],
            "source": "jsearch",
            "signals": {
                "hiring": True,
                "role_match_keywords": _extract_keywords(
                    job.get("job_title", "") + " " + job.get("job_description", "")[:500]
                ),
            },
        }


class RemotiveCollector:
    """Free remote jobs from Remotive.com — NO API key required.

    This is the automatic fallback when JSearch key is absent.
    Public API: https://remotive.com/api/remote-jobs
    """

    BASE_URL = "https://remotive.com/api/remote-jobs"

    async def search_jobs(self, query: str, location: str = "") -> list[dict]:
        """Search Remotive for remote jobs. Always works, no key needed."""
        try:
            params = {"search": query, "limit": 40}  # fetch more so filtering still leaves enough
            async with httpx.AsyncClient(timeout=20) as client:
                response = await client.get(self.BASE_URL, params=params)
                response.raise_for_status()
                data = response.json()

            jobs = data.get("jobs", [])
            return [self._normalize(job) for job in jobs]

        except httpx.HTTPError:
            return []

    @staticmethod
    def _normalize(job: dict) -> dict:
        return {
            "job_url": job.get("url", ""),
            "role_title": job.get("title", ""),
            "company_name": job.get("company_name", ""),
            "company_logo": job.get("company_logo"),
            "location": job.get("candidate_required_location", "Remote"),
            "is_remote": True,
            "posted_at": job.get("publication_date"),
            "description_snippet": _strip_html(job.get("description", ""))[:300],
            "source": "remotive",
            "signals": {
                "hiring": True,
                "role_match_keywords": _extract_keywords(
                    job.get("title", "") + " " + str(job.get("tags", ""))
                ),
            },
        }


class FundingCollector:
    """Collects company funding data (stub)."""

    async def check_funding(self, company_name: str) -> dict:
        return {
            "recently_funded": False,
            "funding_round": None,
            "amount": None,
            "date": None,
        }


class CompanyInfoCollector:
    """Collects company metadata (stub)."""

    async def get_info(self, company_name: str) -> dict:
        return {
            "company_size": None,
            "industry": None,
            "website": None,
            "remote_friendly": None,
        }


async def search_jobs_auto(query: str, location: str = "") -> tuple[list[dict], str]:
    """Waterfall job search: JSearch (premium key) → Remotive (free, always available).

    Results are filtered by title relevance — Remotive's search is fuzzy and often
    returns unrelated roles. We keep a job only if at least one meaningful word
    from the query appears in the role title.

    Returns:
        (list of normalized job dicts, source_name used)
    """
    jsearch = JSearchCollector()
    if jsearch.has_key:
        jobs = await jsearch.search_jobs(query=query, location=location)
        if jobs:
            return _filter_by_title_relevance(jobs, query), "jsearch"

    # Free fallback — always available, no key needed
    remotive = RemotiveCollector()
    jobs = await remotive.search_jobs(query=query, location=location)
    filtered = _filter_by_title_relevance(jobs, query)
    # If strict filter is too aggressive (< 3 results), relax and return all
    return (filtered if len(filtered) >= 3 else jobs), "remotive"


# ── Helpers ──────────────────────────────────────────────────────────────────

def _strip_html(text: str) -> str:
    """Lightweight HTML tag stripper for Remotive descriptions."""
    return re.sub(r"<[^>]+>", " ", text).strip()


# Stop-words to ignore when matching query to title
_STOP_WORDS = {
    "a", "an", "the", "and", "or", "for", "in", "at", "to", "of",
    "with", "is", "are", "be", "as", "on", "it", "its",
    "senior", "junior", "mid", "lead", "staff", "principal",  # seniority (not role-specific)
}


def _filter_by_title_relevance(jobs: list[dict], query: str) -> list[dict]:
    """Keep only jobs where the role title is relevant to the search query.

    Splits the query into meaningful words (strips stop-words), then keeps
    a job only if at least one query word appears in the role title.
    Falls back to all jobs if query has no meaningful words.
    """
    query_words = [
        w.lower() for w in re.split(r"[\s,/]+", query)
        if len(w) >= 3 and w.lower() not in _STOP_WORDS
    ]
    if not query_words:
        return jobs

    relevant = []
    for job in jobs:
        title_lower = job.get("role_title", "").lower()
        if any(qw in title_lower for qw in query_words):
            relevant.append(job)
    return relevant


def _extract_keywords(text: str) -> list[str]:
    """Extract technology/skill keywords from text."""
    tech_keywords = {
        "python", "javascript", "typescript", "react", "angular", "vue",
        "node", "nodejs", "java", "c++", "c#", "go", "golang", "rust",
        "kubernetes", "docker", "aws", "gcp", "azure", "terraform",
        "sql", "nosql", "postgresql", "mongodb", "redis", "elasticsearch",
        "machine learning", "ml", "ai", "deep learning", "nlp",
        "fastapi", "django", "flask", "spring", "express",
        "graphql", "rest", "grpc", "microservices",
        "ci/cd", "devops", "sre", "agile", "scrum",
        "swift", "kotlin", "flutter", "react native",
        "product manager", "product management", "product owner",
        "data analyst", "data science", "data engineer",
        "ux", "ui", "design", "figma",
        "sales", "marketing", "growth", "seo",
        "finance", "accounting", "legal", "operations",
    }
    text_lower = text.lower()
    found = [kw for kw in tech_keywords if kw in text_lower]
    return list(set(found))[:10]
