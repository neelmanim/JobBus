"""
JobBus — Tests: Provider Architecture.

Tests SearchProvider/AIProvider protocols, waterfall cascade, classify_persona.
"""
from __future__ import annotations
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from providers.search.base import ContactResult, classify_persona, SearchProvider
from providers.ai.base import GenerationResult, AIProvider


class TestClassifyPersona:
    def test_hiring_manager_em(self):
        assert classify_persona("Engineering Manager") == "hiring_manager"

    def test_hiring_manager_vp(self):
        assert classify_persona("VP of Engineering") == "hiring_manager"

    def test_founder(self):
        assert classify_persona("Co-Founder & CEO") == "founder"

    def test_recruiter(self):
        assert classify_persona("Senior Technical Recruiter") == "recruiter"

    def test_lead(self):
        assert classify_persona("Senior Software Engineer") == "lead"

    def test_other(self):
        assert classify_persona("Software Engineer") == "other"

    def test_empty_title(self):
        assert classify_persona("") == "other"


class TestContactResult:
    def test_display_name(self):
        c = ContactResult("Jane", "Doe", "jane@example.com", "EM", "Stripe", source="hunter")
        assert c.display_name() == "Jane Doe"

    def test_persona_rank_order(self):
        hm = ContactResult("", "", "", "", "", persona_type="hiring_manager", source="hunter")
        rec = ContactResult("", "", "", "", "", persona_type="recruiter", source="hunter")
        other = ContactResult("", "", "", "", "", persona_type="other", source="hunter")
        assert hm.persona_rank() < rec.persona_rank() < other.persona_rank()


class MockSearchProvider:
    provider_name = "mock"

    async def find_contacts(self, company, domain, target_titles=None, limit=5):
        return [ContactResult("Jane", "Doe", "jane@mock.io", "EM", company, source="mock")]

    async def test_connection(self):
        return True


class MockAIProvider:
    provider_name = "mock"
    model = "mock-model"

    async def generate(self, system_prompt, user_prompt, temperature=0.7, max_tokens=1024):
        return GenerationResult(text="OK", model="mock-model", provider="mock")

    async def test_connection(self):
        return True


def test_search_provider_protocol_compliance():
    assert isinstance(MockSearchProvider(), SearchProvider)


def test_ai_provider_protocol_compliance():
    assert isinstance(MockAIProvider(), AIProvider)


class TestAIProviderFactory:
    def test_builds_groq_provider(self):
        from providers.ai.factory import _build_provider
        from providers.ai.groq_provider import GroqAIProvider
        assert isinstance(_build_provider("groq", "key", "auto"), GroqAIProvider)

    def test_builds_openai_provider(self):
        from providers.ai.factory import _build_provider
        from providers.ai.openai_provider import OpenAIProvider
        assert isinstance(_build_provider("openai", "key", "auto"), OpenAIProvider)

    def test_builds_gemini_provider(self):
        from providers.ai.factory import _build_provider
        from providers.ai.gemini_provider import GeminiAIProvider
        assert isinstance(_build_provider("gemini", "key", "auto"), GeminiAIProvider)

    def test_raises_on_unknown_provider(self):
        from providers.ai.factory import _build_provider
        with pytest.raises(ValueError, match="Unknown AI provider"):
            _build_provider("unknown", "key", "auto")


class TestWaterfallSearch:
    @pytest.mark.asyncio
    async def test_uses_hunter_first(self):
        mock_user = {"user_id": "u1"}
        with patch("providers.search.factory.get_credential_service") as mc, \
             patch("providers.search.factory.get_supabase_admin"):
            mc.return_value.get_decrypted_field = lambda uid, field: "h-key" if field == "hunter_key" else None
            mock_hunter = AsyncMock()
            mock_hunter.find_contacts = AsyncMock(return_value=[
                ContactResult("J", "D", "j@s.com", "EM", "S", source="hunter")
            ])
            with patch("providers.search.factory.HunterSearchProvider", return_value=mock_hunter):
                from providers.search.factory import waterfall_search
                results, provider = await waterfall_search(mock_user, "Stripe", "stripe.com")
            assert len(results) == 1
            assert provider == "hunter"

    @pytest.mark.asyncio
    async def test_returns_empty_when_all_fail(self):
        mock_user = {"user_id": "u1"}
        with patch("providers.search.factory.get_credential_service") as mc, \
             patch("providers.search.factory.get_supabase_admin"), \
             patch("providers.search.factory._load_system_key", return_value=None):
            mc.return_value.get_decrypted_field = lambda uid, field: None
            from providers.search.factory import waterfall_search
            results, provider = await waterfall_search(mock_user, "X", "x.com")
            assert results == []
            assert provider == "none"
