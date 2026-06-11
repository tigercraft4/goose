import importlib
import os
import subprocess
import sys
import uuid
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.auth import hash_api_token, token_prefix
from tests.conftest import requires_docker


EMPTY_BATCH = {
    "device": {"id": "device-a"},
    "streams": {},
}


@pytest.fixture
def client(clean_db, tmp_path, monkeypatch):
    monkeypatch.setenv("GOOSE_API_KEY", "secret")
    monkeypatch.setenv("GOOSE_DB_DSN", clean_db)
    monkeypatch.setenv("GOOSE_RAW_ROOT", str(tmp_path))
    import app.main as main
    importlib.reload(main)
    return TestClient(main.app, headers={"Authorization": "Bearer secret"})


def _create_token(dsn, email, raw_token, *, revoked=False):
    user_id = uuid.uuid4()
    with psycopg.connect(dsn) as conn:
        conn.execute(
            "INSERT INTO users (id, name, email) VALUES (%s, %s, %s)",
            (user_id, email.split("@", 1)[0], email),
        )
        conn.execute(
            """INSERT INTO api_tokens
               (id, user_id, token_hash, token_prefix, revoked_at)
               VALUES (%s, %s, %s, %s, CASE WHEN %s THEN now() ELSE NULL END)""",
            (
                uuid.uuid4(),
                user_id,
                hash_api_token(raw_token),
                token_prefix(raw_token),
                revoked,
            ),
        )
        conn.commit()
    return user_id


@requires_docker
def test_global_api_key_still_works(client):
    response = client.post("/v1/ingest-decoded", json=EMPTY_BATCH)
    assert response.status_code == 200


@requires_docker
def test_invalid_token_is_rejected(client):
    response = client.post(
        "/v1/ingest-decoded",
        json=EMPTY_BATCH,
        headers={"Authorization": "Bearer invalid"},
    )
    assert response.status_code == 401


@requires_docker
def test_revoked_token_is_rejected(client, clean_db):
    _create_token(clean_db, "revoked@example.com", "goose_revoked", revoked=True)
    response = client.post(
        "/v1/ingest-decoded",
        json=EMPTY_BATCH,
        headers={"Authorization": "Bearer goose_revoked"},
    )
    assert response.status_code == 401


def _claim(client, token, device_id="device-a"):
    return client.post(
        "/v1/devices/claim",
        json={"device_id": device_id, "name": "Test WHOOP", "device_type": "whoop"},
        headers={"Authorization": f"Bearer {token}"},
    )


@requires_docker
def test_user_must_claim_before_upload_and_can_reuse_device(client, clean_db):
    user_id = _create_token(clean_db, "one@example.com", "goose_one")
    headers = {"Authorization": "Bearer goose_one"}

    before_claim = client.post("/v1/ingest-decoded", json=EMPTY_BATCH, headers=headers)
    first_claim = _claim(client, "goose_one")
    second_claim = _claim(client, "goose_one")
    upload = client.post("/v1/ingest-decoded", json=EMPTY_BATCH, headers=headers)

    assert before_claim.status_code == 403
    assert first_claim.status_code == 200
    assert second_claim.status_code == 200
    assert upload.status_code == 200
    with psycopg.connect(clean_db) as conn:
        owners = conn.execute(
            "SELECT user_id FROM device_owners WHERE device_id = 'device-a'"
        ).fetchall()
    assert owners == [(user_id,)]


@requires_docker
def test_different_user_cannot_upload_owned_device(client, clean_db):
    _create_token(clean_db, "one@example.com", "goose_one")
    _create_token(clean_db, "two@example.com", "goose_two")
    first = _claim(client, "goose_one")
    second = client.post(
        "/v1/ingest-decoded",
        json=EMPTY_BATCH,
        headers={"Authorization": "Bearer goose_two"},
    )
    assert first.status_code == 200
    assert second.status_code == 403


@requires_docker
def test_admin_can_upload_device_owned_by_user(client, clean_db):
    _create_token(clean_db, "owner@example.com", "goose_owner")
    claimed = _claim(client, "goose_owner")
    admin = client.post("/v1/ingest-decoded", json=EMPTY_BATCH)
    assert claimed.status_code == 200
    assert admin.status_code == 200


