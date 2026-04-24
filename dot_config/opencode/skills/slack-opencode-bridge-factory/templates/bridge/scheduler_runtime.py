"""
APScheduler runtime embedded in bridge.py.

Responsibilities:
  1. Start a BackgroundScheduler in Asia/Seoul timezone.
  2. Poll schedule_store (SQLite) every RELOAD_INTERVAL_SEC seconds and
     sync jobs to the scheduler (add/update/remove based on DB state).
  3. When a job fires, run the callback that creates a fresh OpenCode
     session, collects the response, and posts it to Slack (DM or channel).

Why poll instead of using APScheduler's SQLAlchemyJobStore directly?
  - Multi-process SQLAlchemyJobStore requires pickling user callables
    (complicates dependency on bridge internals like `app.client`).
  - Our own schema stays human-readable and easy to debug via sqlite3 CLI.
  - 30s polling latency is acceptable for minute-granularity schedules.
"""

from __future__ import annotations

import logging
import os
import threading
from typing import Any, Callable

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.date import DateTrigger
from apscheduler.triggers.interval import IntervalTrigger
import pytz

import schedule_store

log = logging.getLogger(__name__)

DEFAULT_TZ = os.environ.get("SCHEDULE_TIMEZONE", "Asia/Seoul")
RELOAD_INTERVAL_SEC = int(os.environ.get("SCHEDULE_RELOAD_SEC", "30"))


def _build_trigger(trigger_type: str, cfg: dict[str, Any], tz: str):
    tzinfo = pytz.timezone(tz)
    if trigger_type == "cron":
        return CronTrigger(timezone=tzinfo, **cfg)
    if trigger_type == "interval":
        return IntervalTrigger(timezone=tzinfo, **cfg)
    if trigger_type == "date":
        return DateTrigger(timezone=tzinfo, run_date=cfg["run_date"])
    raise ValueError(f"Unknown trigger_type: {trigger_type}")


class ScheduleRuntime:
    def __init__(self, executor: Callable[[dict[str, Any]], None]):
        self._executor = executor
        self._scheduler = BackgroundScheduler(timezone=pytz.timezone(DEFAULT_TZ))
        self._known_state: dict[str, tuple[int, bool]] = {}
        self._lock = threading.Lock()

    def start(self) -> None:
        self._scheduler.start()
        self._sync_from_db()
        self._scheduler.add_job(
            self._sync_from_db,
            trigger=IntervalTrigger(seconds=RELOAD_INTERVAL_SEC),
            id="__schedule_reloader__",
            replace_existing=True,
            max_instances=1,
            coalesce=True,
        )
        log.info(
            f"ScheduleRuntime started (tz={DEFAULT_TZ}, reload={RELOAD_INTERVAL_SEC}s)"
        )

    def shutdown(self) -> None:
        try:
            self._scheduler.shutdown(wait=False)
        except Exception as e:
            log.warning(f"Scheduler shutdown error: {e}")

    def _sync_from_db(self) -> None:
        with self._lock:
            try:
                rows = schedule_store.list_schedules()
            except Exception as e:
                log.error(f"Failed to list schedules: {e}")
                return

            seen: set[str] = set()
            for s in rows:
                sid = s["id"]
                seen.add(sid)
                fingerprint = (int(s["updated_at"]), bool(s["enabled"]))
                if self._known_state.get(sid) == fingerprint:
                    continue

                if not s["enabled"]:
                    self._remove_job(sid)
                    self._known_state[sid] = fingerprint
                    continue

                try:
                    trigger = _build_trigger(
                        s["trigger_type"], s["trigger_config"], s["timezone"]
                    )
                except Exception as e:
                    log.error(f"Invalid trigger for {sid}: {e}")
                    schedule_store.mark_run(sid, "error", f"trigger-build: {e}")
                    continue

                self._scheduler.add_job(
                    self._run_schedule,
                    trigger=trigger,
                    args=[sid],
                    id=sid,
                    replace_existing=True,
                    max_instances=1,
                    coalesce=True,
                    misfire_grace_time=300,
                )
                self._known_state[sid] = fingerprint
                log.info(
                    f"Scheduled {sid}: {s['description']} ({s['trigger_type']} {s['trigger_config']})"
                )

            for sid in list(self._known_state.keys()):
                if sid not in seen:
                    self._remove_job(sid)
                    self._known_state.pop(sid, None)

    def _remove_job(self, sid: str) -> None:
        try:
            self._scheduler.remove_job(sid)
            log.info(f"Removed schedule {sid}")
        except Exception:
            pass

    def _run_schedule(self, schedule_id: str) -> None:
        s = schedule_store.get_schedule(schedule_id)
        if not s:
            log.warning(f"Schedule {schedule_id} vanished before execution")
            return
        if not s["enabled"]:
            return
        try:
            self._executor(s)
            schedule_store.mark_run(schedule_id, "success")
        except Exception as e:
            log.error(f"Schedule {schedule_id} failed: {e}", exc_info=True)
            schedule_store.mark_run(schedule_id, "error", str(e))
