"""
JobBus — Apollo.io Search Provider.

POST /api/v1/mixed_people/api_search → search by title, company, domain.
Key is passed via x-api-key header (NOT in body — old style is deprecated).

NOTE: Free plan returns names but masks emails (shows ??? placeholders).
      Contacts without a real email are skipped — Hunter is the better free
      option; Apollo shines when you have a paid plan with email reveal.
"""

from __future__ import annotations

import httpx
import logging

from providers.search.base import ContactResult, SearchProvider, classify_persona

logger = logging.getLogger(__name__)

# Correct endpoint as of 2025 — mixed_people/search and people/search are DEPRECATED
_SEARCH_URL = "https://api.apollo.io/api/v1/mixed_people/api_search"
_TEST_URL    = "https://api.apollo.io/api/v1/mixed_people/api_search"

# Default seniority filter — skip junior engineers
_DEFAULT_SENIORITY = ["director", "vp", "c_suite", "partner", "manager", "senior", "founder"]


class ApolloSearchProvider:
    """Apollo.io contact search provider."""

    provider_name = "apollo"

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def find_contacts(
        self,
        company: str,
        domain: str,
        target_titles: list[str] | None = None,
        limit: int = 5,
    ) -> list[ContactResult]:
        """Search for contacts using Apollo's people search API."""
        payload: dict = {
            "q_organization_domains_list": [domain],
            "person_seniorities": _DEFAULT_SENIORITY,
            "per_page": min(limit * 3, 25),
            "page": 1,
        }

        if target_titles:
            payload["person_titles"] = target_titles

        async with httpx.AsyncClient(timeout=20.0) as client:
            try:
                resp = await client.post(
                    _SEARCH_URL,
                    json=payload,
                    # Key goes in header, NOT body (old body-key style is deprecated)
                    headers={
                        "Content-Type": "application/json",
                        "x-api-key": self._api_key,
                    },
                )
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401:
                    raise ValueError("Apollo.io: Invalid API key")
                if e.response.status_code == 422:
                    raise ValueError(f"Apollo.io: Invalid search parameters — {e.response.text[:200]}")
                raise ValueError(f"Apollo.io API error: {e.response.status_code}")
            except httpx.TimeoutException:
                raise ValueError("Apollo.io: Request timed out")

        people = resp.json().get("people", [])
        results: list[ContactResult] = []

        for person in people:
            email = person.get("email") or person.get("work_email", "")
            # Apollo free tier returns masked emails like "j***@google.com" — skip them
            if not email or "***" in email or email in ("N/A", ""):
                continue

            first = person.get("first_name") or ""
            last  = person.get("last_name") or ""
            title = person.get("title") or ""
            linkedin = person.get("linkedin_url") or None

            persona = classify_persona(title)
            results.append(ContactResult(
                first_name=first,
                last_name=last,
                email=email,
                title=title,
                company=company,
                linkedin_url=linkedin,
                confidence_score=None,
                persona_type=persona,
                source="apollo",
            ))

        results.sort(key=lambda r: r.persona_rank())
        return results[:limit]

    async def test_connection(self) -> bool:
        """Test Apollo.io API key validity."""
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.post(
                    _TEST_URL,
                    json={"per_page": 1},
                    headers={
                        "Content-Type": "application/json",
                        "x-api-key": self._api_key,
                    },
                )
                # 200 = key works; 422 = key valid but bad params (still OK)
                # 401 / 403 = invalid or expired key
                return resp.status_code not in (401, 403)
            except Exception:
                return False