@requires_docker
def test_user_raw_frame_upload_uses_same_device_ownership(client, clean_db):
    _create_token(clean_db, "frames@example.com", "goose_frames")
    assert _claim(client, "goose_frames", "frame-device").status_code == 200
    body = {
        "device": {"id": "frame-device"},
        "frames": [{
            "captured_at_unix": 1_700_000_000.5,
            "frame_hex": "aabb",
            "source": "ios.corebluetooth.notification",
        }],
    }
    response = client.post(
        "/v1/ingest-frames",
        json=body,
        headers={"Authorization": "Bearer goose_frames"},
    )
    assert response.status_code == 200
    assert response.json() == {"inserted": 1}


@requires_docker
def test_create_user_token_cli_stores_only_hash(clean_db):
    script = Path(__file__).resolve().parents[2] / "scripts" / "create_user_token.py"
    env = os.environ.copy()
    env["GOOSE_DB_DSN"] = clean_db
    result = subprocess.run(
        [sys.executable, str(script), "--name", "Adam", "--email", "adam@example.com"],
        check=True,
        capture_output=True,
        text=True,
        env=env,
    )
    token_line = next(line for line in result.stdout.splitlines() if line.startswith("API token: "))
    raw_token = token_line.removeprefix("API token: ")
    assert raw_token.startswith("goose_")

    with psycopg.connect(clean_db) as conn:
        stored = conn.execute(
            """SELECT t.token_hash, t.token_prefix, u.email
               FROM api_tokens t JOIN users u ON u.id = t.user_id"""
        ).fetchone()
    assert stored == (hash_api_token(raw_token), token_prefix(raw_token), "adam@example.com")
    assert raw_token not in stored


@requires_docker
def test_signup_login_claim_metrics_and_unclaim_transfer(client, clean_db):
    signup = client.post(
        "/v1/auth/signup",
        json={"name": "Adam", "email": "adam@example.com", "password": "password123"},
    )
    assert signup.status_code == 201
    adam_token = signup.json()["api_token"]
    adam_headers = {"Authorization": f"Bearer {adam_token}"}

    login = client.post(
        "/v1/auth/login",
        json={"email": "adam@example.com", "password": "password123"},
    )
    assert login.status_code == 200
    assert login.json()["user"]["id"] == signup.json()["user"]["id"]

    _create_token(clean_db, "beth@example.com", "goose_beth")
    beth_headers = {"Authorization": "Bearer goose_beth"}

    claim = client.post(
        "/v1/devices/claim",
        json={"device_id": "WHOOP-TEST-001", "name": "Adam's WHOOP", "device_type": "whoop"},
        headers=adam_headers,
    )
    assert claim.status_code == 200
    assert client.post(
        "/v1/devices/claim",
        json={"device_id": "WHOOP-TEST-001", "name": "Beth's WHOOP", "device_type": "whoop"},
        headers=beth_headers,
    ).status_code == 409

    inserted = client.post(
        "/v1/metrics",
        json={"device_id": "WHOOP-TEST-001", "heart_rate": 72, "battery": 88},
        headers=adam_headers,
    )
    assert inserted.status_code == 201
    assert client.post(
        "/v1/metrics",
        json={"device_id": "WHOOP-TEST-001", "heart_rate": 80},
        headers=beth_headers,
    ).status_code == 403
    assert len(client.get("/v1/metrics", headers=adam_headers).json()) == 1
    assert client.get("/v1/metrics", headers=beth_headers).json() == []

    removed = client.delete("/v1/devices/WHOOP-TEST-001/claim", headers=adam_headers)
    assert removed.status_code == 200
    assert _claim(client, "goose_beth", "WHOOP-TEST-001").status_code == 200
    assert client.get("/v1/metrics", headers=beth_headers).json() == []
    assert client.get("/v1/metrics", headers=adam_headers).json() == [{
        **inserted.json(),
        "recorded_at": inserted.json()["recorded_at"],
    }]
