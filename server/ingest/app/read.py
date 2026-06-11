"""Read-side queries + archive-frame reader for the Whoop datastore. DB + filesystem,
no HTTP. Timestamps are returned as ISO-8601 strings (psycopg gives tz-aware datetimes;
FastAPI serialises them)."""
import math
import uuid as _uuid

import zstandard

from .analysis.units import (
    resp_rate_bpm,
    skin_temp_celsius,
    spo2_percent,
    spo2_percent_window,
)

# Rolling-window radius (samples each side) for the windowed SpO2 estimator.
# A single sample is too noisy; we use a centered window so each row's `value`
# reflects the local AC/DC ratio. Falls back to the single-sample estimate when
# there are too few neighbours.
_SPO2_WINDOW_RADIUS = 8


def _is_uuid(s: str) -> bool:
    """Return True when s is a valid UUID string (any variant), False otherwise."""
    try:
        _uuid.UUID(s)
        return True
    except ValueError:
        return False

# kind -> (table, value columns) for the decoded stream endpoints.
_STREAMS = {
    "hr": ("hr_samples", ["bpm"]),
    "rr": ("rr_intervals", ["rr_ms"]),
    "events": ("events", ["kind", "payload"]),
    "battery": ("battery", ["soc", "mv", "charging"]),
    # Type-47 V24 biometric history. spo2/skin_temp/resp values are raw ADC counts
    # (cloud computes human units); gravity is the accel-derived vector in g.
    "spo2": ("spo2_samples", ["red", "ir"]),
    "skin_temp": ("skin_temp_samples", ["raw"]),
    "resp": ("resp_samples", ["raw"]),
    "gravity": ("gravity_samples", ["x", "y", "z"]),
}

# Which kinds may be time-bucket downsampled, and how to round each avg'd value
# column for presentation. `events` is excluded entirely (text/jsonb cols can't be
# averaged). Everything listed here has only NUMERIC value columns. Round to None
# keeps the raw float (e.g. gravity, where small magnitudes matter).
#   col -> decimal places (int) | None (keep float, no rounding)
_DOWNSAMPLE = {
    "hr": {"bpm": 0},
    "rr": {"rr_ms": 0},
    "battery": {"soc": 1, "mv": 0},
    "spo2": {"red": 0, "ir": 0},
    "skin_temp": {"raw": 1},
    "resp": {"raw": 1},
    "gravity": {"x": None, "y": None, "z": None},
}


def list_devices(conn, user_id=None):
    if user_id is None:
        rows = conn.execute(
            """SELECT d.device_id, o.display_name, o.user_id, u.name, u.email,
                      o.created_at, d.last_seen
               FROM devices d
               LEFT JOIN device_owners o ON o.device_id = d.device_id
               LEFT JOIN users u ON u.id = o.user_id
               ORDER BY d.device_id"""
        ).fetchall()
        cols = [
            "device_id", "display_name", "owner_user_id", "owner_name",
            "owner_email", "created_at", "last_seen",
        ]
    else:
        rows = conn.execute(
            """SELECT d.device_id, o.display_name, o.nickname, o.created_at, d.last_seen
               FROM devices d
               JOIN device_owners o ON o.device_id = d.device_id
               WHERE o.user_id = %s
               ORDER BY d.device_id""",
            (user_id,),
        ).fetchall()
        cols = ["device_id", "display_name", "nickname", "created_at", "last_seen"]
    return [dict(zip(cols, r)) for r in rows]


def list_mock_metrics(conn, user_id, device_id=None, limit=100):
    filters = ["user_id = %s"]
    params = [user_id]
    if device_id is not None:
        filters.append("device_id = %s")
        params.append(device_id)
    params.append(limit)
    rows = conn.execute(
        """SELECT id::text, device_id, recorded_at, heart_rate, battery
           FROM mock_metrics
           WHERE """ + " AND ".join(filters) + """
           ORDER BY recorded_at DESC
           LIMIT %s""",
        params,
    ).fetchall()
    cols = ["id", "device_id", "recorded_at", "heart_rate", "battery"]
    return [dict(zip(cols, row)) for row in rows]


