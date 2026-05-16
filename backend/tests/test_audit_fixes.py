"""
Tests for the comprehensive backend audit fixes.

Covers:
1. DB schema column names used in CredentialService
2. Onboarding auth.py table name fixes
3. EmailWriter multi-provider support (no SDK import crash)
4. FollowUpGenerator no-SDK init
5. Resume router table names
6. Ollama status key name fix
"""

from __future__ import annotations

import asyncio
import json
import sys
from unittest.mock import AsyncMock, MagicMock, patch

import pytest


# ─── Fix 1: CredentialService — all expected provider fields present ──────────

class TestCredentialServiceFields:
    """Verify that CredentialService maps all 6 provider logical names."""

    def test_all_provider_fields_present(self):
        from services.credential_service import CredentialService
        with patch("services.credential_service.get_settings") as mock_cfg:
            from cryptography.fernet import Fernet
            mock_cfg.return_value.encryption_key = Fernet.generate_key().decode()
            cs = CredentialService()
            expected_fields = {
                "groq_key", "openai_key", "gemini_key",
                "hunter_key", "apollo_key", "rocketreach_key",
                "ollama_base_url",
            }
            assert expected_fields.issubset(set(cs._PROVIDER_FIELDS.keys())), (
                f"Missing fields: {expected_fields - set(cs._PROVIDER_FIELDS.keys())}"
            )

    def test_ollama_is_unencrypted(self):
        from services.credential_service import CredentialService
        with patch("services.credential_service.get_settings") as mock_cfg:
            from cryptography.fernet import Fernet
            mock_cfg.return_value.encryption_key = Fernet.generate_key().decode()
            cs = CredentialService()
            assert "ollama_base_url" in cs._UNENCRYPTED_FIELDS

    def test_all_other_fields_are_encrypted(self):
        from services.credential_service import CredentialService
        with patch("services.credential_service.get_settings") as mock_cfg:
            from cryptography.fernet import Fernet
            mock_cfg.return_value.encryption_key = Fernet.generate_key().decode()
            cs = CredentialService()
            for field in ["groq_key", "openai_key", "gemini_key",
                          "hunter_key", "apollo_key", "rocketreach_key"]:
                assert field not in cs._UNENCRYPTED_FIELDS, (
                    f"{field} should be encrypted"
                )


# ─── Fix 2: CredentialService.get_provider_status — ollama key name ──────────

class TestProviderStatusKeyNames:
    """Verify get_provider_status returns 'ollama_base_url' not 'ollama_url'."""

    def test_ollama_status_key_is_ollama_base_url(self):
        from services.credential_service import CredentialService
        with patch("services.credential_service.get_settings") as mock_cfg, \
             patch("services.credential_service.get_supabase_admin") as mock_sb:
            from cryptography.fernet import Fernet
            mock_cfg.return_value.encryption_key = Fernet.generate_key().decode()

            mock_result = MagicMock()
            mock_result.data = [{
                "groq_key_encrypted": None,
                "openai_key_encrypted": None,
                "gemini_key_encrypted": "some_encrypted_value",
                "hunter_key_encrypted": None,
                "apollo_key_encrypted": None,
                "rocketreach_key_encrypted": None,
                "ollama_base_url": "http://localhost:11434",
            }]
            mock_sb.return_value.table.return_value.select.return_value.eq.return_value.execute.return_value = mock_result

            cs = CredentialService()
            status = cs.get_provider_status("user_abc")

            # Must return 'ollama_base_url' — not 'ollama_url' (the old bug)
            assert "ollama_base_url" in status, (
                "get_provider_status must return 'ollama_base_url' key"
            )
            assert "ollama_url" not in status, (
                "Stale key 'ollama_url' should not appear in status"
            )
            assert status["ollama_base_url"] is True
            assert status["gemini_key"] is True
            assert status["groq_key"] is False

    def test_all_expected_status_keys_present(self):
        from services.credential_service import CredentialService
        with patch("services.credential_service.get_settings") as mock_cfg, \
             patch("services.credential_service.get_supabase_admin") as mock_sb:
            from cryptography.fernet import Fernet
            mock_cfg.return_value.encryption_key = Fernet.generate_key().decode()

            mock_result = MagicMock()
            mock_result.data = [{}]  # All nulls
            mock_sb.return_value.table.return_value.select.return_value.eq.return_value.execute.return_value = mock_result

            cs = CredentialService()
            status = cs.get_provider_status("user_abc")

            expected = {"groq_key", "openai_key", "gemini_key",
                        "hunter_key", "apollo_key", "rocketreach_key",
                        "ollama_base_url"}
            missing = expected - set(status.keys())
            assert not missing, f"Missing status keys: {missing}"


