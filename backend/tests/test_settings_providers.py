"""
JobBus — Tests: Settings Provider Endpoints.

Tests save/test/retrieve for all provider keys and preferences.
"""
from __future__ import annotations
import pytest
from unittest.mock import patch, AsyncMock, MagicMock

from tests.conftest import make_client, auth_headers


class TestProviderStatus:
    def test_returns_status_dict(self):
        with patch("routers.settings.get_credential_service") as mock_cred, \
             patch("routers.settings.get_supabase_admin") as mock_supabase:
            mock_cred.return_value.get_provider_status.return_value = {
                "groq": True, "openai": False, "gemini": False,
                "hunter": True, "apollo": False, "rocketreach": False, "ollama_url": None
            }
            mock_supabase.return_value.table.return_value.select.return_value \
                .eq.return_value.single.return_value.execute.return_value.data = {
                "ai_provider": "groq", "ai_model": "auto", "search_provider": "hunter"
            }
            resp = make_client().get("/api/settings/providers/status",
                                     headers=auth_headers())
            assert resp.status_code == 200
            body = resp.json()
            assert body["groq"] is True
            assert body["ai_provider"] == "groq"


class TestSaveProviderKey:
    def test_save_groq_key(self):
        with patch("routers.settings.get_credential_service") as mock_cred:
            mock_cred.return_value.store_provider_key.return_value = None
            resp = make_client().post("/api/settings/providers/key",
                json={"field": "groq_key", "value": "gsk_test123"},
                headers=auth_headers())
            assert resp.status_code == 200

    def test_reject_unknown_field(self):
        with patch("routers.settings.get_credential_service"):
            resp = make_client().post("/api/settings/providers/key",
                json={"field": "unknown_key", "value": "abc"},
                headers=auth_headers())
            assert resp.status_code == 422

    def test_reject_empty_value(self):
        with patch("routers.settings.get_credential_service"):
            resp = make_client().post("/api/settings/providers/key",
                json={"field": "groq_key", "value": ""},
                headers=auth_headers())
            assert resp.status_code == 422


class TestTestProvider:
    @pytest.mark.asyncio
    async def test_groq_success(self):
        with patch("routers.settings.get_credential_service") as mock_cred, \
             patch("routers.settings._test_groq", AsyncMock(return_value=True)):
            mock_cred.return_value.get_decrypted_field.return_value = "gsk_key"
            resp = make_client().post(
                "/api/settings/providers/test",
                params={"field": "groq_key"},
                headers=auth_headers(),
            )
            assert resp.status_code == 200
            assert resp.json()["success"] is True

    @pytest.mark.asyncio
    async def test_groq_failure(self):
        with patch("routers.settings.get_credential_service") as mock_cred, \
             patch("routers.settings._test_groq", AsyncMock(return_value=False)):
            mock_cred.return_value.get_decrypted_field.return_value = "bad-key"
            resp = make_client().post(
                "/api/settings/providers/test",
                params={"field": "groq_key"},
                headers=auth_headers(),
            )
            assert resp.status_code == 200
            assert resp.json()["success"] is False

    def test_no_key_stored(self):
        with patch("routers.settings.get_credential_service") as mock_cred:
            mock_cred.return_value.get_decrypted_field.return_value = None
            resp = make_client().post(
                "/api/settings/providers/test",
                params={"field": "groq_key"},
                headers=auth_headers(),
            )
            assert resp.status_code == 400


class TestAIProviderPreference:
    def test_set_groq(self):
        with patch("routers.settings.get_supabase_admin") as mock_supabase:
            mock_supabase.return_value.table.return_value.update.return_value \
                .eq.return_value.execute.return_value = None
            resp = make_client().put("/api/settings/ai-provider",
                json={"provider": "groq", "model": "quality"},
                headers=auth_headers())
            assert resp.status_code == 200
            assert resp.json()["ai_provider"] == "groq"

    def test_rejects_invalid_provider(self):
        with patch("routers.settings.get_supabase_admin"):
            resp = make_client().put("/api/settings/ai-provider",
                json={"provider": "invalid", "model": "auto"},
                headers=auth_headers())
            assert resp.status_code == 422


class TestSearchProviderPreference:
    def test_set_apollo(self):
        with patch("routers.settings.get_supabase_admin") as mock_supabase:
            mock_supabase.return_value.table.return_value.update.return_value \
                .eq.return_value.execute.return_value = None
            resp = make_client().put("/api/settings/search-provider",
                json={"provider": "apollo"},
                headers=auth_headers())
            assert resp.status_code == 200

    def test_rejects_invalid(self):
        with patch("routers.settings.get_supabase_admin"):
            resp = make_client().put("/api/settings/search-provider",
                json={"provider": "linkedin"},
                headers=auth_headers())
            assert resp.status_code == 422


class TestEmailStyle:
    def test_get_email_style(self):
        with patch("routers.settings.get_supabase_admin") as mock_supabase:
            mock_supabase.return_value.table.return_value.select.return_value \
                .eq.return_value.single.return_value.execute.return_value.data = {
                "signature_name": "Neel M",
                "signature_title": "Backend Engineer",
                "signature_linkedin": "linkedin.com/in/neel",
                "custom_instructions": "Be concise.",
            }
            resp = make_client().get("/api/settings/email-style",
                headers=auth_headers())
            assert resp.status_code == 200
            assert resp.json()["signature_name"] == "Neel M"

    def test_update_email_style(self):
        with patch("routers.settings.get_supabase_admin") as mock_supabase:
            mock_supabase.return_value.table.return_value.update.return_value \
                .eq.return_value.execute.return_value = None
            resp = make_client().put("/api/settings/email-style",
                json={"signature_name": "Neel M"},
                headers=auth_headers())
            assert resp.status_code == 200


class TestCampaignDefaults:
    def test_update_defaults(self):
        with patch("routers.settings.get_supabase_admin") as mock_supabase:
            mock_supabase.return_value.table.return_value.update.return_value \
                .eq.return_value.execute.return_value = None
            resp = make_client().put("/api/settings/campaign-defaults",
                json={"send_delay_seconds": 300, "max_emails_per_day": 10},
                headers=auth_headers())
            assert resp.status_code == 200

    def test_rejects_delay_below_minimum(self):
        with patch("routers.settings.get_supabase_admin"):
            resp = make_client().put("/api/settings/campaign-defaults",
                json={"send_delay_seconds": 10},  # below 60s minimum
                headers=auth_headers())
            assert resp.status_code == 422
