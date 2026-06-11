"""FastAPI ingest service. Bearer-auth write endpoint + health check + read API +
the static datastore dashboard."""
import datetime as _dt
import logging
import os
import threading
import time
import uuid

import psycopg
from psycopg.errors import UniqueViolation
from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, field_validator

from . import db, ingest, read, store
from .analysis import daily
from .auth import (
    AuthContext,
    authorize_device,
    generate_api_token,
    hash_api_token,
    hash_password,
    require_admin_auth,
    require_auth,
    require_owned_device,
    token_prefix,
    verify_password,
)
from .config import load_config

_log = logging.getLogger("goose.ingest")

cfg = load_config()
db.bootstrap_schema(cfg.db_dsn)

# Docs/schema disabled: don't advertise the API surface publicly (every /v1 route is
# Bearer-gated, but the OpenAPI schema + Swagger UI were world-readable).
app = FastAPI(title="Goose Ingest", docs_url=None, redoc_url=None, openapi_url=None)

_STATIC = os.path.join(os.path.dirname(__file__), "static")
app.mount("/static", StaticFiles(directory=_STATIC), name="static")

# --- Auto-recompute throttle -------------------------------------------------
# The phone uploads opportunistically (every ~30s while connected, plus backlog
# drains), so /v1/ingest-decoded can fire many times per minute — each touching
# the SAME current day. compute_day now runs the heavy neurokit sleep-staging
# pipeline, so recomputing a day on every upload saturates CPU/memory. We
# therefore (a) single-flight recomputes (never run two at once) and (b) debounce
# per (device, day) so a day recomputes at most once per cooldown. On-demand
# freshness is always available via POST /v1/compute-daily.
_RECOMPUTE_COOLDOWN_S = 120.0
_recompute_lock = threading.Lock()
_last_recompute: dict[tuple[str, _dt.date], float] = {}


@app.get("/")
def dashboard():
    """Serve the datastore dashboard (static SPA reading the /v1 read API)."""
    return FileResponse(os.path.join(_STATIC, "index.html"))


@app.get("/architecture")
def architecture():
    """Serve the device-link architecture page (how we talk to the strap, no byte detail)."""
    return FileResponse(os.path.join(_STATIC, "architecture.html"))


class Frame(BaseModel):
    seq: int | None = None
    hex: str = Field(..., pattern=r"^[0-9a-fA-F]*$")

    @field_validator("hex")
    @classmethod
    def hex_even_length(cls, v: str) -> str:
        if len(v) % 2 != 0:
            raise ValueError("hex must have even length (complete bytes)")
        return v


class ClockRef(BaseModel):
    device: int
    wall: int


class Device(BaseModel):
    device_id: str
    mac: str | None = None
    name: str | None = None


class IngestBatch(BaseModel):
    batch_id: str
    device: Device
    clock_ref: ClockRef
    frames: list[Frame]
    decode_streams: bool = True


# ── Decoded-upload models ────────────────────────────────────────────────────

class DecodedDevice(BaseModel):
    id: str
    mac: str | None = None
    name: str | None = None


# Typed sub-models for each stream kind.  Pydantic validates and rejects
# out-of-range or missing-key payloads with a 422 BEFORE they reach
# store.upsert_streams, eliminating the unhandled psycopg 500 that would
# otherwise occur (e.g. bpm=99999 overflows the SMALLINT column).

class HrSample(BaseModel):
    ts: float
    bpm: int = Field(..., ge=0, le=300)


class RrSample(BaseModel):
    ts: float
    rr_ms: int = Field(..., ge=1, le=5000)


class EventSample(BaseModel):
    ts: float
    kind: str
    payload: dict | None = None


class BatterySample(BaseModel):
    ts: float
    soc: float | None = Field(default=None, ge=0.0, le=100.0)
    mv: int | None = Field(default=None, ge=0, le=10000)
    charging: bool | None = None


