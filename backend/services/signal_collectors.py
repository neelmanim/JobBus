"""
JobBus Backend — Signal Collectors.

Gathers external signals for opportunity scoring:
  - JSearch: Job postings from RapidAPI
  - Funding: Company funding data (stub for now)
  - Company: Company metadata (stub)

Users can plug in their own API keys for higher rate limits.
"""

from __future__ import annotations


import os
from typing import Optional
import httpx

from config import get_settings


class JSearchCollector:
    """Collects job postings from JSearch (RapidAPI).
    
    Uses the default JobBus key or user's own key.
    Free tier: 200 requests/month.
    """

    BASE_URL = "https://jsearch.p.rapidapi.com"

    def __init__(self, api_key: str = None):
        settings = get_settings()
        self.api_key = api_key or settings.jsearch_api_key or ""
        self.headers = {
            "X-RapidAPI-Key": self.api_key,
            "X-RapidAPI-Host": "jsearch.p.rapidapi.com",
        }

    async def search_jobs(
        self,
        query: str,
        location: str = "",
        page: int = 1,
        num_pages: int = 1,
        date_posted: str = "month",
        remote_only: bool = False,
    ) -> list[dict]:
        """Search for job postings.

        Args:
            query: Job title or keywords
            location: City or country
            page: Page number (1-indexed)
            num_pages: Number of pages to fetch
            date_posted: Filter: all, today, 3days, week, month
            remote_only: Filter for remote jobs

        Returns:
            List of normalized job dictionaries
        """
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
        """Normalize JSearch response to internal format."""
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


class FundingCollector:
    """Collects company funding data (stub — uses free APIs when available)."""

    async def check_funding(self, company_name: str) -> dict:
        """Check if company has recent funding.
        
        Returns:
            Dict with recently_funded, funding_round, amount, date
        """
        # Stub — in production, use Crunchbase or similar
        return {
            "recently_funded": False,
            "funding_round": None,
            "amount": None,
            "date": None,
        }


class CompanyInfoCollector:
    """Collects company metadata (size, industry, etc.)."""

    async def get_info(self, company_name: str) -> dict:
        """Get company information.
        
        Returns:
            Dict with size, industry, website, remote_friendly
        """
        # Stub — can integrate LinkedIn or Clearbit in future
        return {
            "company_size": None,
            "industry": None,
            "website": None,
            "remote_friendly": None,
        }


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
    }
    text_lower = text.lower()
    found = [kw for kw in tech_keywords if kw in text_lower]
    return list(set(found))[:10]