# ─── Fix 3: EmailWriter — no SDK import at module level ──────────────────────

class TestEmailWriterNoSDKCrash:
    """Verify EmailWriter can be imported without google.generativeai installed."""

    def test_import_does_not_require_generativeai(self):
        """If this import raises ImportError for google.generativeai, test fails."""
        # Force reimport by removing cached module
        sys.modules.pop("services.email_writer", None)
        # Mock google.generativeai as unavailable
        sys.modules["google"] = None
        sys.modules["google.generativeai"] = None
        try:
            from services.email_writer import EmailWriter
            writer = EmailWriter(api_key="fake_key", provider="groq")
            assert writer._provider == "groq"
        finally:
            # Clean up mock
            sys.modules.pop("google", None)
            sys.modules.pop("google.generativeai", None)
            sys.modules.pop("services.email_writer", None)

    def test_email_writer_accepts_all_providers(self):
        from services.email_writer import EmailWriter
        for provider in ["gemini", "groq", "openai"]:
            writer = EmailWriter(api_key="test_key", provider=provider)
            assert writer._provider == provider

    def test_email_writer_falls_back_to_gemini_for_unknown_provider(self):
        from services.email_writer import EmailWriter
        writer = EmailWriter(api_key="test_key", provider="unknown_provider")
        assert writer._provider == "gemini"

    def test_all_providers_configured(self):
        from services.email_writer import _PROVIDER_CONFIGS
        assert "gemini" in _PROVIDER_CONFIGS
        assert "groq" in _PROVIDER_CONFIGS
        assert "openai" in _PROVIDER_CONFIGS

    def test_each_provider_has_required_keys(self):
        from services.email_writer import _PROVIDER_CONFIGS
        for name, cfg in _PROVIDER_CONFIGS.items():
            assert "base_url" in cfg, f"{name} missing base_url"
            assert "model" in cfg, f"{name} missing model"
            assert cfg["base_url"].startswith("https://"), f"{name} base_url not https"


# ─── Fix 4: EmailWriter._call_ai — provider routing ──────────────────────────

