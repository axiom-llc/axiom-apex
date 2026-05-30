"""Smoke tests for the Maverick Logistics Operations API
(logistics-dashboard/operations_api.py).

The app uses a hardcoded SQLite file 'maverick_operational_data.db'.
We monkeypatch the module's DATABASE_NAME to ':memory:' and seed
a minimal schema so tests run without the real database file.

No file I/O, no network calls required.
"""
from __future__ import annotations
import os
import sys
import sqlite3
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "logistics-dashboard"))


@pytest.fixture(scope="module")
def client(tmp_path_factory):
    import operations_api as api

    # Redirect to a temp file-based DB (can't use :memory: across connections)
    db_path = str(tmp_path_factory.mktemp("db") / "test.db")
    api.DATABASE_NAME = db_path
    _seed_db(db_path)

    api.app.config["TESTING"] = True
    return api.app.test_client()


def _seed_db(path: str) -> None:
    """Create minimal schema and insert one row per table."""
    conn = sqlite3.connect(path)
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS daily_shipments (
            shipment_id       TEXT PRIMARY KEY,
            delivery_status   TEXT,
            on_time_status_calculated TEXT,
            fuel_efficiency_mpg REAL,
            shipment_value_usd  REAL,
            partner_contract  TEXT
        );

        CREATE TABLE IF NOT EXISTS partner_tasks_status (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            partner_contract  TEXT,
            simulated_service_health TEXT
        );

        INSERT INTO daily_shipments VALUES
            ('S001', 'Delivered',   'On-Time',  18.5, 1500.00, 'Amazon-Prime'),
            ('S002', 'In-Transit',  'Delayed',  16.2,  800.00, 'Amazon-Prime'),
            ('S003', 'Delivered',   'On-Time',  20.1, 2200.00, 'Hertz-Local');

        INSERT INTO partner_tasks_status (partner_contract, simulated_service_health) VALUES
            ('Amazon-Prime', 'OK'),
            ('Amazon-Prime', 'OK'),
            ('Amazon-Prime', 'Action Required');
    """)
    conn.commit()
    conn.close()


# ── Daily summary ──────────────────────────────────────────────────────────

class TestDailySummary:
    def test_returns_200(self, client):
        r = client.get("/api/logistics/daily_summary")
        assert r.status_code == 200

    def test_response_is_json(self, client):
        r = client.get("/api/logistics/daily_summary")
        assert r.content_type == "application/json"

    def test_required_keys_present(self, client):
        data = client.get("/api/logistics/daily_summary").get_json()
        for key in ("total_shipments_logged", "shipments_in_transit",
                    "delivered_shipments", "on_time_delivery_percent"):
            assert key in data, f"Missing key: {key}"

    def test_on_time_percent_is_numeric(self, client):
        data = client.get("/api/logistics/daily_summary").get_json()
        assert isinstance(data["on_time_delivery_percent"], (int, float))

    def test_counts_match_seeded_data(self, client):
        data = client.get("/api/logistics/daily_summary").get_json()
        assert data["total_shipments_logged"] == 3
        assert data["delivered_shipments"] == 2
        assert data["shipments_in_transit"] == 1


# ── Partner performance ────────────────────────────────────────────────────

class TestPartnerStatus:
    def test_known_partner_returns_200(self, client):
        r = client.get("/api/partner_performance/status?partner_contract=Amazon-Prime")
        assert r.status_code == 200

    def test_response_shape(self, client):
        data = client.get(
            "/api/partner_performance/status?partner_contract=Amazon-Prime"
        ).get_json()
        assert "shipment_metrics" in data
        assert "partner_service_health_summary" in data
        assert "partner_contract" in data

    def test_correct_partner_echoed(self, client):
        data = client.get(
            "/api/partner_performance/status?partner_contract=Amazon-Prime"
        ).get_json()
        assert data["partner_contract"] == "Amazon-Prime"

    def test_unknown_partner_returns_404(self, client):
        r = client.get(
            "/api/partner_performance/status?partner_contract=NonExistentCo"
        )
        assert r.status_code == 404

    def test_default_partner_param(self, client):
        # No query param — should default to Amazon-Prime per the route definition
        r = client.get("/api/partner_performance/status")
        assert r.status_code == 200

    def test_service_health_keys_present(self, client):
        data = client.get(
            "/api/partner_performance/status?partner_contract=Amazon-Prime"
        ).get_json()
        health = data["partner_service_health_summary"]
        assert "OK" in health
        assert "Action Required" in health
