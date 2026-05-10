"""
JobBus — Search Provider Base Protocol.

All contact-search providers implement SearchProvider.
ContactResult is the canonical output structure.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable


# ─────────────────────────────────────────────────────────────
# Data Model
# ─────────────────────────────────────────────────────────────

@dataclass
class ContactResult:
    """Normalized contact record returned by any search provider."""

    first_name: str
    last_name: str
    email: str
    title: str
    company: str

    # Optional enrichment
    linkedin_url: str | None = None
    confidence_score: float | None = None   # 0-100, provider-specific
    persona_type: str = "other"             # hiring_manager | recruiter | founder | lead | other
    source: str = "unknown"                 # hunter | apollo | rocketreach

    def display_name(self) -> str:
        return f"{self.first_name} {self.last_name}".strip()

    def persona_rank(self) -> int:
        """Lower rank = higher priority (HM is most valuable)."""
        ranks = {
            "hiring_manager": 0,
            "lead": 1,
            "founder": 2,
            "recruiter": 3,
            "other": 4,
        }
        return ranks.get(self.persona_type, 4)


# ─────────────────────────────────────────────────────────────
# Protocol
# ─────────────────────────────────────────────────────────────

@runtime_checkable
class SearchProvider(Protocol):
    """Protocol all contact search providers must implement."""

    provider_name: str  # "hunter" | "apollo" | "rocketreach"

    async def find_contacts(
        self,
        company: str,
        domain: str,
        target_titles: list[str] | None = None,
        limit: int = 5,
    ) -> list[ContactResult]:
        """
        Find contacts at a company.

        Args:
            company:       Company display name (e.g., "Stripe")
            domain:        Company domain (e.g., "stripe.com")
            target_titles: Preferred titles to filter by (optional)
            limit:         Maximum contacts to return

        Returns:
            List of ContactResult sorted by persona_rank ascending
        """
        ...

    async def test_connection(self) -> bool:
        """Verify the API key is valid. Returns True on success."""
        ...


# ─────────────────────────────────────────────────────────────
# Persona classification helper
# ─────────────────────────────────────────────────────────────

_HIRING_MANAGER_KEYWORDS = {
    "engineering manager", "em ", "engineering lead", "tech lead",
    "vp engineering", "vp of engineering", "head of engineering",
    "director of engineering", "cto", "chief technology",
    "hiring manager", "team lead",
}

_FOUNDER_KEYWORDS = {
    "founder", "co-founder", "ceo", "chief executive",
    "president", "owner", "partner",
}

_RECRUITER_KEYWORDS = {
    "recruiter", "talent", "hr ", "human resources",
    "people ops", "talent acquisition", "sourcer",
}

_LEAD_KEYWORDS = {
    "lead", "senior", "principal", "staff engineer", "architect",
    "manager", "head of", "director",
}


def classify_persona(title: str) -> str:
    """Classify a job title into a persona type."""
    lower = title.lower()

    if any(kw in lower for kw in _HIRING_MANAGER_KEYWORDS):
        return "hiring_manager"
    if any(kw in lower for kw in _FOUNDER_KEYWORDS):
        return "founder"
    if any(kw in lower for kw in _RECRUITER_KEYWORDS):
        return "recruiter"
    if any(kw in lower for kw in _LEAD_KEYWORDS):
        return "lead"
    return "other"
