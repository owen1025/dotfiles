"""python3 -m unittest discover -s docs -p 'test_claude_usage.py' -v

No credentials or network: the regression payload reproduces the 2026-09-09
case where overall quota remained but the Fable weekly quota was exhausted.
"""
import copy
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
usage = runpy.run_path(str(ROOT / "private_dot_local/bin/executable_claude-usage"))
ACCOUNT = {
    "label": "claude2", "dir": "/unused/claude-b", "kind": "claude", "state": "ok",
    "usage": {"limits": [
        {"kind": "session", "group": "session", "percent": 37},
        {"kind": "weekly_all", "group": "weekly", "percent": 52},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 100,
         "severity": "critical", "scope": {"model": {"display_name": "Fable"}},
         "resets_at": "2026-09-14T16:00:00+00:00"},
    ]},
}


class UsageDisplayTests(unittest.TestCase):
    def render(self, account, style):
        return usage["render"]({"fetched_at": 1788962076, "accounts": [account]},
                               style, usage["Ink"](False), 120)

    def test_scoped_exhaustion_is_visible_in_every_style(self):
        for style in ("bars", "panel", "compact"):
            with self.subTest(style=style):
                text = self.render(ACCOUNT, style)
                self.assertIn("Fable 사용 제한", text)
                self.assertIn("주간 Fable", text)
                self.assertNotIn("전체 사용 제한", text)
                self.assertNotIn("토큰 만료", text)
                self.assertIn("52%", text)

    def test_compact_also_shows_scoped_quota_before_exhaustion(self):
        account = copy.deepcopy(ACCOUNT)
        account["usage"]["limits"][2]["percent"] = 95
        text = self.render(account, "compact")
        self.assertIn("주간 Fable", text)
        self.assertIn("95%", text)
        self.assertNotIn("사용 제한", text)

    def test_global_exhaustion_is_distinct_from_model_exhaustion(self):
        account = copy.deepcopy(ACCOUNT)
        account["usage"]["limits"][1]["percent"] = 100
        self.assertEqual(usage["limit_warning"](account), "⚠ 전체 사용 제한 · 주간 전체 소진")

    def test_legacy_model_quota_is_not_hidden(self):
        account = copy.deepcopy(ACCOUNT)
        account["usage"] = {"seven_day": {"utilization": 52},
                            "seven_day_opus": {"utilization": 100}}
        text = self.render(account, "compact")
        self.assertIn("주간 Opus", text)
        self.assertIn("Opus 사용 제한", text)

    def test_authentication_error_does_not_claim_quota_exhaustion(self):
        account = copy.deepcopy(ACCOUNT)
        account["state"] = "token_expired"
        self.assertIsNone(usage["limit_warning"](account))
        self.assertIn("토큰 만료", self.render(account, "bars"))

    def test_cached_times_stay_truthful_when_read_later(self):
        for style in ("bars", "panel", "compact"):
            with self.subTest(style=style):
                with patch("time.time", return_value=1788962076):
                    first = self.render(ACCOUNT, style)
                with patch("time.time", return_value=1788962076 + 86400):
                    later = self.render(ACCOUNT, style)
                self.assertEqual(first, later)
                self.assertIn("09/09", first)
                self.assertIn("조회", first)
                self.assertNotIn("방금", first)
                self.assertNotIn("후 초기화", first)

    def test_chatgpt_row_keeps_its_existing_quota(self):
        account = {"kind": "chatgpt", "label": "chatgpt", "dir": "/unused/codex",
                   "state": "ok", "rows": [{"name": "주간", "group": "weekly", "percent": 15,
                                               "severity": "normal", "resets_at": None}]}
        text = self.render(account, "compact")
        self.assertIn("15%", text)
        self.assertNotIn("Fable", text)


class ShellCacheTests(unittest.TestCase):
    def startup(self, age):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "cache"
            cache.mkdir()
            state = cache / "state.json"
            state.write_text("{}")
            os.utime(state, (time.time() - age, time.time() - age))
            (cache / "render-bars-120.txt").write_text("CACHED_USAGE\n")
            # A fake command detects the refresh handoff without loading any credentials.
            script = root / "claude-usage"
            script.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$REFRESH_CAPTURE"\n')
            script.chmod(0o755)
            env = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                   "CLAUDE_USAGE_STARTUP": "0", "CLAUDE_USAGE_CACHE": str(cache),
                   "CLAUDE_USAGE_TTL": "300", "CLAUDE_USAGE_STALE_MAX": "86400",
                   "CLAUDE_USAGE_STYLE": "bars", "REFRESH_CAPTURE": str(root / "refresh")}
            code = 'source "$1"; COLUMNS=120; cat() { print BAD_CAT_WRAPPER; }; _claude_usage_startup'
            result = subprocess.run(["zsh", "-f", "-c", code, "test", str(ROOT / "dot_claude-accounts.zsh")],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("BAD_CAT_WRAPPER", result.stdout)
            for _ in range(100):
                if age < 300 or (root / "refresh").exists():
                    break
                time.sleep(.01)
            refreshed = (root / "refresh").read_text() if (root / "refresh").exists() else ""
            return result.stdout, refreshed

    def test_fresh_cache_does_not_refresh(self):
        text, refreshed = self.startup(5)
        self.assertIn("CACHED_USAGE", text)
        self.assertNotIn("이전 조회값", text)
        self.assertEqual(refreshed, "")

    def test_stale_cache_is_explicit_and_refresh_uses_locking_path(self):
        text, refreshed = self.startup(600)
        self.assertIn("CACHED_USAGE", text)
        self.assertIn("이전 조회값", text)
        self.assertIn("--startup --quiet", refreshed)

    def test_expired_cache_is_hidden(self):
        text, refreshed = self.startup(90000)
        self.assertNotIn("CACHED_USAGE", text)
        self.assertIn("오래된 사용량 숨김", text)
        self.assertIn("--startup --quiet", refreshed)


if __name__ == "__main__":
    unittest.main()
