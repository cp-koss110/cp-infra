"""
Smoke tests for the deployed API service.

Run against staging (ALB_URL must be set):
    ALB_URL=http://my-alb-dns.us-east-2.elb.amazonaws.com pytest tests/e2e/test_smoke.py -v

Tests are skipped when ALB_URL is not set.
"""

import os
import time
from datetime import datetime, timezone

import boto3
import pytest
import requests

AWS_REGION   = os.environ.get("AWS_REGION", "us-east-2")
E2E_ENV      = os.environ.get("E2E_ENV", "staging")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "exam-costa")


def _ssm_get(name: str, with_decryption: bool = False) -> str:
    try:
        ssm = boto3.client("ssm", region_name=AWS_REGION)
        return ssm.get_parameter(Name=name, WithDecryption=with_decryption)["Parameter"]["Value"]
    except Exception:
        return ""


ALB_URL   = (os.environ.get("ALB_URL") or _ssm_get(f"/{PROJECT_NAME}/{E2E_ENV}/outputs/alb_url")).rstrip("/")
API_TOKEN = os.environ.get("API_TOKEN") or _ssm_get(f"/{PROJECT_NAME}/{E2E_ENV}/api/token", with_decryption=True)
S3_BUCKET = os.environ.get("S3_BUCKET_NAME") or _ssm_get(f"/{PROJECT_NAME}/{E2E_ENV}/outputs/s3_bucket_name")

pytestmark = pytest.mark.skipif(
    not ALB_URL,
    reason="ALB_URL not set and SSM lookup failed — skipping smoke tests",
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
    """POST /message with wrong token must return 401."""
    r = requests.post(
        f"{ALB_URL}/message",
        json={
            "data": {
                "email_subject": "Smoke test",
                "email_sender": "smoke@test.com",
                "email_timestream": "1693561101",
                "email_content": "Smoke test content",
            },
            "token": "definitely-wrong-token",
        },
        timeout=10,
    )
    assert r.status_code == 401, f"Expected 401, got {r.status_code}: {r.text}"


def test_health_returns_service_name():
    """GET /healthz must include service=api in response."""
    r = requests.get(f"{ALB_URL}/healthz", timeout=10)
    assert r.status_code == 200
    body = r.json()
    assert body.get("service") == "api", f"Unexpected service field: {body}"


def test_message_end_to_end():
    """Send a valid message and verify the worker uploads it to S3 within 60s."""
    if not API_TOKEN:
        pytest.skip("API_TOKEN not set — skipping end-to-end write test")
    if not S3_BUCKET:
        pytest.skip("S3_BUCKET_NAME not set — skipping end-to-end write test")

    sent_at = datetime.now(timezone.utc)
    date_prefix = sent_at.strftime("%Y/%m/%d")
    s3_prefix = f"messages/{date_prefix}/"

    # Send a real message with the valid token
    r = requests.post(
        f"{ALB_URL}/message",
        json={
            "data": {
                "email_subject": "E2E smoke test",
                "email_sender": "smoke@test.com",
                "email_timestream": str(int(sent_at.timestamp())),
                "email_content": f"E2E test sent at {sent_at.isoformat()}",
            },
            "token": API_TOKEN,
        },
        timeout=10,
    )
    assert r.status_code == 200, f"Expected 200, got {r.status_code}: {r.text}"

    # Poll S3 for up to 60s for a new object that appeared after we sent the message
    s3 = boto3.client("s3", region_name=AWS_REGION)
    deadline = time.time() + 60
    found_key = None
    while time.time() < deadline:
        resp = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix=s3_prefix)
        for obj in resp.get("Contents", []):
            if obj["LastModified"].replace(tzinfo=timezone.utc) >= sent_at:
                found_key = obj["Key"]
                break
        if found_key:
            break
        time.sleep(5)

    assert found_key, (
        f"No S3 object found under s3://{S3_BUCKET}/{s3_prefix} within 60s — "
        "worker may not be running or SQS delivery is delayed"
    )
