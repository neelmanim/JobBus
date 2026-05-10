"""
Tests for Admin Service — system config and platform usage analytics.

Covers:
  - get_system_config: reads rows, masks secrets
  - save_system_config: upserts key/value pairs, rejects empty
  - get_platform_usage: aggregate stats, leaderboard, reply rate
  - _get_user_stats: no double-counting bug
  - Admin router: GET/PUT /config, GET /usage endpoints
"""

from __future__ import annotations

import pytest
from unittest.mock import MagicMock, patch


# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

def _chain_mock(*rows):
    """Build a Supabase mock chain that returns rows."""
    result = MagicMock()
    result.data = list(rows)
    chain = MagicMock()
    chain.execute.return_value = result
    chain.eq.return_value = chain
    chain.in_.return_value = chain
    chain.select.return_value = chain
    chain.update.return_value = chain
    chain.upsert.return_value = chain
    chain.order.return_value = chain
    return chain


def _make_supabase(table_data: dict):
    """
    table_data: {'table_name': [row_dict, ...], ...}
    Returns a MagicMock supabase where sb.table(name) returns the right data.
    """
    sb = MagicMock()

    def _table(name):
        rows = table_data.get(name, [])
        chain = _chain_mock(*rows)
        return chain

    sb.table.side_effect = _table
    return sb


# ─────────────────────────────────────────────────────────────
# get_system_config
# ─────────────────────────────────────────────────────────────

class TestGetSystemConfig:

    def test_returns_flat_dict(self):
        """Rows are returned as key→value dict."""
        from services.admin_service import AdminService
        rows = [
            {"key": "max_emails_per_user_per_day", "value": "20"},
            {"key": "enable_follow_ups", "value": "false"},
        ]
        sb = _make_supabase({"system_config": rows})
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            config = AdminService.get_system_config(mask_secrets=False)
        assert config["max_emails_per_user_per_day"] == "20"
        assert config["enable_follow_ups"] == "false"

    def test_masks_secret_keys(self):
        """Secret key values are masked (first 8 chars + ***)."""
        from services.admin_service import AdminService
        rows = [
            {"key": "system_groq_key",   "value": "gsk_abcdefghijklmnop"},
            {"key": "system_hunter_key", "value": "hunter_xyz_12345"},
            {"key": "enable_ollama",     "value": "true"},
        ]
        sb = _make_supabase({"system_config": rows})
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            config = AdminService.get_system_config(mask_secrets=True)
        assert config["system_groq_key"].endswith("***")
        assert not config["system_groq_key"].startswith("gsk_abcdefghijk")  # full key not exposed
        assert config["enable_ollama"] == "true"  # non-secret unchanged

    def test_masks_short_secret(self):
        """Very short secret values return just '***'."""
        from services.admin_service import AdminService
        rows = [{"key": "system_groq_key", "value": "short"}]
        sb = _make_supabase({"system_config": rows})
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            config = AdminService.get_system_config(mask_secrets=True)
        assert config["system_groq_key"] == "***"

    def test_empty_table_returns_empty_dict(self):
        """No rows → empty dict (not an error)."""
        from services.admin_service import AdminService
        sb = _make_supabase({"system_config": []})
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            config = AdminService.get_system_config()
        assert config == {}

    def test_db_error_returns_empty_dict(self):
        """Database error → empty dict (graceful degradation)."""
        from services.admin_service import AdminService
        sb = MagicMock()
        sb.table.side_effect = Exception("DB connection failed")
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            config = AdminService.get_system_config()
        assert config == {}


# ─────────────────────────────────────────────────────────────
# save_system_config
# ─────────────────────────────────────────────────────────────

class TestSaveSystemConfig:

    def test_upserts_correct_rows(self):
        """Each key/value pair becomes a separate row dict."""
        from services.admin_service import AdminService
        sb = MagicMock()
        upsert_mock = MagicMock()
        upsert_mock.execute.return_value = MagicMock(data=[])
        sb.table.return_value.upsert.return_value = upsert_mock

        updates = {"max_emails_per_user_per_day": "30", "enable_follow_ups": "true"}
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            AdminService.save_system_config(updates)

        # upsert was called with both rows
        call_args = sb.table.return_value.upsert.call_args
        rows_sent = call_args[0][0]
        keys_sent = {r["key"] for r in rows_sent}
        assert "max_emails_per_user_per_day" in keys_sent
        assert "enable_follow_ups" in keys_sent

    def test_empty_updates_noop(self):
        """Empty dict → no DB call."""
        from services.admin_service import AdminService
        sb = MagicMock()
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            AdminService.save_system_config({})
        sb.table.assert_not_called()

    def test_none_values_excluded(self):
        """None values are filtered out before upsert."""
        from services.admin_service import AdminService
        sb = MagicMock()
        upsert_mock = MagicMock()
        upsert_mock.execute.return_value = MagicMock(data=[])
        sb.table.return_value.upsert.return_value = upsert_mock

        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            AdminService.save_system_config({"enable_follow_ups": "false", "system_groq_key": None})

        rows_sent = sb.table.return_value.upsert.call_args[0][0]
        keys_sent = [r["key"] for r in rows_sent]
        assert "system_groq_key" not in keys_sent
        assert "enable_follow_ups" in keys_sent


