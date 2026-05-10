"""
JobBus — Tests: Settings Provider Endpoints.

Tests save/test/retrieve for all provider keys and preferences.
"""
from __future__ import annotations
import pytest
from unittest.mock import patch, AsyncMock, MagicMock
from fastapi.testclient import TestClient


def _make_app():
    from main import create_app
    return create_app()


@pytest.fixture(autouse=True)
def mock_current_user():
    with patch("middleware.auth_middleware.get_current_user", return_value={"user_id": "u1"}):
        yield


@pytest.fixture
def mock_cred():
    with patch("routers.settings.get_credential_service") as m:
        yield m


@pytest.fixture
def mock_supabase():
    with patch("routers.settings.get_supabase_admin") as m:
        yield m


class TestProviderStatus:
    def test_returns_status_dict(self, mock_cred, mock_supabase):
        mock_cred.return_value.get_provider_status.return_value = {
            "groq": True, "openai": False, "gemini": False,
            "hunter": True, "apollo": False, "rocketreach": False, "ollama_url": None
        }
        mock_supabase.return_value.table.return_value.select.return_value \
            .eq.return_value.single.return_value.execute.return_value.data = {
            "ai_provider": "groq", "ai_model": "auto", "search_provider": "hunter"
        }
        resp = TestClient(_make_app()).get("/api/settings/providers/status",
                                           headers={"Authorization": "Bearer t"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["groq"] is True
        assert body["ai_provider"] == "groq"


class TestSaveProviderKey:
    def test_save_groq_key(self, mock_cred, mock_supabase):
        mock_cred.return_value.store_provider_key.return_value = None
        resp = TestClient(_make_app()).post("/api/settings/providers/key",
            json={"field": "groq_key", "value": "gsk_test123"},
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 200

    def test_reject_unknown_field(self, mock_cred, mock_supabase):
        resp = TestClient(_make_app()).post("/api/settings/providers/key",
            json={"field": "unknown_key", "value": "abc"},
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 422

    def test_reject_empty_value(self, mock_cred, mock_supabase):
        resp = TestClient(_make_app()).post("/api/settings/providers/key",
            json={"field": "groq_key", "value": ""},
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 422


class TestTestProvider:
    @pytest.mark.asyncio
    async def test_groq_success(self, mock_cred):
        mock_cred.return_value.get_decrypted_field.return_value = "gsk_key"
        with patch("routers.settings._test_groq", AsyncMock(return_value=True)):
            resp = TestClient(_make_app()).post(
                "/api/settings/providers/test",
                params={"field": "groq_key"},
                headers={"Authorization": "Bearer t"},
            )
        assert resp.status_code == 200
        assert resp.json()["success"] is True

    @pytest.mark.asyncio
    async def test_groq_failure(self, mock_cred):
        mock_cred.return_value.get_decrypted_field.return_value = "bad-key"
        with patch("routers.settings._test_groq", AsyncMock(return_value=False)):
            resp = TestClient(_make_app()).post(
                "/api/settings/providers/test",
                params={"field": "groq_key"},
                headers={"Authorization": "Bearer t"},
            )
        assert resp.status_code == 200
        assert resp.json()["success"] is False

    def test_no_key_stored(self, mock_cred):
        mock_cred.return_value.get_decrypted_field.return_value = None
        resp = TestClient(_make_app()).post(
            "/api/settings/providers/test",
            params={"field": "groq_key"},
            headers={"Authorization": "Bearer t"},
        )
        assert resp.status_code == 400


class TestAIProviderPreference:
    def test_set_groq(self, mock_supabase):
        mock_supabase.return_value.table.return_value.update.return_value \
            .eq.return_value.execute.return_value = None
        resp = TestClient(_make_app()).put("/api/settings/ai-provider",
            json={"provider": "groq", "model": "quality"},
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 200
        assert resp.json()["ai_provider"] == "groq"

    def test_rejects_invalid_provider(self, mock_supabase):
        resp = TestClient(_make_app()).put("/api/settings/ai-provider",
            json={"provider": "invalid", "model": "auto"},
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 422


class TestSearchProviderPreference:
    def test_set_apollo(self, mock_supabase):
        mock_supabase.return_value.table.return_value.update.return_value \
            .eq.return_value.execute.return_value = None
        resp = TestClient(_make_app()).put("/api/settings/search-provider",
            json={"provider": "apollo"},
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 200

    def test_rejects_invalid(self, mock_supabase):
        resp = TestClient(_make_app()).put("/api/settings/search-provider",
            json={"provider": "linkedin"},
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 422


class TestEmailStyle:
    def test_get_email_style(self, mock_supabase):
        mock_supabase.return_value.table.return_value.select.return_value \
            .eq.return_value.single.return_value.execute.return_value.data = {
            "signature_name": "Neel M",
            "signature_title": "Backend Engineer",
            "signature_linkedin": "linkedin.com/in/neel",
            "custom_instructions": "Be concise.",
        }
        resp = TestClient(_make_app()).get("/api/settings/email-style",
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 200
        assert resp.json()["signature_name"] == "Neel M"

    def test_update_email_style(self, mock_supabase):
        mock_supabase.return_value.table.return_value.update.return_value \
            .eq.return_value.execute.return_value = None
        resp = TestClient(_make_app()).put("/api/settings/email-style",
            json={"signature_name": "Neel M"},
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 200


class TestCampaignDefaults:
    def test_update_defaults(self, mock_supabase):
        mock_supabase.return_value.table.return_value.update.return_value \
            .eq.return_value.execute.return_value = None
        resp = TestClient(_make_app()).put("/api/settings/campaign-defaults",
            json={"send_delay_seconds": 300, "max_emails_per_day": 10},
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 200

    def test_rejects_delay_below_minimum(self, mock_supabase):
        resp = TestClient(_make_app()).put("/api/settings/campaign-defaults",
            json={"send_delay_seconds": 10},  # below 60s minimum
            headers={"Authorization": "Bearer t"})
        assert resp.status_code == 422
