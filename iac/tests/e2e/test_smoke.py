"""
Smoke tests for the deployed API service.

Run against staging (ALB_URL must be set):
    ALB_URL=http://my-alb-dns.us-east-2.elb.amazonaws.com pytest tests/e2e/test_smoke.py -v

Tests are skipped when ALB_URL is not set.
"""

import os

import pytest
import requests

ALB_URL = os.environ.get("ALB_URL", "").rstrip("/")

pytestmark = pytest.mark.skipif(
    not ALB_URL,
    reason="ALB_URL not set — skipping smoke tests",
)


def test_health():
    """GET /healthz must return 200 with status=healthy."""
    r = requests.get(f"{ALB_URL}/healthz", timeout=10)
    assert r.status_code == 200, f"Expected 200, got {r.status_code}: {r.text}"
    body = r.json()
    assert body["status"] == "healthy", f"Unexpected status: {body}"


def test_message_requires_auth():
    """POST /message without Authorization header must be rejected."""
    r = requests.post(
        f"{ALB_URL}/message",
        json={},
        timeout=10,
    )
    assert r.status_code in (401, 403, 422), (
        f"Expected 401/403/422, got {r.status_code}: {r.text}"
    )


def test_message_rejects_invalid_token():
    """POST /message with wrong Bearer token must return 401."""
    r = requests.post(
        f"{ALB_URL}/message",
        json={
            "name": "Smoke Test",
            "category": "smoke",
            "value": 1.0,
            "description": "Smoke test message",
        },
        headers={"Authorization": "Bearer definitely-wrong-token"},
        timeout=10,
    )
    assert r.status_code == 401, f"Expected 401, got {r.status_code}: {r.text}"


def test_health_returns_service_name():
    """GET /healthz must include service=api in response."""
    r = requests.get(f"{ALB_URL}/healthz", timeout=10)
    assert r.status_code == 200
    body = r.json()
    assert body.get("service") == "api", f"Unexpected service field: {body}"