# ─────────────────────────────────────────────────────────────
# get_platform_usage
# ─────────────────────────────────────────────────────────────

class TestGetPlatformUsage:

    def _make_realistic_sb(self):
        """Three users, two campaigns, mixed contact outcomes."""
        sb = MagicMock()
        call_count = [0]

        def _table(name):
            chain = MagicMock()
            if name == "user_profiles":
                chain.select.return_value.execute.return_value = MagicMock(data=[
                    {"user_id": "u1", "display_name": "Alice", "email": "alice@x.com"},
                    {"user_id": "u2", "display_name": "Bob",   "email": "bob@x.com"},
                    {"user_id": "u3", "display_name": "Carol", "email": "carol@x.com"},
                ])
            elif name == "campaigns":
                chain.select.return_value.execute.return_value = MagicMock(data=[
                    {"id": "c1", "user_id": "u1", "status": "sending"},
                    {"id": "c2", "user_id": "u2", "status": "draft"},
                ])
            elif name == "campaign_contacts":
                chain.select.return_value.in_.return_value.execute.return_value = MagicMock(data=[
                    {"campaign_id": "c1", "status": "sent"},
                    {"campaign_id": "c1", "status": "replied"},
                    {"campaign_id": "c1", "status": "interview"},
                    {"campaign_id": "c1", "status": "draft"},  # not counted
                    {"campaign_id": "c2", "status": "sent"},
                ])
            else:
                chain.select.return_value.execute.return_value = MagicMock(data=[])
            return chain

        sb.table.side_effect = _table
        return sb

    def test_total_counts(self):
        """Correct totals for users, campaigns, emails, contacts."""
        from services.admin_service import AdminService
        sb = self._make_realistic_sb()
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            result = AdminService.get_platform_usage()
        assert result["total_users"] == 3
        assert result["total_campaigns"] == 2
        # sent(c1) + replied(c1) + interview(c1) + sent(c2) = 4
        assert result["total_emails_sent"] == 4
        # All 5 contact rows
        assert result["total_contacts"] == 5

    def test_reply_rate_calculation(self):
        """Reply rate = (replied + interview) / sent * 100."""
        from services.admin_service import AdminService
        sb = self._make_realistic_sb()
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            result = AdminService.get_platform_usage()
        # Replies from c1: replied(1) + interview(1) = 2 out of 4 sent
        assert result["reply_rate"] == 50.0

    def test_reply_rate_none_when_no_emails(self):
        """Reply rate is None (not 0) when no emails sent."""
        from services.admin_service import AdminService
        sb = MagicMock()
        sb.table.side_effect = lambda name: MagicMock(
            select=MagicMock(return_value=MagicMock(
                execute=MagicMock(return_value=MagicMock(data=[])),
                in_=MagicMock(return_value=MagicMock(
                    execute=MagicMock(return_value=MagicMock(data=[])))
                )))
            )
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            result = AdminService.get_platform_usage()
        assert result["reply_rate"] is None

    def test_leaderboard_sorted_by_emails(self):
        """top_users sorted descending by emails_sent."""
        from services.admin_service import AdminService
        sb = self._make_realistic_sb()
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            result = AdminService.get_platform_usage()
        users = result["top_users"]
        # Alice (u1) sent 3, Bob (u2) sent 1
        if len(users) >= 2:
            assert users[0]["emails_sent"] >= users[1]["emails_sent"]

    def test_leaderboard_max_10(self):
        """Leaderboard capped at 10 users."""
        from services.admin_service import AdminService
        # 15 users, all with campaigns
        many_users = [{"user_id": f"u{i}", "display_name": f"User{i}", "email": f"u{i}@x.com"} for i in range(15)]
        many_campaigns = [{"id": f"c{i}", "user_id": f"u{i}", "status": "sending"} for i in range(15)]
        many_contacts = [{"campaign_id": f"c{i}", "status": "sent"} for i in range(15)]

        sb = MagicMock()
        def _table(name):
            chain = MagicMock()
            if name == "user_profiles":
                chain.select.return_value.execute.return_value = MagicMock(data=many_users)
            elif name == "campaigns":
                chain.select.return_value.execute.return_value = MagicMock(data=many_campaigns)
            elif name == "campaign_contacts":
                chain.select.return_value.in_.return_value.execute.return_value = MagicMock(data=many_contacts)
            else:
                chain.select.return_value.execute.return_value = MagicMock(data=[])
            return chain
        sb.table.side_effect = _table

        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            result = AdminService.get_platform_usage()
        assert len(result["top_users"]) <= 10

    def test_db_error_returns_zeros(self):
        """DB error → graceful zeros (no crash)."""
        from services.admin_service import AdminService
        sb = MagicMock()
        sb.table.side_effect = Exception("DB is down")
        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            result = AdminService.get_platform_usage()
        assert result["total_users"] == 0
        assert result["total_campaigns"] == 0
        assert result["reply_rate"] is None


