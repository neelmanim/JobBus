"""
JobBus — Apollo.io Search Provider.

POST /v1/mixed_people/search → search by title, company, domain.
Requires Organization plan ($119/user/month min).
Used in Advanced mode when user provides their own key.
"""

from __future__ import annotations

import httpx
import logging

from providers.search.base import ContactResult, SearchProvider, classify_persona

logger = logging.getLogger(__name__)

_BASE_URL = "https://api.apollo.io/v1"

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
            "api_key": self._api_key,
            "q_organization_domains": [domain],
            "person_seniorities": _DEFAULT_SENIORITY,
            "contact_email_status": ["verified", "guessed", "unavailable", "bounced", "pending_manual_fulfillment"],
            "per_page": min(limit * 3, 25),
            "page": 1,
        }

        if target_titles:
            payload["person_titles"] = target_titles

        async with httpx.AsyncClient(timeout=20.0) as client:
            try:
                resp = await client.post(
                    f"{_BASE_URL}/mixed_people/search",
                    json=payload,
                    headers={"Content-Type": "application/json"},
                )
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401:
                    raise ValueError("Apollo.io: Invalid API key — requires Organization plan")
                if e.response.status_code == 422:
                    raise ValueError("Apollo.io: Invalid search parameters")
                raise ValueError(f"Apollo.io API error: {e.response.status_code}")
            except httpx.TimeoutException:
                raise ValueError("Apollo.io: Request timed out")

        people = resp.json().get("people", [])
        results: list[ContactResult] = []

        for person in people:
            email = person.get("email")
            if not email or email in ("", "N/A"):
                # Try work email
                email = person.get("work_email", "")
            if not email:
                continue

            first = person.get("first_name") or ""
            last = person.get("last_name") or ""
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
                    f"{_BASE_URL}/auth/health",
                    json={"api_key": self._api_key},
                    headers={"Content-Type": "application/json"},
                )
                return resp.status_code == 200
            except Exception:
                return False
