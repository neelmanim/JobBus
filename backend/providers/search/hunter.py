"""
JobBus — Hunter.io Search Provider.

GET /v2/domain-search → returns all known emails at a domain.
Free tier: 50 credits/month. Starter: $49/month → 500 credits.
"""

from __future__ import annotations

import httpx
import logging

from providers.search.base import ContactResult, SearchProvider, classify_persona

logger = logging.getLogger(__name__)

_BASE_URL = "https://api.hunter.io/v2"


class HunterSearchProvider:
    """Hunter.io contact search provider."""

    provider_name = "hunter"

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def find_contacts(
        self,
        company: str,
        domain: str,
        target_titles: list[str] | None = None,
        limit: int = 5,
    ) -> list[ContactResult]:
        """Search for contacts at a company domain using Hunter.io."""
        async with httpx.AsyncClient(timeout=15.0) as client:
            try:
                resp = await client.get(
                    f"{_BASE_URL}/domain-search",
                    params={
                        "domain": domain,
                        "api_key": self._api_key,
                        "limit": min(limit * 3, 100),  # fetch more to filter by title
                        "type": "personal",
                    },
                )
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401:
                    raise ValueError("Hunter.io: Invalid API key")
                if e.response.status_code == 429:
                    raise ValueError("Hunter.io: Rate limit / quota exceeded")
                raise ValueError(f"Hunter.io API error: {e.response.status_code}")
            except httpx.TimeoutException:
                raise ValueError("Hunter.io: Request timed out")

        data = resp.json().get("data", {})
        emails = data.get("emails", [])

        results: list[ContactResult] = []
        for entry in emails:
            email = entry.get("value", "")
            if not email:
                continue

            first = entry.get("first_name") or ""
            last = entry.get("last_name") or ""
            title = entry.get("position") or ""
            confidence = entry.get("confidence")

            persona = classify_persona(title)
            result = ContactResult(
                first_name=first,
                last_name=last,
                email=email,
                title=title,
                company=company,
                linkedin_url=entry.get("linkedin"),
                confidence_score=float(confidence) if confidence else None,
                persona_type=persona,
                source="hunter",
            )
            results.append(result)

        # Filter by target titles (fuzzy match) if provided
        if target_titles:
            lower_targets = [t.lower() for t in target_titles]
            filtered = [
                r for r in results
                if any(kw in r.title.lower() for kw in lower_targets)
            ]
            # Fall back to all results if filter is too aggressive
            results = filtered if filtered else results

        # Sort by persona rank (HM first), then confidence descending
        results.sort(key=lambda r: (r.persona_rank(), -(r.confidence_score or 0)))
        return results[:limit]

    async def test_connection(self) -> bool:
        """Test Hunter.io API key validity."""
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(
                    f"{_BASE_URL}/account",
                    params={"api_key": self._api_key},
                )
                return resp.status_code == 200
            except Exception:
                return False