def list_batches(conn, device_id, limit=100):
    rows = conn.execute(
        """SELECT batch_id::text, device_id, received_at, start_ts, end_ts, packet_count,
                  file_path, sha256, byte_size
           FROM raw_batches WHERE device_id = %s ORDER BY start_ts DESC NULLS LAST LIMIT %s""",
        (device_id, limit),
    ).fetchall()
    cols = ["batch_id", "device_id", "received_at", "start_ts", "end_ts",
            "packet_count", "file_path", "sha256", "byte_size"]
    return [dict(zip(cols, r)) for r in rows]


def query_stream(conn, kind, device_id, start, end, limit=5000, max_points=None):
    """Return time-ordered rows for ``kind`` in [start, end] (unix seconds).

    ``limit`` is a hard safety cap on the number of returned rows. ``max_points``,
    when set, enables server-side time-bucket downsampling for high-rate streams so
    the FULL range renders (bucketed to ~chart resolution) with the latest sample at
    the right edge — instead of returning only the oldest ``limit`` rows.

    Downsampling triggers only when (a) ``max_points`` is set, (b) the kind is
    downsampleable (numeric value cols — `events` is excluded), and (c) the raw row
    count in the window exceeds ``max_points``. We do a cheap COUNT(*) first to decide;
    when it's within budget we fall through to the exact (un-bucketed) path so existing
    callers and small windows see ZERO behaviour change.

    Bucket width = max(1s, ceil((end-start)/max_points)) seconds. Each NUMERIC value
    column is avg()'d over the bucket and the bucket-start ts is returned; the bucket
    grid spans the whole window so the last bucket carries the latest data. Units
    augmentation runs on the (possibly downsampled) rows exactly as before."""
    if kind not in _STREAMS:
        raise ValueError(f"unknown stream kind: {kind}")
    table, value_cols = _STREAMS[kind]

    if max_points is not None and max_points > 0 and kind in _DOWNSAMPLE:
        # One probe: row count + the ACTUAL data extent inside the window. Bucket width
        # must be derived from the real data span (epoch seconds), not the caller's
        # nominal [start,end] — the dashboard's "all" range is a giant sentinel
        # (from=0&to=2e9), and using it would collapse hours of data into one bucket.
        total, span = conn.execute(
            f"SELECT count(*), "
            "COALESCE(extract(epoch FROM max(ts)) - extract(epoch FROM min(ts)), 0) "
            f"FROM {table} "
            "WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s)",
            (device_id, start, end),
        ).fetchone()
        if total > max_points:
            return _query_stream_downsampled(
                conn, kind, table, value_cols, device_id, start, end,
                max_points, limit, span)

    cols = ["ts"] + value_cols
    sql = (f"SELECT {', '.join(cols)} FROM {table} "
           f"WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s) "
           f"ORDER BY ts LIMIT %s")
    rows = conn.execute(sql, (device_id, start, end, limit)).fetchall()
    out = [dict(zip(cols, r)) for r in rows]
    return _augment_units(kind, out)


def _query_stream_downsampled(conn, kind, table, value_cols, device_id,
                              start, end, max_points, limit, span):
    """Time-bucket downsample a numeric stream. Bucket width (whole seconds) =
    max(1, ceil(span / max_points)), where ``span`` is the ACTUAL data extent
    (max(ts)-min(ts) in the window), so the buckets track real data density rather
    than a possibly-huge sentinel window. SELECTs time_bucket(...) AS ts + avg(col)
    per value column, GROUP BY the bucket, ORDER BY ts; capped at ``limit``. Value/col
    names come from the hardcoded _STREAMS/_DOWNSAMPLE maps (never user input)."""
    width = max(1, math.ceil(max(0.0, float(span)) / max_points))
    rounding = _DOWNSAMPLE[kind]
    # Average only the NUMERIC columns named in _DOWNSAMPLE (e.g. battery.charging is a
    # boolean and must never reach avg()). Non-averaged value cols are dropped from the
    # downsampled view — acceptable, and battery is fetched without max_points anyway.
    avg_cols = [c for c in value_cols if c in rounding]
    avg_exprs = ", ".join(f"avg({c}) AS {c}" for c in avg_cols)
    cols = ["ts"] + avg_cols
    sql = (
        f"SELECT time_bucket(make_interval(secs => %s), ts) AS ts, {avg_exprs} "
        f"FROM {table} "
        "WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s) "
        "GROUP BY 1 ORDER BY 1 LIMIT %s"
    )
    rows = conn.execute(sql, (width, device_id, start, end, limit)).fetchall()
    out = []
    for r in rows:
        d = dict(zip(cols, r))
        for c in avg_cols:
            v = d[c]
            if v is None:
                continue
            v = float(v)
            places = rounding[c]
            d[c] = int(round(v)) if places == 0 else (v if places is None else round(v, places))
        out.append(d)
    return _augment_units(kind, out)


