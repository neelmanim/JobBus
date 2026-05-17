"""
JobBus — Tests: Campaign Workflow.

Tests draft generation, approval, sandbox safety gate, send guard, outcomes.
"""
from __future__ import annotations
import pytest
from unittest.mock import patch, AsyncMock, MagicMock
from fastapi.testclient import TestClient

from tests.conftest import make_client, auth_headers


# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

def _db_mock_campaign(supabase_mock, sandbox_mode=True, status="draft"):
    """Helper to mock a campaign DB row.
    Router queries: .table("campaigns").select("*").eq("id", ...).eq("user_id", ...).single().execute()
    """
    campaign_data = {
        "id": "camp1", "user_id": "u1", "name": "Test Campaign",
        "opportunity_id": "opp1", "sandbox_mode": sandbox_mode,
        "status": status, "description": "Test outreach",
    }
    supabase_mock.return_value.table.return_value.select.return_value \
        .eq.return_value.eq.return_value.single.return_value.execute.return_value.data = campaign_data
    return campaign_data


# ─────────────────────────────────────────────────────────────
# Draft Generation
# ─────────────────────────────────────────────────────────────

class TestGenerateDrafts:
    def test_generates_drafts_for_contacts(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db, \
             patch("routers.campaigns.get_ai_provider") as mock_ai_factory:
            contact_row = {
                "id": "c1", "first_name": "Jane", "last_name": "Doe",
                "email": "jane@stripe.com", "title": "EM", "company": "Stripe",
                "persona_type": "hiring_manager", "opportunity_id": "opp1",
            }
            campaign_row = {
                "id": "camp1", "user_id": "u1", "name": "Test Campaign",
                "opportunity_id": "opp1", "sandbox_mode": True,
                "status": "draft", "description": "Test outreach",
            }
            profile_row = {"signature_name": "Neel", "signature_title": None,
                           "signature_linkedin": None, "custom_instructions": None}
            opp_row = {"id": "opp1", "role": "Backend Eng", "company": "Stripe"}

            # Updated call sequence after the campaign_contacts fix:
            # 1. Campaign lookup            (.single().execute())
            # 2. campaign_contacts join     (.eq(campaign_id).execute())  ← NEW
            # 3. contacts.in_() fetch       (.in_().execute())            ← NEW
            # 4. Approved drafts check      (.eq(status).execute())
            # 5. User profile               (.single().execute())
            # 6. Opportunity                (.single().execute())
            # 7. Draft insert               (.insert().execute())
            execute_results = [
                MagicMock(data=campaign_row),               # 1 campaign single
                MagicMock(data=[{"contact_id": "c1"}]),    # 2 campaign_contacts join
                MagicMock(data=[contact_row]),              # 3 contacts.in_() fetch
                MagicMock(data=[]),                         # 4 approved drafts (none)
                MagicMock(data=profile_row),                # 5 user profile single
                MagicMock(data=opp_row),                    # 6 opportunity single
            ]

            call_count = [0]
            def execute_side_effect():
                idx = call_count[0]
                call_count[0] += 1
                if idx < len(execute_results):
                    return execute_results[idx]
                return MagicMock(data=[])

            # Wire every .execute() variant to our counter
            table = mock_db.return_value.table.return_value
            table.select.return_value.eq.return_value.eq.return_value \
                .single.return_value.execute.side_effect = execute_side_effect
            table.select.return_value.eq.return_value.eq.return_value \
                .execute.side_effect = execute_side_effect
            table.select.return_value.eq.return_value.single.return_value \
                .execute.side_effect = execute_side_effect
            table.select.return_value.eq.return_value \
                .execute.side_effect = execute_side_effect
            table.select.return_value.in_.return_value \
                .execute.side_effect = execute_side_effect
            table.insert.return_value.execute.return_value.data = [{"id": "d1"}]

            from providers.ai.base import GenerationResult
            mock_ai = AsyncMock()
            mock_ai.provider_name = "groq"
            mock_ai.model = "llama-3.1-8b-instant"
            mock_ai.generate = AsyncMock(return_value=GenerationResult(
                text="Subject: Hi Jane\n\nHello! I admire Stripe's infrastructure...",
                model="llama-3.1-8b-instant",
                provider="groq",
            ))
            mock_ai_factory.return_value = mock_ai

            client = make_client()
            resp = client.post("/api/campaigns/camp1/generate-drafts",
                json={"regenerate": False, "tone": "professional"},
                headers=auth_headers())
            assert resp.status_code == 200
            data = resp.json()
            assert data["generated"] >= 1, f"Expected >=1 draft, got: {data}"

    def test_requires_contacts(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db, \
             patch("routers.campaigns.get_ai_provider"):
            _db_mock_campaign(mock_db)
            table = mock_db.return_value.table.return_value
            table.select.return_value.eq.return_value.eq.return_value \
                .execute.return_value.data = []
            table.select.return_value.eq.return_value.execute.return_value.data = []

            resp = make_client().post("/api/campaigns/camp1/generate-drafts",
                json={"regenerate": False},
                headers=auth_headers())
            assert resp.status_code == 400
            assert "No contacts" in resp.json()["detail"]


# ─────────────────────────────────────────────────────────────
# Draft Approval
# ─────────────────────────────────────────────────────────────

class TestDraftApproval:
    def test_approve_draft(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db:
            table = mock_db.return_value.table.return_value
            table.select.return_value.eq.return_value.eq.return_value.eq.return_value \
                .single.return_value.execute.return_value.data = {
                "id": "d1", "campaign_id": "camp1", "status": "draft",
                "subject": "Hi", "body": "Hello!"
            }
            table.update.return_value.eq.return_value.execute.return_value = None
            resp = make_client().post("/api/campaigns/camp1/drafts/approve",
                json={"draft_id": "d1", "action": "approve"},
                headers=auth_headers())
            assert resp.status_code == 200
            assert resp.json()["action"] == "approve"

    def test_reject_draft_with_reason(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db:
            table = mock_db.return_value.table.return_value
            table.select.return_value.eq.return_value.eq.return_value.eq.return_value \
                .single.return_value.execute.return_value.data = {
                "id": "d1", "campaign_id": "camp1", "status": "draft",
                "subject": "Hi", "body": "Hello!"
            }
            table.update.return_value.eq.return_value.execute.return_value = None
            resp = make_client().post("/api/campaigns/camp1/drafts/approve",
                json={"draft_id": "d1", "action": "reject", "rejection_reason": "Too generic"},
                headers=auth_headers())
            assert resp.status_code == 200
            assert resp.json()["action"] == "reject"

    def test_invalid_action(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db:
            table = mock_db.return_value.table.return_value
            table.select.return_value.eq.return_value.eq.return_value.eq.return_value \
                .single.return_value.execute.return_value.data = {
                "id": "d1", "campaign_id": "camp1", "status": "draft",
                "subject": "Hi", "body": "Hello!"
            }
            resp = make_client().post("/api/campaigns/camp1/drafts/approve",
                json={"draft_id": "d1", "action": "blast"},
                headers=auth_headers())
            assert resp.status_code == 422


# ─────────────────────────────────────────────────────────────
# Sandbox Safety Gate
# ─────────────────────────────────────────────────────────────

class TestSandboxSafetyGate:
    def test_blocks_when_sandbox_on(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db:
            _db_mock_campaign(mock_db, sandbox_mode=True)
            resp = make_client().post("/api/campaigns/camp1/send/start",
                json={"dry_run": False},
                headers=auth_headers())
            assert resp.status_code == 200
            body = resp.json()
            assert body["blocked"] is True
            assert "Sandbox" in body["reason"]

    def test_dry_run_returns_preflight(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db:
            _db_mock_campaign(mock_db, sandbox_mode=False)
            table = mock_db.return_value.table.return_value
            table.select.return_value.eq.return_value.eq.return_value \
                .execute.return_value.count = 3
            resp = make_client().post("/api/campaigns/camp1/send/start",
                json={"dry_run": True},
                headers=auth_headers())
            assert resp.status_code == 200
            assert resp.json()["dry_run"] is True

    def test_blocks_without_smtp(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db, \
             patch("routers.campaigns.get_credential_service") as mock_cred:
            _db_mock_campaign(mock_db, sandbox_mode=False)
            # Also mock the dry_run drafts count so we get past that gate
            mock_db.return_value.table.return_value.select.return_value \
                .eq.return_value.eq.return_value.execute.return_value.count = 3
            # SMTP creds raise
            mock_cred.return_value.get_decrypted.side_effect = Exception("No SMTP")
            with make_client() as client:
                resp = client.post("/api/campaigns/camp1/send/start",
                    json={"dry_run": False},
                    headers=auth_headers())
            assert resp.status_code == 400
            assert "SMTP" in resp.json()["detail"]


# ─────────────────────────────────────────────────────────────
# Pause / Resume / Stop
# ─────────────────────────────────────────────────────────────

class TestCampaignPauseResumeStop:
    def test_pause(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db:
            table = mock_db.return_value.table.return_value
            table.select.return_value.eq.return_value.eq.return_value \
                .single.return_value.execute.return_value.data = {"id": "camp1"}
            table.update.return_value.eq.return_value.execute.return_value = None
            resp = make_client().post("/api/campaigns/camp1/send/pause",
                headers=auth_headers())
            assert resp.status_code == 200
            assert resp.json()["status"] == "paused"

    def test_stop_also_cancels_drafts(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db:
            table = mock_db.return_value.table.return_value
            table.select.return_value.eq.return_value.eq.return_value \
                .single.return_value.execute.return_value.data = {"id": "camp1"}
            table.update.return_value.eq.return_value.execute.return_value = None
            table.update.return_value.eq.return_value.eq.return_value.execute.return_value = None
            resp = make_client().post("/api/campaigns/camp1/send/stop",
                headers=auth_headers())
            assert resp.status_code == 200
            assert resp.json()["status"] == "completed"


# ─────────────────────────────────────────────────────────────
# Outcomes
# ─────────────────────────────────────────────────────────────

class TestOutcomes:
    def test_record_valid_outcome(self):
        with patch("routers.campaigns.get_supabase_admin") as mock_db:
            table = mock_db.return_value.table.return_value
            table.update.return_value.eq.return_value.eq.return_value.execute.return_value = None
            resp = make_client().post("/api/campaigns/camp1/outcomes",
                json={"contact_id": "c1", "outcome": "replied"},
                headers=auth_headers())
            assert resp.status_code == 200
            assert resp.json()["outcome"] == "replied"

    def test_rejects_invalid_outcome(self):
        # "ghosted" is not in the valid set — endpoint raises 422
        # Must mock DB since the endpoint calls get_supabase_admin() before validation
        with patch("routers.campaigns.get_supabase_admin"):
            with make_client() as client:
                resp = client.post("/api/campaigns/camp1/outcomes",
                    json={"contact_id": "c1", "outcome": "ghosted"},
                    headers=auth_headers())
        assert resp.status_code == 422


# ─────────────────────────────────────────────────────────────
# Draft Quality Scorer (pure unit tests — no HTTP)
# ─────────────────────────────────────────────────────────────

class TestDraftQualityScorer:
    def test_score_penalizes_generic_phrases(self):
        from routers.campaigns import _score_draft
        score, issues = _score_draft(
            subject="I hope this finds you well",
            body="I hope this finds you well. I am writing to discuss synergy opportunities.",
            contact={"first_name": "Jane", "company": "Stripe"},
            profile={},
        )
        assert score < 80
        assert any("generic" in i["type"] for i in issues)

    def test_score_penalizes_too_long(self):
        from routers.campaigns import _score_draft
        body = "word " * 250
        score, issues = _score_draft("Subject", body, {}, {})
        assert any(i["type"] == "length" for i in issues)

    def test_score_high_for_good_email(self):
        from routers.campaigns import _score_draft
        score, issues = _score_draft(
            subject="Quick question about Stripe's infra team",
            body="Hi Jane, I saw Stripe's recent blog post on distributed systems. "
                 "I've spent the last 3 years building similar pipelines at scale. "
                 "Would you be open to a 15-min chat?",
            contact={"first_name": "Jane", "company": "Stripe"},
            profile={"signature_name": "Neel"},
        )
        assert score >= 70


# ─────────────────────────────────────────────────────────────
# Parse Email Output (pure unit tests — no HTTP)
# ─────────────────────────────────────────────────────────────

class TestParseEmailOutput:
    def test_parses_subject_and_body(self):
        from routers.campaigns import _parse_email_output
        text = "Subject: Quick question\n\nHi Jane, I noticed..."
        subject, body = _parse_email_output(text, {"company": "Stripe"}, {})
        assert subject == "Quick question"
        assert body.startswith("Hi Jane")

    def test_fallback_subject_when_missing(self):
        from routers.campaigns import _parse_email_output
        text = "Hi Jane, I noticed your team at Stripe..."
        subject, body = _parse_email_output(text, {"company": "Stripe"}, {})
        assert "Stripe" in subject
        assert "Hi Jane" in body
