"""
JobBus — Apollo.io Search Provider.

Two-phase approach (free-plan compatible):
  Phase 1 — bulk search (api_search): discovers names + titles but emails
             are hidden on free plan.
  Phase 2 — individual enrich (people/match): resolves a real work email
             for each discovered person. Each call costs 1 export credit.
             Apollo free plan gives 50 export credits/month.

Key goes in x-api-key header (body-key style is deprecated).
"""

from __future__ import annotations

import httpx
import logging
import asyncio

from providers.search.base import ContactResult, classify_persona

logger = logging.getLogger(__name__)

_BASE_URL   = "https://api.apollo.io/api/v1"
_SEARCH_URL = f"{_BASE_URL}/mixed_people/api_search"
_MATCH_URL  = f"{_BASE_URL}/people/match"
_TEST_URL   = f"{_BASE_URL}/auth/health"

# Default seniority filter — focus on decision-makers
_DEFAULT_SENIORITY = ["director", "vp", "c_suite", "partner", "manager", "senior", "founder"]


class ApolloSearchProvider:
    """Apollo.io contact search provider.

    Free plan: 50 export credits/month. Each people/match call = 1 credit.
    We use bulk search to discover names, then enrich only top N to save credits.
    """

    provider_name = "apollo"

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key
        self._headers = {
            "Content-Type": "application/json",
            "x-api-key": api_key,
        }

    async def find_contacts(
        self,
        company: str,
        domain: str,
        target_titles: list[str] | None = None,
        limit: int = 5,
    ) -> list[ContactResult]:
        """Discover contacts at a company using a 2-phase approach.

        Phase 1: Bulk search (free, no credits) → get names + titles
        Phase 2: Individual enrich (1 credit each) → get real work emails
        """
        # ── Phase 1: Discover people ─────────────────────────────
        payload: dict = {
            "q_organization_domains_list": [domain],
            "person_seniorities": _DEFAULT_SENIORITY,
            "per_page": min(limit * 2, 10),  # fetch extras to allow for enrich failures
            "page": 1,
        }
        if target_titles:
            payload["person_titles"] = target_titles

        async with httpx.AsyncClient(timeout=20.0) as client:
            try:
                resp = await client.post(_SEARCH_URL, json=payload, headers=self._headers)
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401:
                    raise ValueError("Apollo.io: Invalid API key")
                if e.response.status_code == 422:
                    raise ValueError(f"Apollo.io: Invalid search params — {e.response.text[:150]}")
                raise ValueError(f"Apollo.io API error: {e.response.status_code}")
            except httpx.TimeoutException:
                raise ValueError("Apollo.io: Request timed out")

            people_raw = resp.json().get("people", [])
            if not people_raw:
                return []

            # ── Phase 2: Enrich up to `limit` people to get emails ──
            results: list[ContactResult] = []
            enrich_tasks = []
            for person in people_raw[:limit]:
                first = person.get("first_name") or ""
                last  = person.get("last_name")  or ""
                title = person.get("title")       or ""
                if not first or not last:
                    continue
                enrich_tasks.append((first, last, title, person.get("linkedin_url")))

            # Run enrichment concurrently (max 3 at once to be polite)
            sem = asyncio.Semaphore(3)

            async def enrich_one(first, last, title, linkedin):
                async with sem:
                    try:
                        payload = {"domain": domain, "reveal_personal_emails": False}
                        if first:
                            payload["first_name"] = first
                        if last:
                            payload["last_name"] = last
                        # LinkedIn URL is the most reliable identifier
                        if linkedin:
                            payload["linkedin_url"] = linkedin

                        r = await client.post(_MATCH_URL, headers=self._headers, json=payload)
                        if r.status_code != 200:
                            return None
                        person_data = r.json().get("person") or {}
                        email = person_data.get("email") or ""
                        if not email or "***" in email:
                            return None
                        # Use resolved name if we only had a first name
                        resolved_first = person_data.get("first_name") or first
                        resolved_last  = person_data.get("last_name")  or last or ""
                        return ContactResult(
                            first_name=resolved_first,
                            last_name=resolved_last,
                            email=email,
                            title=title,
                            company=company,
                            linkedin_url=linkedin or person_data.get("linkedin_url"),
                            confidence_score=0.85,
                            persona_type=classify_persona(title),
                            source="apollo",
                        )
                    except Exception:
                        return None

            enriched = await asyncio.gather(*[enrich_one(*t) for t in enrich_tasks])
            results = [r for r in enriched if r is not None]

        results.sort(key=lambda r: r.persona_rank())
        return results[:limit]

    async def test_connection(self) -> bool:
        """Test Apollo.io API key validity (free — hits /auth/health)."""
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(_TEST_URL, headers=self._headers)
                return resp.status_code == 200 and resp.json().get("is_logged_in", False)
            except Exception:
                return False
