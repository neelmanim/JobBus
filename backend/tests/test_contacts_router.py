"""
JobBus — Tests: Contacts Router.

Tests contact import, deletion, and waterfall search.
"""
from __future__ import annotations
import pytest
from unittest.mock import patch, AsyncMock, MagicMock
from fastapi.testclient import TestClient

from tests.conftest import make_client, auth_headers


class TestImportContacts:
    def test_accepts_valid_list(self):
        with patch("routers.contacts.get_supabase_admin") as mock_db:
            table = mock_db.return_value.table.return_value
            # deduplicate check (existing emails)
            table.select.return_value.eq.return_value.execute.return_value.data = []
            # insert result
            table.insert.return_value.execute.return_value.data = [
                {
                    "id": "c1", "first_name": "Jane", "last_name": "Doe",
                    "email": "jane@stripe.com", "title": "EM", "company": "Stripe",
                    "persona_type": "hiring_manager", "source": "manual",
                    "confidence_score": None, "linkedin_url": None, "opportunity_id": "opp1",
                }
            ]
            with make_client() as client:
                resp = client.post("/api/contacts/bulk",
                    json=[
                        {
                            "first_name": "Jane", "last_name": "Doe",
                            "email": "jane@stripe.com", "title": "EM",
                            "company": "Stripe", "persona_type": "hiring_manager",
                            "opportunity_id": "opp1",
                        }
                    ],
                    headers=auth_headers())
            assert resp.status_code == 201

    def test_rejects_empty_list(self):
        with make_client() as client:
            resp = client.post("/api/contacts/bulk",
                json=[],
                headers=auth_headers())
        assert resp.status_code == 422

    def test_rejects_missing_required_field(self):
        # email is a required field — omitting it should 422
        with make_client() as client:
            resp = client.post("/api/contacts/bulk",
                json=[{"first_name": "Jane"}],
                headers=auth_headers())
        assert resp.status_code == 422


class TestDeleteContact:
    def test_delete_existing(self):
        with patch("routers.contacts.get_supabase_admin") as mock_db:
            table = mock_db.return_value.table.return_value
            # contact exists: .select().eq("id", ...).eq("user_id", ...).execute()
            table.select.return_value.eq.return_value.eq.return_value \
                .execute.return_value.data = [{"id": "c1"}]
            table.delete.return_value.eq.return_value.execute.return_value = None
            with make_client() as client:
                resp = client.delete("/api/contacts/c1", headers=auth_headers())
            assert resp.status_code in (200, 204)

    def test_delete_not_found(self):
        with patch("routers.contacts.get_supabase_admin") as mock_db:
            table = mock_db.return_value.table.return_value
            # contact NOT found: returns empty list
            table.select.return_value.eq.return_value.eq.return_value \
                .execute.return_value.data = []
            with make_client() as client:
                resp = client.delete("/api/contacts/missing", headers=auth_headers())
            assert resp.status_code == 404


class TestFindContact:
    @pytest.mark.asyncio
    async def test_find_uses_waterfall(self):
        from providers.search.base import ContactResult
        mock_results = [
            ContactResult("Jane", "Doe", "jane@stripe.com", "EM", "Stripe",
                         source="hunter", persona_type="hiring_manager")
        ]
        with patch("routers.contacts.get_supabase_admin") as mock_db, \
             patch("routers.contacts.waterfall_search",
                   AsyncMock(return_value=(mock_results, "hunter"))):
            db = mock_db.return_value.table.return_value
            # existing emails query
            db.select.return_value.eq.return_value.execute.return_value.data = []
            # insert result
            db.insert.return_value.execute.return_value.data = []
            # all_contacts_result for this opportunity
            db.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = [
                {
                    "id": "c1", "first_name": "Jane", "last_name": "Doe",
                    "email": "jane@stripe.com", "title": "EM", "company": "Stripe",
                    "persona_type": "hiring_manager", "source": "hunter",
                    "confidence_score": None, "linkedin_url": None, "opportunity_id": "opp1",
                }
            ]

            with make_client() as client:
                resp = client.post("/api/contacts/find",
                    json={
                        "opportunity_id": "opp1",
                        "company": "Stripe",
                        "domain": "stripe.com",
                        "limit": 1,
                    },
                    headers=auth_headers())
            assert resp.status_code == 200
            body = resp.json()
            assert body["provider_used"] == "hunter"
            assert body["total_found"] == 1
