"""
MCP stdio server exposing schedule CRUD to the OpenCode agent.

Tools:
  - schedule_register: create a recurring or one-shot schedule
  - schedule_list:     list all schedules for this agent
  - schedule_delete:   remove a schedule
  - schedule_pause:    disable without deleting
  - schedule_resume:   re-enable

Design:
  - Uses the SAME SQLite database as bridge.py (via schedule_store.py).
  - Only WRITES to the DB. The bridge process polls the DB and owns the
    APScheduler instance that actually fires jobs.
  - Runs under OpenCode's `mcp.local` stdio transport.

The agent is expected to:
  1. Interpret natural-language schedule requests ("매일 5시 …")
  2. Ask the user where to deliver results (DM vs channel)
  3. Call schedule_register with resolved cron/interval/date config
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from typing import Any

# Make the bundled schedule_store importable when launched via stdio
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import schedule_store  # noqa: E402

from mcp.server import Server  # noqa: E402
from mcp.server.stdio import stdio_server  # noqa: E402
import mcp.types as types  # noqa: E402


AGENT_NAME = os.environ.get("AGENT_NAME", "unknown")
DEFAULT_TZ = os.environ.get("SCHEDULE_TIMEZONE", "Asia/Seoul")

server = Server(f"scheduler-{AGENT_NAME}")


REGISTER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "description": {
            "type": "string",
            "description": "Short human-readable description (e.g. '매일 오후 5시 캘린더 정리'). Shown to the user in lists.",
        },
        "prompt": {
            "type": "string",
            "description": (
                "The prompt the agent will receive when the schedule fires. "
                "Write it as if the user just sent it: 'Google Calendar를 확인하고 오늘 일정을 요약해서 보고해줘'. "
                "DO NOT include meta-instructions like 'send to Slack' — delivery is handled automatically."
            ),
        },
        "trigger_type": {
            "type": "string",
            "enum": ["cron", "interval", "date"],
            "description": (
                "'cron' for recurring at specific times (e.g. every day at 17:00), "
                "'interval' for every N seconds/minutes/hours, "
                "'date' for one-shot at a specific datetime."
            ),
        },
        "trigger_config": {
            "type": "object",
            "description": (
                "APScheduler trigger kwargs. "
                "For cron: {hour, minute, day_of_week, day, month} — e.g. {\"hour\": 17, \"minute\": 0} for every day 5pm. "
                "Use '*' or omit for wildcard. day_of_week uses 'mon,tue,...' or '0-6'. "
                "For interval: {seconds | minutes | hours | days} — e.g. {\"minutes\": 30}. "
                "For date: {run_date} — ISO 8601 string, e.g. '2025-12-25T09:00:00'."
            ),
            "additionalProperties": True,
        },
        "target_type": {
            "type": "string",
            "enum": ["dm", "channel"],
            "description": (
                "Where to deliver the report. "
                "'dm' = direct message to a Slack user (use their user_id). "
                "'channel' = post to a channel (use channel_id, not #name)."
            ),
        },
        "target_id": {
            "type": "string",
            "description": "Slack user_id (U...) for DM, or channel_id (C.../D...) for channel.",
        },
        "target_label": {
            "type": "string",
            "description": "Optional human-readable label for the target (e.g. '#general', 'DM: owen').",
        },
        "timezone": {
            "type": "string",
            "description": f"IANA timezone name. Default: {DEFAULT_TZ}.",
            "default": DEFAULT_TZ,
        },
        "requested_by": {
            "type": "string",
            "description": "Slack user_id who requested this schedule (for audit).",
        },
    },
    "required": [
        "description",
        "prompt",
        "trigger_type",
        "trigger_config",
        "target_type",
        "target_id",
    ],
}


@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="schedule_register",
            description=(
                "Register a recurring or one-shot scheduled task. The agent should "
                "parse the user's natural-language request (e.g. '매일 5시 캘린더 정리') "
                "into a trigger_type + trigger_config, then ASK the user whether "
                "they want results delivered via DM or channel before calling this tool. "
                f"Default timezone is {DEFAULT_TZ}."
            ),
            inputSchema=REGISTER_SCHEMA,
        ),
        types.Tool(
            name="schedule_list",
            description="List all schedules owned by this agent. Returns id, description, next config, target, and last run status.",
            inputSchema={"type": "object", "properties": {}},
        ),
        types.Tool(
            name="schedule_delete",
            description="Permanently delete a schedule by id.",
            inputSchema={
                "type": "object",
                "properties": {
                    "schedule_id": {
                        "type": "string",
                        "description": "The schedule id returned from schedule_register or schedule_list.",
                    }
                },
                "required": ["schedule_id"],
            },
        ),
        types.Tool(
            name="schedule_pause",
            description="Disable a schedule without deleting it. Can be re-enabled with schedule_resume.",
            inputSchema={
                "type": "object",
                "properties": {"schedule_id": {"type": "string"}},
                "required": ["schedule_id"],
            },
        ),
        types.Tool(
            name="schedule_resume",
            description="Re-enable a paused schedule.",
            inputSchema={
                "type": "object",
                "properties": {"schedule_id": {"type": "string"}},
                "required": ["schedule_id"],
            },
        ),
    ]


def _validate_cron(cfg: dict[str, Any]) -> None:
    allowed = {
        "year",
        "month",
        "day",
        "week",
        "day_of_week",
        "hour",
        "minute",
        "second",
    }
    unknown = set(cfg.keys()) - allowed
    if unknown:
        raise ValueError(f"Unknown cron fields: {sorted(unknown)}. Allowed: {sorted(allowed)}")


def _validate_interval(cfg: dict[str, Any]) -> None:
    allowed = {"weeks", "days", "hours", "minutes", "seconds"}
    unknown = set(cfg.keys()) - allowed
    if unknown:
        raise ValueError(f"Unknown interval fields: {sorted(unknown)}. Allowed: {sorted(allowed)}")
    if not any(cfg.get(k) for k in allowed):
        raise ValueError("interval trigger requires at least one of: weeks/days/hours/minutes/seconds")


def _validate_date(cfg: dict[str, Any]) -> None:
    if not cfg.get("run_date"):
        raise ValueError("date trigger requires 'run_date' (ISO 8601 string)")


def _validate_trigger(trigger_type: str, cfg: dict[str, Any]) -> None:
    if trigger_type == "cron":
        _validate_cron(cfg)
    elif trigger_type == "interval":
        _validate_interval(cfg)
    elif trigger_type == "date":
        _validate_date(cfg)
    else:
        raise ValueError(f"Invalid trigger_type: {trigger_type}")


def _fmt_schedule(s: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": s["id"],
        "description": s["description"],
        "prompt": s["prompt"],
        "trigger_type": s["trigger_type"],
        "trigger_config": s["trigger_config"],
        "target": {
            "type": s["target_type"],
            "id": s["target_id"],
            "label": s.get("target_label"),
        },
        "timezone": s["timezone"],
        "enabled": s["enabled"],
        "last_run_at": s.get("last_run_at"),
        "last_status": s.get("last_status"),
        "last_error": s.get("last_error"),
    }


def _text_result(payload: Any) -> list[types.TextContent]:
    return [types.TextContent(type="text", text=json.dumps(payload, ensure_ascii=False, indent=2))]


@server.call_tool()
async def call_tool(name: str, arguments: dict[str, Any]) -> list[types.TextContent]:
    try:
        if name == "schedule_register":
            trigger_type = arguments["trigger_type"]
            trigger_config = arguments["trigger_config"]
            _validate_trigger(trigger_type, trigger_config)

            s = schedule_store.create_schedule(
                description=arguments["description"],
                prompt=arguments["prompt"],
                trigger_type=trigger_type,
                trigger_config=trigger_config,
                target_type=arguments["target_type"],
                target_id=arguments["target_id"],
                target_label=arguments.get("target_label"),
                timezone=arguments.get("timezone", DEFAULT_TZ),
                requested_by=arguments.get("requested_by"),
            )
            return _text_result(
                {
                    "ok": True,
                    "message": f"Schedule registered. It will take effect within ~30s (bridge polls every 30s).",
                    "schedule": _fmt_schedule(s),
                }
            )

        if name == "schedule_list":
            items = [_fmt_schedule(s) for s in schedule_store.list_schedules()]
            return _text_result({"ok": True, "count": len(items), "schedules": items})

        if name == "schedule_delete":
            ok = schedule_store.delete_schedule(arguments["schedule_id"])
            return _text_result({"ok": ok, "deleted": ok})

        if name == "schedule_pause":
            ok = schedule_store.set_enabled(arguments["schedule_id"], False)
            return _text_result({"ok": ok, "paused": ok})

        if name == "schedule_resume":
            ok = schedule_store.set_enabled(arguments["schedule_id"], True)
            return _text_result({"ok": ok, "resumed": ok})

        return _text_result({"ok": False, "error": f"Unknown tool: {name}"})

    except Exception as e:
        return _text_result({"ok": False, "error": str(e), "error_type": type(e).__name__})


async def _run() -> None:
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options(),
        )


if __name__ == "__main__":
    asyncio.run(_run())