class Spo2Sample(BaseModel):
    ts: float
    red: int = Field(..., ge=0)
    ir: int = Field(..., ge=0)


class SkinTempSample(BaseModel):
    ts: float
    raw: int | float


class RespSample(BaseModel):
    ts: float
    raw: int | float


class GravitySample(BaseModel):
    ts: float
    x: float
    y: float
    z: float


class DecodedStreams(BaseModel):
    hr: list[HrSample] = []
    rr: list[RrSample] = []
    events: list[EventSample] = []
    battery: list[BatterySample] = []
    # Type-47 V24 biometric history (optional; older clients omit these). Values are
    # raw ADC for spo2/skin_temp/resp; gravity is the accel-derived vector in g.
    spo2: list[Spo2Sample] = []
    skin_temp: list[SkinTempSample] = []
    resp: list[RespSample] = []
    gravity: list[GravitySample] = []


class DecodedBatch(BaseModel):
    device: DecodedDevice
    streams: DecodedStreams
    # WHOOP device generation that produced these streams (Phase 05, D-10 / SRV-01).
    # Optional + defaulted for backward compatibility: clients that omit it (e.g. the
    # 4.0 reference app) are classified '5.0' on this 5.0-only deployment. Validated
    # as a plain string by Pydantic; never feeds dynamic SQL (persisted parametrised).
    device_generation: str | None = "5.0"


class RawFrame(BaseModel):
    captured_at_unix: float = Field(..., ge=0)
    frame_hex: str = Field(..., min_length=2, pattern=r"^[0-9a-fA-F]+$")
    source: str | None = None
    device_type: str | None = None
    device_model: str | None = None
    sensitivity: str | None = None

    @field_validator("frame_hex")
    @classmethod
    def frame_hex_even_length(cls, value: str) -> str:
        if len(value) % 2 != 0:
            raise ValueError("frame_hex must have even length (complete bytes)")
        return value


class RawFrameBatch(BaseModel):
    device: DecodedDevice
    frames: list[RawFrame]


class DeviceUpdate(BaseModel):
    display_name: str = Field(..., min_length=1, max_length=80)

    @field_validator("display_name", mode="before")
    @classmethod
    def trim_display_name(cls, value):
        if isinstance(value, str):
            return value.strip()
        return value


