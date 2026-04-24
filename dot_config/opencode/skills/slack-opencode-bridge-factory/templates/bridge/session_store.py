import sqlite3
import time
import os

DB_PATH = os.path.join(os.path.dirname(__file__), "sessions.db")


def _get_conn():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS thread_sessions (
            thread_ts TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            last_used_at INTEGER NOT NULL,
            depth INTEGER DEFAULT 0
        )
    """)
    # Migration: add depth column to existing DBs
    try:
        conn.execute("ALTER TABLE thread_sessions ADD COLUMN depth INTEGER DEFAULT 0")
    except sqlite3.OperationalError:
        pass  # already exists
    conn.commit()
    return conn


def get_session(thread_ts: str) -> str | None:
    with _get_conn() as conn:
        row = conn.execute(
            "SELECT session_id FROM thread_sessions WHERE thread_ts = ?", (thread_ts,)
        ).fetchone()
        return row[0] if row else None


def save_session(thread_ts: str, session_id: str) -> None:
    now = int(time.time())
    with _get_conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO thread_sessions (thread_ts, session_id, created_at, last_used_at) VALUES (?, ?, ?, ?)",
            (thread_ts, session_id, now, now),
        )


def touch_session(thread_ts: str) -> None:
    with _get_conn() as conn:
        conn.execute(
            "UPDATE thread_sessions SET last_used_at = ? WHERE thread_ts = ?",
            (int(time.time()), thread_ts),
        )


def get_depth(thread_ts: str) -> int:
    with _get_conn() as conn:
        row = conn.execute(
            "SELECT depth FROM thread_sessions WHERE thread_ts = ?", (thread_ts,)
        ).fetchone()
        return row[0] if row else 0


def increment_depth(thread_ts: str) -> int:
    with _get_conn() as conn:
        conn.execute(
            "UPDATE thread_sessions SET depth = depth + 1 WHERE thread_ts = ?",
            (thread_ts,),
        )
        row = conn.execute(
            "SELECT depth FROM thread_sessions WHERE thread_ts = ?", (thread_ts,)
        ).fetchone()
        return row[0] if row else 0


def reset_depth(thread_ts: str) -> None:
    with _get_conn() as conn:
        conn.execute(
            "UPDATE thread_sessions SET depth = 0 WHERE thread_ts = ?", (thread_ts,)
        )


def cleanup_old_sessions(days: int = 30) -> int:
    cutoff = int(time.time()) - (days * 86400)
    with _get_conn() as conn:
        result = conn.execute(
            "DELETE FROM thread_sessions WHERE last_used_at < ?", (cutoff,)
        )
        return result.rowcount
