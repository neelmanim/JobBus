"""
JobBus — Search Provider Factory.

Implements the waterfall cascade pattern:
  Hunter → Apollo → RocketReach (auto-fallback on 0 results)

get_search_provider(user) returns the configured provider for that user.
waterfall_search() tries all available providers in sequence.
"""

from __future__ import annotations

import logging
from database import get_supabase_admin
from services.credential_service import get_credential_service
from providers.search.base import ContactResult
from providers.search.hunter import HunterSearchProvider
from providers.search.apollo import ApolloSearchProvider
from providers.search.rocketreach import RocketReachSearchProvider

logger = logging.getLogger(__name__)

# System-level keys for Beginner mode (admin-configured)
_SYSTEM_HUNTER_KEY: str | None = None


def _load_system_key(config_key: str) -> str | None:
    """Load a system config value from the DB."""
    try:
        supabase = get_supabase_admin()
        result = supabase.table("system_config").select("value").eq("key", config_key).execute()
        if result.data:
            return result.data[0].get("value")
    except Exception:
        pass
    return None


def get_search_provider(user: dict) -> "HunterSearchProvider | ApolloSearchProvider | RocketReachSearchProvider":
    """
    Return the configured search provider for a user.

    Falls back to system Hunter.io key in beginner mode.
    Raises ValueError if no key is available.
    """
    user_id = user["user_id"]
    cred = get_credential_service()

    # Determine which provider the user has selected
    supabase = get_supabase_admin()
    profile = supabase.table("user_profiles").select(
        "ai_provider, search_provider"
    ).eq("user_id", user_id).single().execute()

    selected = (profile.data or {}).get("search_provider", "hunter")

    # Get user's API key for the selected provider
    try:
        user_key = cred.get_decrypted_field(user_id, f"{selected}_key")
    except Exception:
        user_key = None

    if not user_key:
        # Try system key (beginner mode — Hunter only)
        if selected == "hunter":
            global _SYSTEM_HUNTER_KEY
            if not _SYSTEM_HUNTER_KEY:
                _SYSTEM_HUNTER_KEY = _load_system_key("system_hunter_key")
            user_key = _SYSTEM_HUNTER_KEY

        if not user_key:
            raise ValueError(
                f"No API key configured for {selected}. "
                "Go to Settings → Contact Search to add your key."
            )

    providers = {
        "hunter": HunterSearchProvider,
        "apollo": ApolloSearchProvider,
        "rocketreach": RocketReachSearchProvider,
    }
    cls = providers.get(selected, HunterSearchProvider)
    return cls(user_key)


async def waterfall_search(
    user: dict,
    company: str,
    domain: str,
    target_titles: list[str] | None = None,
    limit: int = 5,
) -> tuple[list[ContactResult], str]:
    """
    Try providers in waterfall order: Hunter → Apollo → RocketReach.
    Returns (results, provider_name_that_succeeded).
    Never raises — returns empty list if all fail.
    """
    user_id = user["user_id"]
    cred = get_credential_service()

    # Build available providers in cascade order
    cascade = []

    for name, cls in [
        ("hunter", HunterSearchProvider),
        ("apollo", ApolloSearchProvider),
        ("rocketreach", RocketReachSearchProvider),
    ]:
        try:
            key = cred.get_decrypted_field(user_id, f"{name}_key")
            if key:
                cascade.append((name, cls(key)))
        except Exception:
            pass

    # Add system Hunter key if available
    if not cascade:
        global _SYSTEM_HUNTER_KEY
        if not _SYSTEM_HUNTER_KEY:
            _SYSTEM_HUNTER_KEY = _load_system_key("system_hunter_key")
        if _SYSTEM_HUNTER_KEY:
            cascade.append(("hunter_system", HunterSearchProvider(_SYSTEM_HUNTER_KEY)))

    for provider_name, provider in cascade:
        try:
            results = await provider.find_contacts(company, domain, target_titles, limit)
            if results:
                logger.info(f"Waterfall: {provider_name} returned {len(results)} contacts for {domain}")
                return results, provider_name
        except Exception as e:
            logger.warning(f"Waterfall: {provider_name} failed for {domain}: {e}")
            continue

    logger.warning(f"Waterfall: all providers failed for {domain}")
    return [], "none"
