"""
Test Suite: Signal Collectors
Tests the individual data collectors that feed the Opportunity Scorer.

Collectors:
  - JobBoardCollector: Fetches job listings (JSearch API default, user API supported)
  - FundingCollector: Checks for recent funding rounds
  - CompanyInfoCollector: Gets company size, industry, remote status
"""

import pytest
from unittest.mock import AsyncMock, patch


# ============================================================
# JOB BOARD COLLECTOR
# ============================================================

class TestJobBoardCollector:
    """Tests for fetching job board data."""

    def test_search_returns_matching_jobs(self):
        """Should return jobs matching the query keywords."""
        # collector = JobBoardCollector(api_key="test_key")
        # results = await collector.search(query="Software Engineer", location="Remote")
        # assert len(results) > 0
        # assert all(r.title is not None for r in results)
        # assert all(r.company is not None for r in results)
        pytest.skip("Awaiting implementation")

    def test_search_with_user_provided_api_key(self):
        """Should work with user's own API key."""
        # collector = JobBoardCollector(api_key="user_custom_key")
        # results = await collector.search(query="Backend Engineer")
        # assert len(results) >= 0  # Should not error
        pytest.skip("Awaiting implementation")

    def test_invalid_api_key_returns_clear_error(self):
        """Invalid API key should return actionable error, not crash."""
        # collector = JobBoardCollector(api_key="invalid_key")
        # with pytest.raises(APIKeyError) as exc:
        #     await collector.search(query="SWE")
        # assert "api key" in str(exc.value).lower()
        pytest.skip("Awaiting implementation")

    def test_rate_limit_handled_gracefully(self):
        """Should handle 429 rate limit with retry or clear message."""
        # collector = JobBoardCollector(api_key="test_key")
        # with patch("httpx.AsyncClient.get", side_effect=rate_limit_response):
        #     result = await collector.search(query="SWE")
        #     assert result.error_type == "rate_limited"
        #     assert "retry" in result.message.lower()
        pytest.skip("Awaiting implementation")

    def test_empty_results_handled(self):
        """No matching jobs should return empty list, not error."""
        # collector = JobBoardCollector(api_key="test_key")
        # results = await collector.search(query="Quantum Underwater Basket Weaving Engineer")
        # assert results == []
        pytest.skip("Awaiting implementation")

    def test_job_url_extraction(self):
        """Should extract direct job URL from results."""
        # collector = JobBoardCollector(api_key="test_key")
        # results = await collector.search(query="SWE")
        # for r in results:
        #     assert r.url is None or r.url.startswith("http")
        pytest.skip("Awaiting implementation")


# ============================================================
# COMPANY INFO COLLECTOR
# ============================================================

class TestCompanyInfoCollector:
    """Tests for fetching company metadata."""

    def test_returns_company_size(self):
        """Should return estimated company size range."""
        # collector = CompanyInfoCollector()
        # info = await collector.get_info("Stripe")
        # assert info.size_range is not None  # e.g., "1000-5000"
        pytest.skip("Awaiting implementation")

    def test_returns_industry(self):
        """Should return company industry."""
        # info = await collector.get_info("Stripe")
        # assert info.industry is not None  # e.g., "FinTech"
        pytest.skip("Awaiting implementation")

    def test_unknown_company_returns_defaults(self):
        """Unknown company should return None/defaults, not error."""
        # info = await collector.get_info("TotallyFakeCompanyXYZ123")
        # assert info is not None
        # assert info.size_range is None  # Unknown, not error
        pytest.skip("Awaiting implementation")


# ============================================================
# USER-PROVIDED JOB URL
# ============================================================

class TestUserProvidedJobURL:
    """Tests for when user pastes a specific job URL."""

    def test_valid_url_extracts_signals(self):
        """Valid job URL should extract company + role signals."""
        # collector = JobURLCollector()
        # signals = await collector.extract("https://careers.acme.com/senior-backend-engineer")
        # assert signals.company_name is not None
        # assert signals.role_title is not None
        # assert signals.hiring_active is True
        pytest.skip("Awaiting implementation")

    def test_invalid_url_returns_error(self):
        """Non-job URL should return clear error."""
        # collector = JobURLCollector()
        # with pytest.raises(InvalidJobURL):
        #     await collector.extract("https://google.com")
        pytest.skip("Awaiting implementation")

    def test_expired_listing_detected(self):
        """Should detect or flag potentially expired job listings."""
        # collector = JobURLCollector()
        # signals = await collector.extract("https://careers.acme.com/expired-role")
        # # Should not crash — may return hiring_active=None for uncertain
        pytest.skip("Awaiting implementation")