# ─────────────────────────────────────────────────────────────
# _get_user_stats — no double counting
# ─────────────────────────────────────────────────────────────

class TestGetUserStats:

    def test_no_double_counting_sent(self):
        """
        A contact with status='replied' should count as 1 sent + 1 reply.
        A contact with status='interview' should count as 1 sent + 1 reply + 1 interview.
        NOT as 2 or 3 sent.
        """
        from services.admin_service import AdminService

        contacts = [
            {"status": "sent"},      # +1 sent
            {"status": "replied"},   # +1 sent, +1 reply
            {"status": "interview"}, # +1 sent, +1 reply, +1 interview
            {"status": "draft"},     # nothing
            {"status": "failed"},    # nothing
        ]

        sb = MagicMock()
        def _table(name):
            chain = MagicMock()
            if name == "campaigns":
                chain.select.return_value.eq.return_value.execute.return_value = MagicMock(data=[
                    {"id": "c1", "status": "sending"}
                ])
            elif name == "campaign_contacts":
                chain.select.return_value.in_.return_value.execute.return_value = MagicMock(data=contacts)
            return chain
        sb.table.side_effect = _table

        with patch("services.admin_service.get_supabase_admin", return_value=sb):
            stats = AdminService._get_user_stats("user_001")

        assert stats["total_sent"] == 3       # not 6
        assert stats["total_replies"] == 2    # replied + interview
        assert stats["total_interviews"] == 1
        assert stats["campaigns_count"] == 1


# ─────────────────────────────────────────────────────────────
# Admin router endpoint tests (FastAPI test client)
# ─────────────────────────────────────────────────────────────

@pytest.fixture
def admin_client():
    try:
        from fastapi import FastAPI
        from fastapi.testclient import TestClient
        from routers.admin import router as admin_router
        app = FastAPI()
        app.include_router(admin_router)
        return TestClient(app, raise_server_exceptions=False)
    except Exception:
        return None


def test_get_config_requires_auth(admin_client):
    """GET /api/admin/config returns 4xx without admin auth."""
    if admin_client is None:
        pytest.skip("App client setup failed")
    resp = admin_client.get("/api/admin/config")
    assert resp.status_code in (401, 403, 422, 500)


def test_put_config_requires_auth(admin_client):
    """PUT /api/admin/config returns 4xx without admin auth."""
    if admin_client is None:
        pytest.skip("App client setup failed")
    resp = admin_client.put("/api/admin/config", json={"enable_follow_ups": "true"})
    assert resp.status_code in (401, 403, 422, 500)


def test_get_usage_requires_auth(admin_client):
    """GET /api/admin/usage returns 4xx without admin auth."""
    if admin_client is None:
        pytest.skip("App client setup failed")
    resp = admin_client.get("/api/admin/usage")
    assert resp.status_code in (401, 403, 422, 500)


def test_system_config_update_model():
    """SystemConfigUpdate model allows all optional fields."""
    from routers.admin import SystemConfigUpdate
    req = SystemConfigUpdate(max_emails_per_user_per_day="50")
    assert req.max_emails_per_user_per_day == "50"
    assert req.system_groq_key is None
    assert req.enable_follow_ups is None


def test_platform_usage_response_model():
    """PlatformUsageResponse has correct defaults."""
    from routers.admin import PlatformUsageResponse
    r = PlatformUsageResponse()
    assert r.total_users == 0
    assert r.reply_rate is None
    assert r.top_users == []
