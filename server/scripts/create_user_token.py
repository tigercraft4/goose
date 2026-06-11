#!/usr/bin/env python3
"""Create a user and print a newly generated API token exactly once."""
import argparse
import os
import secrets
import sys
import uuid
from pathlib import Path

import psycopg

SERVER_ROOT = Path(__file__).resolve().parents[1]
INGEST_ROOT = SERVER_ROOT / "ingest"
sys.path.insert(0, str(INGEST_ROOT if INGEST_ROOT.exists() else SERVER_ROOT))

from app.auth import hash_api_token, token_prefix  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--email", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    dsn = os.environ.get("GOOSE_DB_DSN")
    if not dsn:
        print("GOOSE_DB_DSN is required", file=sys.stderr)
        return 2

    raw_token = "goose_" + secrets.token_urlsafe(32)
    digest = hash_api_token(raw_token)
    prefix = token_prefix(raw_token)

    with psycopg.connect(dsn) as conn:
        user = conn.execute(
            """INSERT INTO users (id, name, email)
               VALUES (%s, %s, %s)
               ON CONFLICT (email) DO UPDATE
               SET name = COALESCE(users.name, EXCLUDED.name)
               RETURNING id, name, email""",
            (uuid.uuid4(), args.name, args.email),
        ).fetchone()
        conn.execute(
            """INSERT INTO api_tokens (id, user_id, token_hash, token_prefix)
               VALUES (%s, %s, %s, %s)""",
            (uuid.uuid4(), user[0], digest, prefix),
        )
        conn.commit()

    print(f"User: {user[1] or ''} <{user[2]}>")
    print(f"User ID: {user[0]}")
    print(f"API token: {raw_token}")
    print(f"Token prefix: {prefix}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