def _augment_units(kind, rows):
    """Add APPROXIMATE human-unit fields (`value` + `unit`) to spo2/skin_temp/resp
    rows in place, alongside the raw columns. Uses analysis.units (pure functions).
    Other kinds (hr/rr/events/battery/gravity) are returned unchanged. SpO2 uses a
    centered rolling window over the time-ordered rows (single-sample fallback)."""
    if kind == "spo2":
        reds = [float(r["red"]) for r in rows]
        irs = [float(r["ir"]) for r in rows]
        n = len(rows)
        for i, r in enumerate(rows):
            lo = max(0, i - _SPO2_WINDOW_RADIUS)
            hi = min(n, i + _SPO2_WINDOW_RADIUS + 1)
            win_red = reds[lo:hi]
            win_ir = irs[lo:hi]
            try:
                if len(win_red) >= 2:
                    val = spo2_percent_window(win_red, win_ir)
                else:
                    val = spo2_percent(reds[i], irs[i])
            except ZeroDivisionError:
                val = None
            r["value"] = round(val, 1) if val is not None else None
            r["unit"] = "%"
    elif kind == "skin_temp":
        for r in rows:
            raw = r.get("raw")
            r["value"] = round(skin_temp_celsius(raw), 1) if raw is not None else None
            r["unit"] = "°C"
    elif kind == "resp":
        for r in rows:
            raw = r.get("raw")
            r["value"] = round(resp_rate_bpm(raw), 1) if raw is not None else None
            r["unit"] = "bpm"
    return rows


def counts(conn, device_id, start, end):
    """Accurate COUNT(*) per decoded stream + raw batches for a device within a time window.
    Unlimited (unlike the row/list endpoints) so dashboard totals are exact and comparable
    to the phone's local totals. Table names come from the hardcoded _STREAMS map (no injection)."""
    out = {}
    for kind, (table, _value_cols) in _STREAMS.items():
        out[kind] = conn.execute(
            f"SELECT count(*) FROM {table} "
            "WHERE device_id = %s AND ts >= to_timestamp(%s) AND ts <= to_timestamp(%s)",
            (device_id, start, end),
        ).fetchone()[0]
    out["batches"] = conn.execute(
        "SELECT count(*) FROM raw_batches "
        "WHERE device_id = %s AND start_ts >= to_timestamp(%s) AND start_ts <= to_timestamp(%s)",
        (device_id, start, end),
    ).fetchone()[0]
    return out


# ── Profile reads ─────────────────────────────────────────────────────────────

_PROFILE_COLS = ["device_id", "height_cm", "weight_kg", "age", "sex", "updated_at"]


def query_profile(conn, device_id: str) -> dict | None:
    """Return the profile row for ``device_id``, or ``None`` if none exists."""
    row = conn.execute(
        f"SELECT {', '.join(_PROFILE_COLS)} FROM profile WHERE device_id = %s",
        (device_id,),
    ).fetchone()
    if row is None:
        return None
    return dict(zip(_PROFILE_COLS, row))


# ── Derived daily-analysis reads (Task 2.5) ──────────────────────────────────

_DAILY_COLS = ["device_id", "day", "total_sleep_min", "efficiency", "deep_min",
               "rem_min", "light_min", "disturbances", "resting_hr", "avg_hrv",
               "recovery", "strain", "exercise_count", "sleep_start", "sleep_end",
               "spo2_pct", "skin_temp_dev_c", "resp_rate_bpm",
               "sleep_performance", "training_state", "sleep_needed_min",
               "total_calories_kcal", "computed_at"]


