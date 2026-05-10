"""
JobBus — RocketReach Search Provider.

POST /v2/api/search → search contacts by company, title.
Used as final fallback in the waterfall cascade.
Best for executives and hard-to-find profiles.
"""

from __future__ import annotations

import httpx
import logging

from providers.search.base import ContactResult, classify_persona

logger = logging.getLogger(__name__)

_BASE_URL = "https://api.rocketreach.co/v2"


class RocketReachSearchProvider:
    """RocketReach contact search provider."""

    provider_name = "rocketreach"

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def find_contacts(
        self,
        company: str,
        domain: str,
        target_titles: list[str] | None = None,
        limit: int = 5,
    ) -> list[ContactResult]:
        """Search for contacts using RocketReach API."""
        query: dict = {
            "current_employer": [company],
        }
        if target_titles:
            query["current_title"] = target_titles

        payload = {
            "query": query,
            "start": 1,
            "page_size": min(limit * 2, 10),
        }

        async with httpx.AsyncClient(timeout=20.0) as client:
            try:
                resp = await client.post(
                    f"{_BASE_URL}/api/search",
                    json=payload,
                    headers={
                        "Api-Key": self._api_key,
                        "Content-Type": "application/json",
                    },
                )
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401:
                    raise ValueError("RocketReach: Invalid API key")
                raise ValueError(f"RocketReach API error: {e.response.status_code}")
            except httpx.TimeoutException:
                raise ValueError("RocketReach: Request timed out")

        profiles = resp.json().get("profiles", [])
        results: list[ContactResult] = []

        for profile in profiles:
            emails = profile.get("emails") or []
            email = next((e.get("email") for e in emails if e.get("email")), None)
            if not email:
                continue

            name = profile.get("name") or ""
            parts = name.split(" ", 1)
            first = parts[0] if parts else ""
            last = parts[1] if len(parts) > 1 else ""
            title = profile.get("current_title") or ""

            persona = classify_persona(title)
            results.append(ContactResult(
                first_name=first,
                last_name=last,
                email=email,
                title=title,
                company=company,
                linkedin_url=profile.get("linkedin_url"),
                confidence_score=None,
                persona_type=persona,
                source="rocketreach",
            ))

        results.sort(key=lambda r: r.persona_rank())
        return results[:limit]

    async def test_connection(self) -> bool:
        """Test RocketReach API key validity."""
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(
                    f"{_BASE_URL}/api/account",
                    headers={"Api-Key": self._api_key},
                )
                return resp.status_code == 200
            except Exception:
                return False
