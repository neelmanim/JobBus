"""
JobBus — Provider Package.

Exports factory functions and base protocols.
"""
from providers.search.factory import get_search_provider
from providers.ai.factory import get_ai_provider

__all__ = ["get_search_provider", "get_ai_provider"]
