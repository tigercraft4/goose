import importlib
import uuid

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.auth import hash_api_token, token_prefix
from tests.conftest import requires_docker


@pytest.fixture
def client(clean_db, tmp_path, monkeypatch):
    monkeypatch.setenv("GOOSE_API_KEY", "secret")
    monkeypatch.setenv("GOOSE_DB_DSN", clean_db)
    monkeypatch.setenv("GOOSE_RAW_ROOT", str(tmp_path))
    import app.main as main
    importlib.reload(main)
    return TestClient(main.app, headers={"Authorization": "Bearer secret"})


def _create_token(dsn, name, email, raw_token):
    user_id = uuid.uuid4()
    with psycopg.connect(dsn) as conn:
        conn.execute(
            "INSERT INTO users (id, name, email) VALUES (%s, %s, %s)",
            (user_id, name, email),
        )
        conn.execute(
            """INSERT INTO api_tokens (id, user_id, token_hash, token_prefix)
               VALUES (%s, %s, %s, %s)""",
            (uuid.uuid4(), user_id, hash_api_token(raw_token), token_prefix(raw_token)),
        )
        conn.commit()
    return user_id


def _claim(client, token, device_id):
    response = client.post(
        "/v1/devices/claim",
        json={"device_id": device_id, "name": "Test WHOOP", "device_type": "whoop"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200, response.text


@requires_docker
def test_user_can_rename_own_device_and_list_display_name(client, clean_db):
    _create_token(clean_db, "Adam", "adam@example.com", "goose_adam")
    _claim(client, "goose_adam", "adam-device")

    response = client.patch(
        "/v1/devices/adam-device",
        json={"display_name": "  Ádám WHOOP 5  "},
        headers={"Authorization": "Bearer goose_adam"},
    )
    assert response.status_code == 200
    assert response.json() == {
        "device_id": "adam-device",
        "display_name": "Ádám WHOOP 5",
    }

    devices = client.get(
        "/v1/devices",
        headers={"Authorization": "Bearer goose_adam"},
    ).json()
    assert len(devices) == 1
    assert devices[0]["device_id"] == "adam-device"
    assert devices[0]["display_name"] == "Ádám WHOOP 5"
    assert devices[0]["nickname"] is None
    assert devices[0]["created_at"] is not None
    assert devices[0]["last_seen"] is not None


@requires_docker
def test_user_cannot_rename_another_users_device(client, clean_db):
    _create_token(clean_db, "Adam", "adam@example.com", "goose_adam")
    _create_token(clean_db, "Beth", "beth@example.com", "goose_beth")
    _claim(client, "goose_adam", "adam-device")

    response = client.patch(
        "/v1/devices/adam-device",
        json={"display_name": "Beth's device"},
        headers={"Authorization": "Bearer goose_beth"},
    )
    assert response.status_code == 403
    assert client.get(
        "/v1/devices",
        headers={"Authorization": "Bearer goose_beth"},
    ).json() == []


@requires_docker
def test_admin_can_rename_any_owned_device_and_list_owner(client, clean_db):
    user_id = _create_token(clean_db, "Adam", "adam@example.com", "goose_adam")
    _claim(client, "goose_adam", "adam-device")

    response = client.patch(
        "/v1/devices/adam-device",
        json={"display_name": "Adam WHOOP"},
    )
    assert response.status_code == 200

    devices = client.get("/v1/devices").json()
    assert devices == [{
        "device_id": "adam-device",
        "display_name": "Adam WHOOP",
        "owner_user_id": str(user_id),
        "owner_name": "Adam",
        "owner_email": "adam@example.com",
        "created_at": devices[0]["created_at"],
        "last_seen": devices[0]["last_seen"],
    }]


@requires_docker
def test_existing_null_display_name_is_returned(client, clean_db):
    _create_token(clean_db, "Adam", "adam@example.com", "goose_adam")
    _claim(client, "goose_adam", "adam-device")

    devices = client.get(
        "/v1/devices",
        headers={"Authorization": "Bearer goose_adam"},
    ).json()
    assert devices[0]["display_name"] is None


@pytest.mark.parametrize("display_name", ["", "   ", "x" * 81])
@requires_docker
def test_invalid_display_name_is_rejected(client, clean_db, display_name):
    _create_token(clean_db, "Adam", "adam@example.com", "goose_adam")
    _claim(client, "goose_adam", "adam-device")

    response = client.patch(
        "/v1/devices/adam-device",
        json={"display_name": display_name},
        headers={"Authorization": "Bearer goose_adam"},
    )
    assert response.status_code == 422