class SignupBody(BaseModel):
    name: str = Field(..., min_length=1, max_length=80)
    email: str = Field(..., min_length=3, max_length=320)
    password: str = Field(..., min_length=8, max_length=256)

    @field_validator("name", "email", mode="before")
    @classmethod
    def trim_identity_fields(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        value = value.lower()
        if "@" not in value:
            raise ValueError("invalid email")
        return value


class LoginBody(BaseModel):
    email: str = Field(..., min_length=3, max_length=320)
    password: str = Field(..., min_length=1, max_length=256)

    @field_validator("email", mode="before")
    @classmethod
    def normalize_login_email(cls, value):
        return value.strip().lower() if isinstance(value, str) else value


class DeviceClaim(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=160)
    name: str | None = Field(default=None, max_length=80)
    device_type: str = Field(default="whoop", min_length=1, max_length=40)

    @field_validator("device_id", "name", "device_type", mode="before")
    @classmethod
    def trim_claim_fields(cls, value):
        return value.strip() if isinstance(value, str) else value


class MockMetric(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=160)
    heart_rate: int | None = Field(default=None, ge=0, le=300)
    battery: float | None = Field(default=None, ge=0, le=100)
    recorded_at: _dt.datetime | None = None


def _auth_response(user_id, name, email, raw_token):
    return {
        "user": {"id": str(user_id), "name": name, "email": email},
        "api_token": raw_token,
        "token_type": "bearer",
    }


@app.post("/v1/auth/signup", status_code=201)
@app.post("/auth/signup", status_code=201, include_in_schema=False)
def signup(body: SignupBody):
    user_id = uuid.uuid4()
    raw_token = generate_api_token()
    try:
        with psycopg.connect(cfg.db_dsn) as conn:
            conn.execute(
                """INSERT INTO users (id, name, email, password_hash)
                   VALUES (%s, %s, %s, %s)""",
                (user_id, body.name, body.email, hash_password(body.password)),
            )
            conn.execute(
                """INSERT INTO api_tokens (id, user_id, token_hash, token_prefix)
                   VALUES (%s, %s, %s, %s)""",
                (uuid.uuid4(), user_id, hash_api_token(raw_token), token_prefix(raw_token)),
            )
            conn.commit()
    except UniqueViolation:
        raise HTTPException(status_code=409, detail="account already exists")
    return _auth_response(user_id, body.name, body.email, raw_token)


@app.post("/v1/auth/login")
@app.post("/auth/login", include_in_schema=False)
def login(body: LoginBody):
    with psycopg.connect(cfg.db_dsn) as conn:
        user = conn.execute(
            "SELECT id, name, email, password_hash FROM users WHERE email = %s",
            (body.email,),
        ).fetchone()
        if user is None or not verify_password(body.password, user[3]):
            raise HTTPException(status_code=401, detail="invalid email or password")
        raw_token = generate_api_token()
        conn.execute(
            """INSERT INTO api_tokens (id, user_id, token_hash, token_prefix)
               VALUES (%s, %s, %s, %s)""",
            (uuid.uuid4(), user[0], hash_api_token(raw_token), token_prefix(raw_token)),
        )
        conn.commit()
    return _auth_response(user[0], user[1], user[2], raw_token)


@app.get("/healthz")
def healthz():
    try:
        with psycopg.connect(cfg.db_dsn, connect_timeout=3) as conn:
            conn.execute("SELECT 1")
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=503, detail="db unavailable")


@app.post("/v1/ingest")
def ingest_batch(batch: IngestBatch, auth: AuthContext = Depends(require_auth)):
    payload = batch.model_dump()
    with psycopg.connect(cfg.db_dsn) as conn:
        device = payload["device"]
        store.ensure_device(conn, device["device_id"], mac=device.get("mac"), name=device.get("name"))
        authorize_device(conn, auth, device["device_id"], auto_bind=False)
        result = ingest.process_batch(conn, cfg, payload)
        conn.commit()
    return result


def _batch_dates_utc(streams: dict) -> set[_dt.date]:
    """UTC calendar dates spanned by every stream-row ts in an ingest batch."""
    days: set[_dt.date] = set()
    for rows in streams.values():
        for r in rows or []:
            ts = r.get("ts")
            if ts is None:
                continue
            days.add(_dt.datetime.fromtimestamp(float(ts), _dt.timezone.utc).date())
    return days


@app.post("/v1/ingest-decoded")
def ingest_decoded(batch: DecodedBatch, auth: AuthContext = Depends(require_auth)):
    payload = batch.model_dump()
    device_id = payload["device"]["id"]
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, device_id,
                            mac=payload["device"].get("mac"),
                            name=payload["device"].get("name"))
        authorize_device(conn, auth, device_id, auto_bind=False)
        counts = store.upsert_streams(conn, device_id, payload["streams"])
        conn.commit()
        # Recompute the day(s) this batch touched — throttled (see _RECOMPUTE_*).
        # Best-effort: a compute error must NOT fail the ingest (the raw streams
        # are already persisted) — log + move on.
        for day in _batch_dates_utc(payload["streams"]):
            key = (device_id, day)
            if time.monotonic() - _last_recompute.get(key, 0.0) < _RECOMPUTE_COOLDOWN_S:
                continue  # debounce: this day was recomputed very recently
            if not _recompute_lock.acquire(blocking=False):
                continue  # single-flight: a recompute is already running; a later upload catches up
            try:
                daily.compute_day(conn, device_id, day)
                conn.commit()
            except Exception:
                conn.rollback()
                _log.exception("compute_day failed for %s %s (ingest still 200)", device_id, day)
            finally:
                _last_recompute[key] = time.monotonic()  # throttle successes AND failures
                _recompute_lock.release()
    return {"upserted": counts}


