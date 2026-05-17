"""
JobBus Backend — Signal Collectors.

Gathers external job signals for opportunity scoring.

Source waterfall (best → always-available):
  1. JSearch (RapidAPI) — premium, requires JSEARCH_API_KEY
     Aggregates Google for Jobs → LinkedIn, Indeed, ZipRecruiter data.

  2. LinkedIn Guest API — FREE, no key, always available.
     LinkedIn's public job search endpoint returns real keyword-matched
     results. No auth required (same data as linkedin.com/jobs logged out).

  NOTE: Remotive was removed — it ignores the `search` parameter entirely
  and always returns the same ~18 static jobs regardless of the query.
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


class LinkedInCollector:
    """Scrapes LinkedIn public guest job search — FREE, no key needed.

    Uses LinkedIn's unauthenticated job listing endpoint. Returns real,
    keyword-matched jobs sorted by relevance — the same results as
    linkedin.com/jobs when browsing without an account.

    Rate limit: graceful (~100 req/hour per IP). Falls back to [] on any error.
    """

    BASE_URL = "https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search"

    HEADERS = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "en-US,en;q=0.9",
    }

    async def search_jobs(
        self,
        query: str,
        location: str = "",
        count: int = 25,
    ) -> list[dict]:
        """Search LinkedIn guest API. Parses HTML, returns normalized job dicts."""
        params = {
            "keywords": query,
            "start": "0",
            "count": str(count),
            "sortBy": "R",  # Relevance
        }
        if location:
            params["location"] = location

        try:
            async with httpx.AsyncClient(timeout=20, follow_redirects=True) as client:
                response = await client.get(
                    self.BASE_URL,
                    params=params,
                    headers=self.HEADERS,
                )
                response.raise_for_status()
                html = response.text

            return self._parse_html(html)

        except Exception:
            return []

    @staticmethod
    def _parse_html(html: str) -> list[dict]:
        """Parse LinkedIn HTML response into normalized job dicts."""
        jobs = []

        titles    = re.findall(r'class="base-search-card__title"[^>]*>\s*([^<]+)\s*<', html)
        companies = re.findall(r'class="base-search-card__subtitle"[^>]*>\s*<[^>]+>\s*([^<]+)\s*<', html)
        locations = re.findall(r'class="job-search-card__location"[^>]*>\s*([^<]+)\s*<', html)
        links     = re.findall(r'href="(https://www\.linkedin\.com/jobs/view/[^"?]+)', html)

        for i, title in enumerate(titles):
            title    = title.strip()
            company  = companies[i].strip() if i < len(companies) else ""
            location = locations[i].strip() if i < len(locations) else ""
            url      = links[i] if i < len(links) else ""

            if not title or not company:
                continue

            jobs.append({
                "job_url":             url,
                "role_title":          title,
                "company_name":        company,
                "company_logo":        None,
                "location":            location,
                "is_remote":           "remote" in location.lower(),
                "posted_at":           None,
                "description_snippet": f"{title} position at {company}. Location: {location}",
                "source":              "linkedin",
                "signals": {
                    "hiring": True,
                    "role_match_keywords": _extract_keywords(title),
                },
            })

        return jobs


class FundingCollector:
    """Collects company funding data (stub)."""

    async def check_funding(self, company_name: str) -> dict:
        return {"recently_funded": False, "funding_round": None, "amount": None, "date": None}


class CompanyInfoCollector:
    """Collects company metadata (stub)."""

    async def get_info(self, company_name: str) -> dict:
        return {"company_size": None, "industry": None, "website": None, "remote_friendly": None}


async def search_jobs_auto(query: str, location: str = "") -> tuple[list[dict], str]:
    """Waterfall job search: JSearch (premium key) → LinkedIn (free, always available).

    Both sources do real keyword matching — results are relevant to the query.
    A title-relevance filter is applied as a secondary guard.

    Returns:
        (list of normalized job dicts, source_name used)
    """
    # Edge case: empty or whitespace-only query
    query = (query or "").strip() or "software engineer"

    jsearch = JSearchCollector()
    if jsearch.has_key:
        jobs = await jsearch.search_jobs(query=query, location=location)
        if jobs:
            return jobs, "jsearch"

    # Free fallback — LinkedIn guest API, always available, real keyword search
    linkedin = LinkedInCollector()
    jobs = await linkedin.search_jobs(query=query, location=location)
    filtered = _filter_by_title_relevance(jobs, query)
    # Safety: if strict filter returns < 3, use all LinkedIn results
    return (filtered if len(filtered) >= 3 else jobs), "linkedin"


# ── Helpers ───────────────────────────────────────────────────────────────────

# Stop-words to skip when building query-word list for relevance matching
_STOP_WORDS = {
    "a", "an", "the", "and", "or", "for", "in", "at", "to", "of",
    "with", "is", "are", "be", "as", "on", "it", "its",
    "senior", "junior", "mid", "lead", "staff", "principal",
}


def _filter_by_title_relevance(jobs: list[dict], query: str) -> list[dict]:
    """Keep only jobs where the role title is relevant to the search query.

    Strategy:
      - Multi-word query ("Product Manager"): ALL words must appear in title.
        Prevents "Marketing Manager" matching when only 'manager' overlaps.
      - Single-word query ("Python"): any occurrence in title is fine.
      - Minimum word length = 2 chars so "PM", "QA", "ML" are handled.
      - Falls back to all jobs if < 3 pass (avoids empty page).
    """
    query_words = [
        w.lower() for w in re.split(r"[\s,/]+", query)
        if len(w) >= 2 and w.lower() not in _STOP_WORDS
    ]
    if not query_words:
        return jobs

    is_multi_word = len(query_words) >= 2
    relevant = []
    for job in jobs:
        title_lower = job.get("role_title", "").lower()
        if is_multi_word:
            if all(qw in title_lower for qw in query_words):
                relevant.append(job)
        else:
            if any(qw in title_lower for qw in query_words):
                relevant.append(job)

    return relevant if len(relevant) >= 3 else jobs


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
