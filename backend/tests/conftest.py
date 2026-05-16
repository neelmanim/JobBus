"""
Shared pytest fixtures and configuration for JobBus Web App tests.

Key patterns:
- Auth is bypassed via `app.dependency_overrides` (the correct FastAPI testing approach).
  Patching `middleware.auth_middleware.get_current_user` does NOT work because routers
  import the function directly at module load time, and FastAPI resolves Depends() via
  the app's override registry — not the original module.
- `mock_supabase` patches `routers.<module>.get_supabase_admin` per-test via fixture.
  For router-level patches, tests still use `with patch(...)` context managers.
"""

from __future__ import annotations

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

from middleware.auth_middleware import get_current_user, get_jwt_user, require_admin

# ─────────────────────────────────────────────────────────────
# App factory helpers (used by individual test files)
# ─────────────────────────────────────────────────────────────

_FAKE_USER = {
    "user_id": "u1",
    "email": "test@example.com",
    "display_name": "Test User",
    "mode": "beginner",
    "is_admin": False,
    "is_active": True,
}

_FAKE_ADMIN = {
    "user_id": "admin_001",
    "email": "admin@jobbus.io",
    "display_name": "Admin",
    "mode": "advanced",
    "is_admin": True,
    "is_active": True,
}


def make_app_with_auth_override(user: dict = None):
    """Create a FastAPI app with the auth dependency overridden.

    This is the correct way to bypass auth in FastAPI tests — using
    `dependency_overrides` instead of mock.patch on the middleware module.
    """
    from main import create_app

    resolved_user = user or _FAKE_USER
    app = create_app()
    app.dependency_overrides[get_current_user] = lambda: resolved_user
    app.dependency_overrides[get_jwt_user] = lambda: resolved_user
    app.dependency_overrides[require_admin] = lambda: {**resolved_user, "is_admin": True}
    return app


def make_client(user: dict = None) -> TestClient:
    """Convenience: create a TestClient with auth already overridden.

    Supports both direct use and context manager:
        make_client().get(...)
        with make_client() as client: client.get(...)
    """
    return TestClient(make_app_with_auth_override(user), raise_server_exceptions=False)


def auth_headers() -> dict:
    """Return a dummy Authorization header (auth is overridden, value is ignored)."""
    return {"Authorization": "Bearer test-token"}


# ─────────────────────────────────────────────────────────────
# Shared fixtures
# ─────────────────────────────────────────────────────────────

@pytest.fixture
def mock_ai_provider():
    """Mock AI provider for tests that don't need real API calls."""
    provider = AsyncMock()
    provider.generate.return_value = {
        "text": "Mock AI response",
        "model": "gemini-2.0-flash",
        "tokens_used": 100,
    }
    return provider


@pytest.fixture
def mock_db():
    """Mock database session."""
    db = MagicMock()
    db.execute = AsyncMock()
    db.commit = AsyncMock()
    db.rollback = AsyncMock()
    return db


@pytest.fixture
def sample_user():
    """A typical authenticated user."""
    return dict(_FAKE_USER)


@pytest.fixture
def admin_user():
    """An admin user."""
    return dict(_FAKE_ADMIN)


@pytest.fixture
def mock_current_user():
    """
    Patch get_current_user via dependency_overrides on a freshly created app.
    Tests that need this fixture get it from the shared client fixture instead —
    this fixture exists for backward compat with test files that declare it explicitly.
    """
    # No-op: the actual override is done in make_app_with_auth_override.
    # If a test file uses this fixture alongside make_client(), the override already applies.
    return _FAKE_USER


@pytest.fixture
def mock_supabase():
    """Patch get_supabase_admin broadly for settings/contacts tests."""
    with patch("database.get_supabase_admin") as m:
        yield m
