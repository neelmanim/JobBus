from __future__ import annotations
import pytest
from unittest.mock import patch, MagicMock, AsyncMock
from starlette.testclient import TestClient


@pytest.fixture(scope="module")
def app():
    with patch("database.get_supabase_admin"), \
         patch("config.get_settings") as mock_cfg:
        mock_cfg.return_value.environment = "test"
        mock_cfg.return_value.frontend_url = ""
        from main import create_app
        return create_app()


@pytest.fixture
def client(app):
    return TestClient(app)



class TestListContacts:
    def test_list_all_contacts(self, mock_current_user, mock_supabase):
        mock_supabase.return_value.table.return_value.select.return_value \
            .eq.return_value.order.return_value.execute.return_value.data = [
            {
                "id": "c1", "first_name": "Jane", "last_name": "Doe",
                "email": "jane@stripe.com", "title": "EM", "company": "Stripe",
                "persona_type": "hiring_manager", "source": "hunter",
                "confidence_score": 85.0, "linkedin_url": None, "opportunity_id": None,
            }
        ]
        client = TestClient(_make_app())
        resp = client.get("/api/contacts/", headers=_auth_headers())
        assert resp.status_code == 200
        assert len(resp.json()) == 1


class TestCreateContact:
    def test_create_valid_contact(self, mock_current_user, mock_supabase):
        db = mock_supabase.return_value.table.return_value
        # dedup check returns empty
        db.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
        # insert returns contact
        db.insert.return_value.execute.return_value.data = [{
            "id": "c1", "first_name": "Jane", "last_name": "Doe",
            "email": "jane@stripe.com", "title": "EM", "company": "Stripe",
            "persona_type": "hiring_manager", "source": "manual",
            "confidence_score": None, "linkedin_url": None, "opportunity_id": None,
        }]
        client = TestClient(_make_app())
        resp = client.post("/api/contacts/", json={
            "first_name": "Jane", "last_name": "Doe",
            "email": "jane@stripe.com", "title": "Engineering Manager", "company": "Stripe"
        }, headers=_auth_headers())
        assert resp.status_code == 201

    def test_rejects_invalid_email(self, mock_current_user, mock_supabase):
        client = TestClient(_make_app())
        resp = client.post("/api/contacts/", json={
            "first_name": "Jane", "last_name": "Doe",
            "email": "not-an-email", "title": "EM", "company": "Stripe"
        }, headers=_auth_headers())
        assert resp.status_code == 422

    def test_rejects_duplicate_email(self, mock_current_user, mock_supabase):
        db = mock_supabase.return_value.table.return_value
        db.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = [
            {"id": "existing"}
        ]
        client = TestClient(_make_app())
        resp = client.post("/api/contacts/", json={
            "first_name": "Jane", "last_name": "Doe",
            "email": "jane@stripe.com", "title": "EM", "company": "Stripe"
        }, headers=_auth_headers())
        assert resp.status_code == 409


class TestBulkCreateContacts:
    def test_bulk_deduplicates_within_batch(self, mock_current_user, mock_supabase):
        db = mock_supabase.return_value.table.return_value
        db.select.return_value.eq.return_value.execute.return_value.data = []
        db.insert.return_value.execute.return_value.data = [
            {"id": "c1", "first_name": "Jane", "last_name": "Doe",
             "email": "jane@stripe.com", "title": "EM", "company": "Stripe",
             "persona_type": "other", "source": "manual",
             "confidence_score": None, "linkedin_url": None, "opportunity_id": None}
        ]
        client = TestClient(_make_app())
        # Send duplicate in same batch
        resp = client.post("/api/contacts/bulk", json=[
            {"first_name": "Jane", "last_name": "Doe", "email": "jane@stripe.com", "title": "EM", "company": "S"},
            {"first_name": "Jane", "last_name": "Doe", "email": "jane@stripe.com", "title": "EM", "company": "S"},
        ], headers=_auth_headers())
        assert resp.status_code == 201
        assert len(resp.json()) == 1  # deduped to 1

    def test_rejects_empty_list(self, mock_current_user, mock_supabase):
        client = TestClient(_make_app())
        resp = client.post("/api/contacts/bulk", json=[], headers=_auth_headers())
        assert resp.status_code == 422


class TestDeleteContact:
    def test_delete_existing(self, mock_current_user, mock_supabase):
        db = mock_supabase.return_value.table.return_value
        db.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = [{"id": "c1"}]
        db.delete.return_value.eq.return_value.execute.return_value = None
        client = TestClient(_make_app())
        resp = client.delete("/api/contacts/c1", headers=_auth_headers())
        assert resp.status_code == 200

    def test_delete_not_found(self, mock_current_user, mock_supabase):
        db = mock_supabase.return_value.table.return_value
        db.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
        client = TestClient(_make_app())
        resp = client.delete("/api/contacts/nonexistent", headers=_auth_headers())
        assert resp.status_code == 404


class TestFindContact:
    @pytest.mark.asyncio
    async def test_find_uses_waterfall(self, mock_current_user, mock_supabase):
        from providers.search.base import ContactResult
        mock_results = [
            ContactResult("Jane", "Doe", "jane@stripe.com", "EM", "Stripe",
                         source="hunter", persona_type="hiring_manager")
        ]
        db = mock_supabase.return_value.table.return_value
        db.select.return_value.eq.return_value.execute.return_value.data = []
        db.insert.return_value.execute.return_value.data = []
        db.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = []

        with patch("routers.contacts.waterfall_search",
                   AsyncMock(return_value=(mock_results, "hunter"))):
            client = TestClient(_make_app())
            resp = client.post("/api/contacts/find", json={
                "opportunity_id": "opp1",
                "company": "Stripe",
                "domain": "stripe.com",
            }, headers=_auth_headers())
            assert resp.status_code == 200
            body = resp.json()
            assert body["provider_used"] == "hunter"
            assert body["total_found"] == 1