class TestCallAiProviderRouting:
    """Test that _call_ai routes to correct endpoints per provider."""

    def _make_mock_response(self, provider: str, text: str) -> dict:
        if provider == "gemini":
            return {
                "candidates": [{
                    "content": {"parts": [{"text": text}]}
                }]
            }
        else:
            return {
                "choices": [{"message": {"content": text}}]
            }

    @pytest.mark.asyncio
    async def test_gemini_uses_correct_endpoint(self):
        from services.email_writer import _call_ai
        captured = {}

        async def mock_post(url, **kwargs):
            captured["url"] = url
            captured["params"] = kwargs.get("params", {})
            resp = MagicMock()
            resp.is_success = True
            resp.json.return_value = self._make_mock_response("gemini", "test response")
            return resp

        with patch("httpx.AsyncClient") as MockClient:
            MockClient.return_value.__aenter__ = AsyncMock(return_value=MagicMock(post=mock_post))
            MockClient.return_value.__aexit__ = AsyncMock(return_value=False)
            result = await _call_ai("gemini", "fake_api_key", "test prompt")

        assert "generativelanguage.googleapis.com" in captured["url"]
        assert captured["params"].get("key") == "fake_api_key"
        assert result == "test response"

    @pytest.mark.asyncio
    async def test_groq_uses_openai_compat_endpoint(self):
        from services.email_writer import _call_ai
        captured = {}

        async def mock_post(url, **kwargs):
            captured["url"] = url
            captured["headers"] = kwargs.get("headers", {})
            resp = MagicMock()
            resp.is_success = True
            resp.json.return_value = self._make_mock_response("groq", "groq response")
            return resp

        with patch("httpx.AsyncClient") as MockClient:
            MockClient.return_value.__aenter__ = AsyncMock(return_value=MagicMock(post=mock_post))
            MockClient.return_value.__aexit__ = AsyncMock(return_value=False)
            result = await _call_ai("groq", "gsk_test_key", "test prompt")

        assert "groq.com" in captured["url"]
        assert "Bearer gsk_test_key" in captured["headers"].get("Authorization", "")
        assert result == "groq response"

    @pytest.mark.asyncio
    async def test_openai_uses_openai_endpoint(self):
        from services.email_writer import _call_ai
        captured = {}

        async def mock_post(url, **kwargs):
            captured["url"] = url
            resp = MagicMock()
            resp.is_success = True
            resp.json.return_value = self._make_mock_response("openai", "openai response")
            return resp

        with patch("httpx.AsyncClient") as MockClient:
            MockClient.return_value.__aenter__ = AsyncMock(return_value=MagicMock(post=mock_post))
            MockClient.return_value.__aexit__ = AsyncMock(return_value=False)
            result = await _call_ai("openai", "sk_test_key", "test prompt")

        assert "openai.com" in captured["url"]
        assert result == "openai response"

    @pytest.mark.asyncio
    async def test_api_error_raises_value_error(self):
        from services.email_writer import _call_ai

        async def mock_post(url, **kwargs):
            resp = MagicMock()
            resp.is_success = False
            resp.status_code = 401
            resp.text = "Unauthorized: invalid API key"
            return resp

        with patch("httpx.AsyncClient") as MockClient:
            MockClient.return_value.__aenter__ = AsyncMock(return_value=MagicMock(post=mock_post))
            MockClient.return_value.__aexit__ = AsyncMock(return_value=False)
            with pytest.raises(ValueError, match="401"):
                await _call_ai("gemini", "bad_key", "test prompt")

    @pytest.mark.asyncio
    async def test_empty_gemini_candidates_raises(self):
        from services.email_writer import _call_ai

        async def mock_post(url, **kwargs):
            resp = MagicMock()
            resp.is_success = True
            resp.json.return_value = {"candidates": []}
            return resp

        with patch("httpx.AsyncClient") as MockClient:
            MockClient.return_value.__aenter__ = AsyncMock(return_value=MagicMock(post=mock_post))
            MockClient.return_value.__aexit__ = AsyncMock(return_value=False)
            with pytest.raises(ValueError, match="no candidates"):
                await _call_ai("gemini", "key", "test prompt")


# ─── Fix 5: EmailWriter.generate — JSON parsing and fallback ─────────────────