@app.post("/v1/ingest-frames")
def ingest_frames(batch: RawFrameBatch, auth: AuthContext = Depends(require_auth)):
    payload = batch.model_dump()
    device_id = payload["device"]["id"]
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(
            conn,
            device_id,
            mac=payload["device"].get("mac"),
            name=payload["device"].get("name"),
        )
        authorize_device(conn, auth, device_id, auto_bind=False)
        inserted = store.insert_raw_frames(conn, device_id, payload["frames"])
        conn.commit()
    return {"inserted": inserted}


@app.get("/v1/me")
def get_me(auth: AuthContext = Depends(require_auth)):
    if auth.is_admin:
        return {"role": "admin", "user": None}
    return {
        "role": "user",
        "user": {"id": str(auth.user_id), "name": auth.name, "email": auth.email},
    }


@app.get("/v1/devices")
def get_devices(auth: AuthContext = Depends(require_auth)):
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.list_devices(conn, user_id=None if auth.is_admin else auth.user_id)


@app.post("/v1/devices/claim")
@app.post("/devices/claim", include_in_schema=False)
def claim_device(body: DeviceClaim, auth: AuthContext = Depends(require_auth)):
    if auth.is_admin or auth.user_id is None:
        raise HTTPException(status_code=403, detail="an account token is required")
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, body.device_id, name=body.name)
        conn.execute(
            """UPDATE devices
               SET device_type = %s, name = COALESCE(%s, name), last_seen = now()
               WHERE device_id = %s""",
            (body.device_type.lower(), body.name, body.device_id),
        )
        conn.execute("SELECT device_id FROM devices WHERE device_id = %s FOR UPDATE", (body.device_id,))
        owner = conn.execute(
            "SELECT user_id, display_name FROM device_owners WHERE device_id = %s",
            (body.device_id,),
        ).fetchone()
        if owner is not None and owner[0] != auth.user_id:
            raise HTTPException(status_code=409, detail="device is already claimed")
        if owner is None:
            conn.execute(
                """INSERT INTO device_owners (device_id, user_id, display_name)
                   VALUES (%s, %s, %s)""",
                (body.device_id, auth.user_id, body.name),
            )
        elif body.name is not None:
            conn.execute(
                "UPDATE device_owners SET display_name = %s WHERE device_id = %s",
                (body.name, body.device_id),
            )
        conn.commit()
    return {
        "device_id": body.device_id,
        "name": body.name if body.name is not None else (owner[1] if owner else None),
        "device_type": body.device_type.lower(),
        "claimed": True,
    }


@app.delete("/v1/devices/{device_id}/claim")
@app.delete("/devices/{device_id}/claim", include_in_schema=False)
def unclaim_device(device_id: str, auth: AuthContext = Depends(require_auth)):
    if auth.is_admin or auth.user_id is None:
        raise HTTPException(status_code=403, detail="an account token is required")
    with psycopg.connect(cfg.db_dsn) as conn:
        owner = conn.execute(
            "SELECT user_id FROM device_owners WHERE device_id = %s FOR UPDATE",
            (device_id,),
        ).fetchone()
        if owner is None:
            raise HTTPException(status_code=404, detail="claimed device not found")
        if owner[0] != auth.user_id:
            raise HTTPException(status_code=403, detail="device is owned by another user")
        conn.execute(
            "DELETE FROM device_owners WHERE device_id = %s AND user_id = %s",
            (device_id, auth.user_id),
        )
        conn.commit()
    return {"device_id": device_id, "claimed": False}