def query_daily(conn, device_id, start_date, end_date):
    """daily_metrics rows for a device over the inclusive [start_date, end_date]
    DATE range. start_date/end_date are datetime.date (or YYYY-MM-DD strings)."""
    rows = conn.execute(
        f"SELECT {', '.join(_DAILY_COLS)} FROM daily_metrics "
        "WHERE device_id = %s AND day >= %s AND day <= %s ORDER BY day",
        (device_id, start_date, end_date),
    ).fetchall()
    return [dict(zip(_DAILY_COLS, r)) for r in rows]


def query_today(conn, device_id):
    """Most-recent daily_metrics row for a device (ORDER BY day DESC LIMIT 1).
    Returns a single dict (same format as one row from query_daily) or None if no rows exist."""
    row = conn.execute(
        f"SELECT {', '.join(_DAILY_COLS)} FROM daily_metrics "
        "WHERE device_id = %s ORDER BY day DESC LIMIT 1",
        (device_id,),
    ).fetchone()
    if row is None:
        return None
    return dict(zip(_DAILY_COLS, row))


def query_sleep(conn, device_id, day):
    """Sleep sessions for a device whose END falls on ``day`` (the night ending
    that morning). ``day`` is a datetime.date (or YYYY-MM-DD string). Stages are
    returned parsed (JSONB → list). Timestamps are tz-aware datetimes (ISO on the wire)."""
    cols = ["device_id", "start_ts", "end_ts", "efficiency", "resting_hr", "avg_hrv", "stages"]
    rows = conn.execute(
        f"SELECT {', '.join(cols)} FROM sleep_sessions "
        "WHERE device_id = %s AND (end_ts AT TIME ZONE 'UTC')::date = %s ORDER BY start_ts",
        (device_id, day),
    ).fetchall()
    return [dict(zip(cols, r)) for r in rows]


_WORKOUT_COLS = [
    "device_id", "start_ts", "end_ts", "avg_hr", "peak_hr", "strain", "kind",
    "duration_s", "zone_time_pct", "avg_hrr_pct", "hrmax", "hrmax_source",
    "calories_kcal", "calories_kj",
]


def query_workouts(conn, device_id, start_date, end_date):
    """Exercise sessions for a device whose start_ts (UTC date) is in
    [start_date, end_date] (inclusive). start_date/end_date are datetime.date
    (or YYYY-MM-DD strings). Returns all columns including calories."""
    rows = conn.execute(
        f"SELECT {', '.join(_WORKOUT_COLS)} FROM exercise_sessions "
        "WHERE device_id = %s "
        "AND (start_ts AT TIME ZONE 'UTC')::date >= %s "
        "AND (start_ts AT TIME ZONE 'UTC')::date <= %s "
        "ORDER BY start_ts",
        (device_id, start_date, end_date),
    ).fetchall()
    return [dict(zip(_WORKOUT_COLS, r)) for r in rows]


