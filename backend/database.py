"""
JobBus Backend — Supabase Database Client.

Provides both the Supabase client (for auth/storage) and direct
PostgreSQL connection (for complex queries via asyncpg if needed).
"""

from supabase import create_client, Client
from functools import lru_cache
from config import get_settings


@lru_cache
def get_supabase_client() -> Client:
    """Get the Supabase client for auth + database operations."""
    settings = get_settings()
    return create_client(settings.supabase_url, settings.supabase_anon_key)


@lru_cache
def get_supabase_admin() -> Client:
    """Get the Supabase admin client (service role) for admin operations.
    
    This bypasses Row Level Security — use only in admin endpoints.
    """
    settings = get_settings()
    return create_client(settings.supabase_url, settings.supabase_service_role_key)