@app.post("/v1/metrics", status_code=201)
@app.post("/metrics", status_code=201, include_in_schema=False)
def insert_mock_metric(body: MockMetric, auth: AuthContext = Depends(require_auth)):
    if auth.is_admin or auth.user_id is None:
        raise HTTPException(status_code=403, detail="an account token is required")
    if body.heart_rate is None and body.battery is None:
        raise HTTPException(status_code=422, detail="heart_rate or battery is required")
    recorded_at = body.recorded_at or _dt.datetime.now(_dt.timezone.utc)
    metric_id = uuid.uuid4()
    with psycopg.connect(cfg.db_dsn) as conn:
        require_owned_device(conn, auth, body.device_id)
        conn.execute(
            """INSERT INTO mock_metrics
               (id, user_id, device_id, recorded_at, heart_rate, battery)
               VALUES (%s, %s, %s, %s, %s, %s)""",
            (
                metric_id, auth.user_id, body.device_id, recorded_at,
                body.heart_rate, body.battery,
            ),
        )
        conn.commit()
    return {
        "id": str(metric_id),
        "device_id": body.device_id,
        "recorded_at": recorded_at,
        "heart_rate": body.heart_rate,
        "battery": body.battery,
    }


@app.get("/v1/metrics")
@app.get("/metrics", include_in_schema=False)
def get_mock_metrics(
    device_id: str | None = None,
    limit: int = Query(100, ge=1, le=500),
    auth: AuthContext = Depends(require_auth),
):
    if auth.is_admin or auth.user_id is None:
        raise HTTPException(status_code=403, detail="an account token is required")
    with psycopg.connect(cfg.db_dsn) as conn:
        if device_id is not None:
            require_owned_device(conn, auth, device_id)
        rows = read.list_mock_metrics(
            conn,
            user_id=auth.user_id,
            device_id=device_id,
            limit=limit,
        )
    return rows


@app.patch("/v1/devices/{device_id}")
def update_device(
    device_id: str,
    body: DeviceUpdate,
    auth: AuthContext = Depends(require_auth),
):
    with psycopg.connect(cfg.db_dsn) as conn:
        owner = conn.execute(
            "SELECT user_id FROM device_owners WHERE device_id = %s",
            (device_id,),
        ).fetchone()
        if owner is None:
            raise HTTPException(status_code=404, detail="owned device not found")
        if not auth.is_admin and owner[0] != auth.user_id:
            raise HTTPException(status_code=403, detail="device is owned by another user")

        store.set_device_display_name(conn, device_id, body.display_name)
        conn.commit()
    return {"device_id": device_id, "display_name": body.display_name}


@app.get("/v1/batches", dependencies=[Depends(require_admin_auth)])
def get_batches(device: str, limit: int = Query(100, ge=1, le=10000)):
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.list_batches(conn, device_id=device, limit=limit)


@app.get("/v1/summary", dependencies=[Depends(require_admin_auth)])
def get_summary(device: str,
                from_: int = Query(0, alias="from"),
                to: int = Query(2_000_000_000, alias="to")):
    """Exact (unlimited) counts per decoded stream + raw batches, for accurate dashboard totals."""
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.counts(conn, device_id=device, start=from_, end=to)


@app.get("/v1/streams/{kind}", dependencies=[Depends(require_admin_auth)])
def get_stream(kind: str, device: str,
               from_: int = Query(0, alias="from"),
               to: int = Query(2_000_000_000, alias="to"),
               limit: int = Query(5000, ge=1, le=10000),
               max_points: int | None = None):
    try:
        with psycopg.connect(cfg.db_dsn) as conn:
            return read.query_stream(conn, kind, device_id=device, start=from_, end=to,
                                     limit=limit, max_points=max_points)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"unknown stream kind: {kind}")


# ── Daily analysis endpoints (Task 2.5) ──────────────────────────────────────

class ComputeDaily(BaseModel):
    device: str
    date: str  # YYYY-MM-DD


def _parse_date(s: str) -> _dt.date:
    try:
        return _dt.date.fromisoformat(s)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"invalid date (want YYYY-MM-DD): {s!r}")