def read_device_frames(conn, device_id: str, from_ts: float, to_ts: float, limit: int = 5000):
    """Return raw frames for a device in [from_ts, to_ts] unix seconds, paginatable.

    Frames uploaded directly by iOS are authoritative and returned when present.
    Older deployments fall back to reconstructing timestamps from archived batches.
    Timestamps are interpolated linearly within each batch's [start_ts, end_ts] window.
    Returns list of dicts compatible with the iOS capture.import_frame_batch format:
      {captured_at_unix, frame_hex, source, device_model, device_type, sensitivity}
    """
    rows = conn.execute(
        """SELECT extract(epoch FROM captured_at)::float, frame_hex, source,
                  device_model, device_type, sensitivity
           FROM raw_frames
           WHERE device_id = %s
             AND captured_at >= to_timestamp(%s)
             AND captured_at <= to_timestamp(%s)
           ORDER BY captured_at
           LIMIT %s""",
        (device_id, from_ts, to_ts, limit),
    ).fetchall()
    if rows:
        cols = [
            "captured_at_unix",
            "frame_hex",
            "source",
            "device_model",
            "device_type",
            "sensitivity",
        ]
        return [dict(zip(cols, row)) for row in rows]

    name_row = conn.execute(
        "SELECT name FROM devices WHERE device_id = %s", (device_id,)
    ).fetchone()
    device_name = (name_row[0] or "WHOOP Goose") if name_row else "WHOOP Goose"

    batches = conn.execute(
        """SELECT file_path,
                  extract(epoch FROM start_ts)::float AS start_unix,
                  extract(epoch FROM end_ts)::float   AS end_unix,
                  packet_count
           FROM raw_batches
           WHERE device_id = %s
             AND extract(epoch FROM end_ts) >= %s
             AND extract(epoch FROM start_ts) <= %s
           ORDER BY start_ts""",
        (device_id, from_ts, to_ts),
    ).fetchall()

    out = []
    for file_path, start_unix, end_unix, packet_count in batches:
        if len(out) >= limit:
            break
        if not file_path:
            continue
        try:
            with open(file_path, "rb") as fh:
                raw = zstandard.ZstdDecompressor().decompress(fh.read())
        except (OSError, Exception):
            continue

        lines = [ln for ln in raw.decode().splitlines() if ln]
        n = len(lines)
        if n == 0:
            continue
        duration = max((end_unix or start_unix) - (start_unix or 0), 0.0)
        for i, hex_line in enumerate(lines):
            frac = i / n if n > 1 else 0.0
            ts = (start_unix or 0.0) + frac * duration
            if ts < from_ts or ts > to_ts:
                continue
            out.append({
                "captured_at_unix": ts,
                "frame_hex": hex_line,
                "source": "ios.corebluetooth.notification",
                "device_model": device_name,
                "device_type": "GOOSE",
                "sensitivity": "user-owned-capture",
            })
            if len(out) >= limit:
                break

    # Also include frames uploaded directly via POST /v1/ingest-frames (raw_frames table).
    # These carry the exact iOS shape already; NULL columns fall back to the same defaults
    # as the archive path above so the iOS importer sees a uniform dict format.
    # Bidirectional lookup: if device_id is a UUID, query by device_uuid column;
    # otherwise query by device_model. Both branches are fully parameterised (%s).
    remaining = max(0, limit - len(out))
    is_uuid = _is_uuid(device_id)
    device_clause = "device_uuid = %s" if is_uuid else "device_model = %s"
    db_rows = conn.execute(
        f"""SELECT extract(epoch FROM captured_at)::float AS captured_at_unix,
                  frame_hex,
                  source,
                  device_model,
                  device_type,
                  sensitivity
           FROM raw_frames
           WHERE {device_clause}
             AND extract(epoch FROM captured_at) >= %s
             AND extract(epoch FROM captured_at) <= %s
           ORDER BY captured_at
           LIMIT %s""",
        (device_id, from_ts, to_ts, remaining),
    ).fetchall()
    for row in db_rows:
        out.append({
            "captured_at_unix": row[0],
            "frame_hex": row[1],
            "source": row[2] if row[2] is not None else "ios.corebluetooth.notification",
            "device_model": row[3] if row[3] is not None else device_name,
            "device_type": row[4] if row[4] is not None else "GOOSE",
            "sensitivity": row[5] if row[5] is not None else "user-owned-capture",
        })

    # Merge both sources, sort ascending by timestamp, then truncate to limit.
    out.sort(key=lambda r: r["captured_at_unix"])
    return out[:limit]


from whoop_protocol import parse_frame


def read_batch_frames(file_path):
    """Decompress a batch's .zst archive and parse each frame via whoop-protocol.
    Returns [{seq, hex, type_name, crc_ok, fields, parsed}] in archived order."""
    with open(file_path, "rb") as fh:
        raw = zstandard.ZstdDecompressor().decompress(fh.read())
    out = []
    for seq, line in enumerate(raw.decode().splitlines()):
        if not line:
            continue
        parsed = parse_frame(bytes.fromhex(line))
        out.append({
            "seq": seq, "hex": line, "type_name": parsed.get("type_name"),
            "crc_ok": parsed.get("crc_ok"), "fields": parsed.get("fields", []),
            "parsed": parsed.get("parsed", {}),
        })
    return out
