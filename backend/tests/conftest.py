"""
Shared pytest fixtures and configuration for JobBus Web App tests.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock


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
    return {
        "user_id": "user_001",
        "email": "test@example.com",
        "display_name": "Test User",
        "mode": "beginner",
        "is_admin": False,
        "is_active": True,
    }


@pytest.fixture
def admin_user():
    """An admin user."""
    return {
        "user_id": "admin_001",
        "email": "admin@jobbus.io",
        "display_name": "Admin",
        "mode": "advanced",
        "is_admin": True,
        "is_active": True,
    }
