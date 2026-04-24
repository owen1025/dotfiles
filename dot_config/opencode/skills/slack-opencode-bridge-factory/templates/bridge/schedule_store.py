"""
Schedule persistence for slack-opencode-bridge-factory.

Owns a SQLite database holding user-defined schedules. Used by both:
  - scheduler_mcp.py (writes via MCP tools called from the agent)
  - bridge.py (reads + executes via APScheduler)

IMPORTANT: This module does NOT use APScheduler's built-in persistence.
We keep our own table so that cross-process writes are reliable and the
schema is human-readable for debugging.
"""

from __future__ import annotations

import json
import os
import sqlite3
import time
import uuid
from typing import Any


def _default_db_path() -> str:
    # Per-agent DB under ~/.config/opencode-bridges/<agent>-schedules.db
    agent = os.environ.get("AGENT_NAME", "default")
    root = os.environ.get(
        "BRIDGE_CONFIG_DIR",
        os.path.expanduser("~/.config/opencode-bridges"),
    )
    os.makedirs(root, exist_ok=True)
    return os.path.join(root, f"{agent}-schedules.db")


DB_PATH = os.environ.get("SCHEDULE_DB_PATH") or _default_db_path()


def _conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False, timeout=10.0)
    conn.row_factory = sqlite3.Row
    # WAL improves concurrent read/write (MCP writer + bridge reader)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
    except sqlite3.OperationalError:
        pass
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS schedules (
            id TEXT PRIMARY KEY,
            description TEXT NOT NULL,
            prompt TEXT NOT NULL,
            trigger_type TEXT NOT NULL,        -- 'cron' | 'interval' | 'date'
            trigger_config TEXT NOT NULL,      -- JSON blob of APScheduler kwargs
            target_type TEXT NOT NULL,         -- 'dm' | 'channel'
            target_id TEXT NOT NULL,           -- Slack user_id or channel_id
            target_label TEXT,                 -- human-readable target (e.g. '#general', 'DM')
            timezone TEXT NOT NULL DEFAULT 'Asia/Seoul',
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            last_run_at INTEGER,
            last_status TEXT,                  -- 'success' | 'error'
            last_error TEXT,
            requested_by TEXT                  -- Slack user_id who asked
        )
        """
    )
    conn.commit()
    return conn


def _row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    d = dict(row)
    try:
        d["trigger_config"] = json.loads(d["trigger_config"])
    except (json.JSONDecodeError, TypeError):
        d["trigger_config"] = {}
    d["enabled"] = bool(d["enabled"])
    return d


def create_schedule(
    description: str,
    prompt: str,
    trigger_type: str,
    trigger_config: dict[str, Any],
    target_type: str,
    target_id: str,
    target_label: str | None = None,
    timezone: str = "Asia/Seoul",
    requested_by: str | None = None,
) -> dict[str, Any]:
    if trigger_type not in ("cron", "interval", "date"):
        raise ValueError(f"Invalid trigger_type: {trigger_type}")
    if target_type not in ("dm", "channel"):
        raise ValueError(f"Invalid target_type: {target_type}")

    sid = f"sch_{uuid.uuid4().hex[:12]}"
    now = int(time.time())
    with _conn() as conn:
        conn.execute(
            """
            INSERT INTO schedules (
                id, description, prompt,
                trigger_type, trigger_config,
                target_type, target_id, target_label,
                timezone, enabled,
                created_at, updated_at,
                requested_by
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
            """,
            (
                sid,
                description,
                prompt,
                trigger_type,
                json.dumps(trigger_config),
                target_type,
                target_id,
                target_label,
                timezone,
                now,
                now,
                requested_by,
            ),
        )
    return get_schedule(sid)  # type: ignore[return-value]


def set_enabled(schedule_id: str, enabled: bool) -> bool:
    with _conn() as conn:
        cur = conn.execute(
            "UPDATE schedules SET enabled=?, updated_at=? WHERE id=?",
            (1 if enabled else 0, int(time.time()), schedule_id),
        )
        return cur.rowcount > 0


def delete_schedule(schedule_id: str) -> bool:
    with _conn() as conn:
        cur = conn.execute("DELETE FROM schedules WHERE id=?", (schedule_id,))
        return cur.rowcount > 0


def mark_run(schedule_id: str, status: str, error: str | None = None) -> None:
    with _conn() as conn:
        conn.execute(
            """
            UPDATE schedules
            SET last_run_at=?, last_status=?, last_error=?, updated_at=?
            WHERE id=?
            """,
            (int(time.time()), status, error, int(time.time()), schedule_id),
        )


def get_schedule(schedule_id: str) -> dict[str, Any] | None:
    with _conn() as conn:
        row = conn.execute(
            "SELECT * FROM schedules WHERE id=?", (schedule_id,)
        ).fetchone()
        return _row_to_dict(row) if row else None


def list_schedules(enabled_only: bool = False) -> list[dict[str, Any]]:
    sql = "SELECT * FROM schedules"
    if enabled_only:
        sql += " WHERE enabled=1"
    sql += " ORDER BY created_at DESC"
    with _conn() as conn:
        rows = conn.execute(sql).fetchall()
        return [_row_to_dict(r) for r in rows]


def max_updated_at() -> int:
    with _conn() as conn:
        row = conn.execute("SELECT MAX(updated_at) AS m FROM schedules").fetchone()
        return int(row["m"]) if row and row["m"] is not None else 0
