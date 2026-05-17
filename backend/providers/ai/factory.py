"""
JobBus — AI Provider Factory.

get_ai_provider(user) returns the correct AIProvider instance
for the user's configured provider and model preference.
Falls back to system Groq key in beginner mode.
"""

from __future__ import annotations

import logging
from database import get_supabase_admin
from services.credential_service import get_credential_service
from providers.ai.groq_provider import GroqAIProvider
from providers.ai.openai_provider import OpenAIProvider
from providers.ai.gemini_provider import GeminiAIProvider
from providers.ai.ollama_provider import OllamaProvider

logger = logging.getLogger(__name__)

# Cached system key (loaded once from DB)
_SYSTEM_GROQ_KEY: str | None = None


def _load_system_groq_key() -> str | None:
    try:
        supabase = get_supabase_admin()
        result = supabase.table("system_config").select("value").eq("key", "system_groq_key").execute()
        if result.data:
            return result.data[0].get("value")
    except Exception:
        pass
    return None


def get_ai_provider(user: dict) -> "GroqAIProvider | GeminiAIProvider | OpenAIProvider | OllamaProvider":
    """
    Return the correct AI provider for a user.

    Resolution order:
    1. User's selected provider + their own API key
    2. System Groq key (beginner mode fallback)
    3. Raise ValueError with friendly message
    """
    user_id = user["user_id"]
    cred = get_credential_service()

    # Use ai_provider already in the user dict (put there by get_current_user / profile cache)
    # Fall back to a fresh DB read only if not present
    selected_provider = user.get("ai_provider")
    selected_model    = user.get("ai_model")

    if not selected_provider:
        supabase = get_supabase_admin()
        profile_result = supabase.table("user_profiles").select(
            "ai_provider, ai_model"
        ).eq("user_id", user_id).single().execute()
        profile = profile_result.data or {}
        selected_provider = profile.get("ai_provider", "groq")
        selected_model    = profile.get("ai_model", "auto")

    selected_provider = selected_provider or "groq"
    selected_model    = selected_model    or "auto"

    # Try user's own key first
    try:
        if selected_provider == "ollama":
            base_url = cred.get_decrypted_field(user_id, "ollama_base_url") or "http://localhost:11434"
            return OllamaProvider(base_url=base_url, model=selected_model if selected_model != "auto" else "llama3.1:8b")

        user_key = cred.get_decrypted_field(user_id, f"{selected_provider}_key")
        if user_key:
            return _build_provider(selected_provider, user_key, selected_model)
    except Exception:
        pass

    # Fall back to system Groq key (beginner mode)
    global _SYSTEM_GROQ_KEY
    if not _SYSTEM_GROQ_KEY:
        _SYSTEM_GROQ_KEY = _load_system_groq_key()

    if _SYSTEM_GROQ_KEY:
        logger.info(f"Using system Groq key for user {user_id} (beginner mode)")
        return GroqAIProvider(api_key=_SYSTEM_GROQ_KEY, model="auto")

    raise ValueError(
        f"No AI provider configured. "
        "Go to Settings → AI Provider to add your API key. "
        "Groq has a free tier at console.groq.com — no credit card needed."
    )


def _build_provider(provider: str, api_key: str, model: str):
    """Build the correct provider instance."""
    if provider == "groq":
        return GroqAIProvider(api_key=api_key, model=model)
    elif provider == "openai":
        return OpenAIProvider(api_key=api_key, model=model)
    elif provider == "gemini":
        return GeminiAIProvider(api_key=api_key, model=model)
    else:
        raise ValueError(f"Unknown AI provider: {provider}")