class TestEmailWriterGenerate:
    """Test EmailWriter.generate with mocked AI responses."""

    def _make_writer(self, provider: str = "groq") -> object:
        from services.email_writer import EmailWriter
        return EmailWriter(api_key="test_key", provider=provider)

    def _mock_contact(self) -> dict:
        return {
            "id": "c1",
            "first_name": "Jane",
            "last_name": "Smith",
            "title": "Engineering Manager",
            "company": "Acme Corp",
            "email": "jane@acme.com",
        }

    def _mock_resume(self) -> dict:
        return {
            "name": "Alex Dev",
            "role": "Software Engineer",
            "skills": ["Python", "FastAPI"],
            "achievements": [
                "Reduced deployment time by 60%",
                "Built ML pipeline serving 10M requests/day",
            ],
            "email_context": "5 years backend, Python + infra",
        }

    def _mock_angle(self) -> dict:
        return {
            "angle_type": "hiring_based",
            "hook_guidance": "Reference their recent engineering blog post",
            "reasoning": "They have 3 open backend roles",
            "signals_used": ["job_posting"],
        }

    @pytest.mark.asyncio
    async def test_generate_parses_valid_json_response(self):
        writer = self._make_writer()
        ai_response = json.dumps({
            "subject": "Quick backend question for Jane",
            "body": "Hi Jane, saw Acme's recent post. Would love to chat."
        })

        with patch("services.email_writer._call_ai", new=AsyncMock(return_value=ai_response)):
            draft = await writer.generate(
                self._mock_contact(), self._mock_resume(), self._mock_angle()
            )

        assert draft.subject == "Quick backend question for Jane"
        assert "Jane" in draft.body
        assert draft.angle_type is not None

    @pytest.mark.asyncio
    async def test_generate_handles_json_wrapped_in_markdown(self):
        writer = self._make_writer()
        ai_response = '```json\n{"subject": "Hello Jane", "body": "Test body"}\n```'

        with patch("services.email_writer._call_ai", new=AsyncMock(return_value=ai_response)):
            draft = await writer.generate(
                self._mock_contact(), self._mock_resume(), self._mock_angle()
            )

        assert draft.subject == "Hello Jane"

    @pytest.mark.asyncio
    async def test_generate_falls_back_on_invalid_json(self):
        writer = self._make_writer()
        ai_response = "This is not JSON at all, just text"

        with patch("services.email_writer._call_ai", new=AsyncMock(return_value=ai_response)):
            draft = await writer.generate(
                self._mock_contact(), self._mock_resume(), self._mock_angle()
            )

        # Falls back to generic subject with first name
        assert "Jane" in draft.subject or len(draft.subject) > 0
        assert len(draft.body) > 0

    @pytest.mark.asyncio
    async def test_generate_batch_returns_one_draft_per_contact(self):
        writer = self._make_writer()
        contacts = [
            {**self._mock_contact(), "id": f"c{i}", "first_name": f"User{i}"}
            for i in range(3)
        ]
        ai_response = json.dumps({"subject": "Test", "body": "Body"})

        with patch("services.email_writer._call_ai", new=AsyncMock(return_value=ai_response)):
            drafts = await writer.generate_batch(
                contacts, self._mock_resume(), self._mock_angle()
            )

        assert len(drafts) == 3

    @pytest.mark.asyncio
    async def test_generate_propagates_angle_metadata(self):
        writer = self._make_writer()
        ai_response = json.dumps({"subject": "Sub", "body": "Body"})
        angle = self._mock_angle()

        with patch("services.email_writer._call_ai", new=AsyncMock(return_value=ai_response)):
            draft = await writer.generate(
                self._mock_contact(), self._mock_resume(), angle
            )

        assert draft.signals_used == [{"signal": "job_posting"}]
        assert draft.angle_reasoning == "They have 3 open backend roles"


# ─── Fix 6: FollowUpGenerator — no SDK import at module level ────────────────

class TestFollowUpGeneratorNoSDKCrash:

    def test_import_does_not_require_generativeai(self):
        sys.modules.pop("services.follow_up_generator", None)
        sys.modules["google"] = None
        sys.modules["google.generativeai"] = None
        try:
            from services.follow_up_generator import FollowUpGenerator
            gen = FollowUpGenerator(api_key="fake_key", provider="groq")
            assert gen._provider == "groq"
            assert gen._api_key == "fake_key"
        finally:
            sys.modules.pop("google", None)
            sys.modules.pop("google.generativeai", None)
            sys.modules.pop("services.follow_up_generator", None)

    def test_generate_followup_is_async(self):
        from services.follow_up_generator import FollowUpGenerator
        import inspect
        gen = FollowUpGenerator(api_key="key")
        assert inspect.iscoroutinefunction(gen.generate_followup), (
            "generate_followup must be async since it awaits _call_ai"
        )

    def test_max_followups_exceeded_raises(self):
        from services.follow_up_generator import FollowUpGenerator, MaxFollowUpsReached
        gen = FollowUpGenerator(api_key="key")
        with pytest.raises(MaxFollowUpsReached):
            # sequence=3 > MAX_FOLLOWUPS=2
            asyncio.get_event_loop().run_until_complete(
                gen.generate_followup(
                    initial_draft={"subject": "Test", "body": "Test", "id": "d1",
                                   "sent_at": "2024-01-01T10:00:00+00:00"},
                    sequence=3,
                    resume_profile={"name": "Alex", "role": "SWE",
                                    "achievements": ["Built X"]},
                )
            )


# ─── Fix 7: Auth router — table name verification (unit) ─────────────────────

