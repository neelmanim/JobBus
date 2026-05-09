"""
JobBus Backend — Application Configuration.

All settings loaded from environment variables with sensible defaults.
"""

from __future__ import annotations


import os
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment."""

    # ── App ──────────────────────────────────────────────────
    app_name: str = "JobBus"
    app_version: str = "0.1.0"
    debug: bool = False
    cors_origins: list[str] = ["http://localhost:5173", "http://localhost:3000"]

    # ── Supabase ─────────────────────────────────────────────
    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_service_role_key: str = ""  # For admin operations

    # ── JWT (Supabase issues JWTs) ───────────────────────────
    jwt_secret: str = ""  # Supabase JWT secret for verification
    jwt_algorithm: str = "HS256"

    # ── Encryption (Fernet key for SMTP credentials) ─────────
    encryption_key: str = ""  # Generate with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

    # ── Job Board API ────────────────────────────────────────
    jsearch_api_key: str = ""  # Default JSearch (RapidAPI) key
    jsearch_api_host: str = "jsearch.p.rapidapi.com"

    # ── Rate Limits ──────────────────────────────────────────
    max_emails_per_hour: int = 30
    max_emails_per_day: int = 100

    # ── Frontend ─────────────────────────────────────────────
    frontend_url: str = ""
    environment: str = "development"

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "case_sensitive": False,
    }


@lru_cache
def get_settings() -> Settings:
    """Cached settings singleton."""
    return Settings()