@app.post("/v1/compute-daily", dependencies=[Depends(require_admin_auth)])
def compute_daily(body: ComputeDaily):
    """Compute + persist the daily metrics for a device/date, returning the summary."""
    day = _parse_date(body.date)
    with psycopg.connect(cfg.db_dsn) as conn:
        result = daily.compute_day(conn, body.device, day)
        conn.commit()
    return result


@app.get("/v1/daily", dependencies=[Depends(require_admin_auth)])
def get_daily(device: str,
              from_: str = Query(..., alias="from"),
              to: str = Query(..., alias="to")):
    """daily_metrics rows over the inclusive [from, to] date range (YYYY-MM-DD)."""
    start, end = _parse_date(from_), _parse_date(to)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_daily(conn, device, start, end)


@app.get("/v1/today", dependencies=[Depends(require_admin_auth)])
def get_today(device: str):
    """Most-recent daily_metrics row for the device (ORDER BY day DESC LIMIT 1), or null."""
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_today(conn, device)


@app.get("/v1/sleep", dependencies=[Depends(require_admin_auth)])
def get_sleep(device: str, date: str):
    """Sleep sessions whose night ENDS on ``date`` (YYYY-MM-DD)."""
    day = _parse_date(date)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_sleep(conn, device, day)


# ── Profile endpoints ─────────────────────────────────────────────────────────

_VALID_SEX = {"male", "female", "nonbinary"}


class ProfileBody(BaseModel):
    device: str
    height_cm: float | None = None
    weight_kg: float | None = None
    age: int | None = None
    sex: str | None = None


@app.get("/v1/profile", dependencies=[Depends(require_admin_auth)])
def get_profile(device: str):
    """Return the stored profile for a device, or {} if none exists."""
    with psycopg.connect(cfg.db_dsn) as conn:
        row = read.query_profile(conn, device)
    return row or {}


@app.post("/v1/profile", dependencies=[Depends(require_admin_auth)])
def upsert_profile(body: ProfileBody):
    """Create or update the user profile (height/weight/age/sex) for a device."""
    sex = body.sex
    if sex is not None:
        sex = sex.lower().strip()
        if sex not in _VALID_SEX:
            raise HTTPException(
                status_code=422,
                detail=f"sex must be one of {sorted(_VALID_SEX)} or null; got {body.sex!r}",
            )
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, body.device)
        store.upsert_profile(conn, body.device,
                             height_cm=body.height_cm,
                             weight_kg=body.weight_kg,
                             age=body.age,
                             sex=sex)
        conn.commit()
        row = read.query_profile(conn, body.device)
    return row


# ── Workouts endpoint ─────────────────────────────────────────────────────────

@app.get("/v1/workouts", dependencies=[Depends(require_admin_auth)])
def get_workouts(device: str,
                 from_: str = Query(..., alias="from"),
                 to: str = Query(..., alias="to")):
    """Exercise sessions whose start_ts (UTC date) is in [from, to] (YYYY-MM-DD)."""
    start, end = _parse_date(from_), _parse_date(to)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_workouts(conn, device, start, end)


# ── Backfill workouts endpoint ────────────────────────────────────────────────

class BackfillWorkouts(BaseModel):
    device: str
    # "from"/"to" are Python keywords; declare them via alias so FastAPI/Pydantic
    # deserialises {"from": "...", "to": "..."} directly without a manual remap.
    # populate_by_name=True keeps from_date/to_date working for any internal callers.
    from_date: str | None = Field(default=None, alias="from")
    to_date:   str | None = Field(default=None, alias="to")

    model_config = {"populate_by_name": True}