class TestOnboardingTableNames:
    """Ensure the onboarding endpoint uses correct Supabase table names."""

    def test_auth_router_uses_smtp_credentials_table(self):
        """Auth onboarding now delegates SMTP storage to cred_service.store().
        Verify that auth.py calls .store() and doesn't use the wrong table directly.
        """
        import os
        router_path = os.path.join(
            os.path.dirname(__file__), "..", "routers", "auth.py"
        )
        with open(router_path) as f:
            source = f.read()

        # auth.py must NOT directly reference the wrong table name
        assert "user_smtp_credentials" not in source, (
            "auth.py still references wrong table 'user_smtp_credentials'"
        )
        # auth.py must delegate to cred_service.store() (which uses the correct table)
        assert "cred_service.store(" in source, (
            "auth.py must delegate SMTP storage to cred_service.store()"
        )

        # Also verify credential_service uses the correct table
        cs_path = os.path.join(
            os.path.dirname(__file__), "..", "services", "credential_service.py"
        )
        with open(cs_path) as f:
            cs_source = f.read()
        assert "\"smtp_credentials\"" in cs_source or "'smtp_credentials'" in cs_source, (
            "credential_service.py must reference 'smtp_credentials' table"
        )

    def test_auth_router_uses_resume_profiles_table(self):
        import os
        router_path = os.path.join(
            os.path.dirname(__file__), "..", "routers", "auth.py"
        )
        with open(router_path) as f:
            source = f.read()

        assert "user_resume_profiles" not in source, (
            "auth.py still references wrong table 'user_resume_profiles' "
            "(correct: 'resume_profiles')"
        )
        assert "resume_profiles" in source, (
            "auth.py must reference 'resume_profiles'"
        )

    def test_auth_router_no_nonexistent_function_call(self):
        import os
        router_path = os.path.join(
            os.path.dirname(__file__), "..", "routers", "auth.py"
        )
        with open(router_path) as f:
            source = f.read()

        assert "save_resume_profile_from_text" not in source, (
            "auth.py calls save_resume_profile_from_text which does not exist"
        )


# ─── Fix 8: Resume router — table name verification ──────────────────────────

class TestResumeRouterTableNames:

    def test_resume_router_uses_resume_profiles_table(self):
        import os
        router_path = os.path.join(
            os.path.dirname(__file__), "..", "routers", "resume.py"
        )
        with open(router_path) as f:
            source = f.read()

        assert "user_resume_profiles" not in source, (
            "resume.py still references wrong table 'user_resume_profiles' "
            "(correct: 'resume_profiles')"
        )


# ─── Fix 9: Migration SQL completeness check ─────────────────────────────────

class TestMigrationSQL:
    """Verify migration 002 adds all required columns."""

    def _read_migration(self) -> str:
        import os
        path = os.path.join(
            os.path.dirname(__file__), "..", "migrations",
            "002_add_provider_columns.sql"
        )
        with open(path) as f:
            return f.read()

    def test_migration_002_exists(self):
        import os
        path = os.path.join(
            os.path.dirname(__file__), "..", "migrations",
            "002_add_provider_columns.sql"
        )
        assert os.path.exists(path), "Migration 002 must exist"

    def test_migration_adds_groq_key(self):
        assert "groq_key_encrypted" in self._read_migration()

    def test_migration_adds_openai_key(self):
        assert "openai_key_encrypted" in self._read_migration()

    def test_migration_adds_hunter_key(self):
        assert "hunter_key_encrypted" in self._read_migration()

    def test_migration_adds_apollo_key(self):
        assert "apollo_key_encrypted" in self._read_migration()

    def test_migration_adds_rocketreach_key(self):
        assert "rocketreach_key_encrypted" in self._read_migration()

    def test_migration_adds_ollama_base_url(self):
        assert "ollama_base_url" in self._read_migration()

    def test_migration_adds_onboarding_complete(self):
        assert "onboarding_complete" in self._read_migration()

    def test_migration_uses_if_not_exists(self):
        """Migration must be idempotent — safe to run multiple times."""
        sql = self._read_migration()
        alter_count = sql.upper().count("ADD COLUMN IF NOT EXISTS")
        assert alter_count >= 7, (
            f"Expected at least 7 idempotent ADD COLUMN IF NOT EXISTS, found {alter_count}"
        )