@app.post("/v1/backfill-workouts", dependencies=[Depends(require_admin_auth)])
def backfill_workouts(body: BackfillWorkouts):
    """Recompute exercise sessions (with calories) over a date range by replaying
    compute_day for each date. Idempotent — safe to re-run. May be slow for large
    ranges (runs the full daily pipeline per day). Auth-gated."""
    from_str = body.from_date
    to_str = body.to_date
    if from_str is None or to_str is None:
        raise HTTPException(status_code=422, detail="'from' and 'to' are required (YYYY-MM-DD)")
    start = _parse_date(from_str)
    end = _parse_date(to_str)
    if end < start:
        raise HTTPException(status_code=422, detail="'to' must be >= 'from'")
    _MAX_BACKFILL_DAYS = 366
    if (end - start).days + 1 > _MAX_BACKFILL_DAYS:
        raise HTTPException(
            status_code=422,
            detail=f"Range exceeds maximum of {_MAX_BACKFILL_DAYS} days",
        )
    results = []
    with psycopg.connect(cfg.db_dsn) as conn:
        day = start
        while day <= end:
            try:
                result = daily.compute_day(conn, body.device, day)
                conn.commit()
                results.append({"date": day.isoformat(), "status": "ok",
                                "exercises": result.get("exercises", [])})
            except Exception as exc:
                conn.rollback()
                _log.exception("backfill-workouts compute_day failed for device day=%s", day)
                results.append({"date": day.isoformat(), "status": "error", "detail": type(exc).__name__})
            day += _dt.timedelta(days=1)
    return {"recomputed": len(results), "days": results}


# ── iOS raw-frame upload models (POST /v1/ingest-frames) ────────────────────
# The iOS GooseUploadService.uploadRawFrames posts:
#   {"device": {"id": ..., "mac": ..., "name": ...}, "frames": [{captured_at_unix, frame_hex, ...}]}
# and reads json["inserted"] from the response (GooseUploadService.swift:182).

class IngestFramesDevice(BaseModel):
    id: str
    mac: str | None = None
    name: str | None = None


class IngestFrame(BaseModel):
    captured_at_unix: float
    frame_hex: str = Field(..., pattern=r"^[0-9a-fA-F]+$")
    source: str | None = None
    device_type: str | None = None
    device_model: str | None = None
    sensitivity: str | None = None
    device_uuid: str | None = None


class IngestFramesBatch(BaseModel):
    device: IngestFramesDevice
    frames: list[IngestFrame] = Field(..., max_length=5000)


@app.post("/v1/ingest-frames", dependencies=[Depends(require_auth)])
def ingest_frames(batch: IngestFramesBatch):
    """Accept a batch of raw BLE frames from iOS and persist to raw_frames.

    Returns {"inserted": N, "skipped": M}. Idempotent: re-posting the same
    frames (same device_id + captured_at_unix + frame_hex) increments skipped."""
    payload = batch.model_dump()
    device_id = payload["device"]["id"]
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, device_id,
                            mac=payload["device"].get("mac"),
                            name=payload["device"].get("name"))
        result = store.insert_raw_frames_batch(conn, device_id, payload["frames"])
        conn.commit()
    return result


@app.get("/v1/export/frames/{device_id}", dependencies=[Depends(require_admin_auth)])
def export_device_frames(
    device_id: str,
    from_: float = Query(0.0, alias="from", ge=0.0),
    to: float = Query(9_999_999_999.0, alias="to"),
    limit: int = Query(5000, ge=1, le=5000),
):
    """Export raw frames for a device in [from, to] unix seconds (paginated).
    iOS calls this as GET /v1/export/frames/{deviceID}?from=...&to=...&limit=5000
    to import historical data on a fresh install via capture.import_frame_batch."""
    with psycopg.connect(cfg.db_dsn) as conn:
        frames = read.read_device_frames(conn, device_id, from_ts=from_, to_ts=to, limit=limit)
    return {"device_id": device_id, "frames": frames, "count": len(frames)}


@app.get("/v1/batches/{batch_id}/frames", dependencies=[Depends(require_admin_auth)])
def get_batch_frames(batch_id: str):
    with psycopg.connect(cfg.db_dsn) as conn:
        row = conn.execute(
            "SELECT file_path FROM raw_batches WHERE batch_id = %s", (batch_id,)
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="batch not found")
    return read.read_batch_frames(row[0])
