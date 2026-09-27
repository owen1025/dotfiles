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
LIVE = usage["render"].__globals__   # run_path 는 사본을 돌려준다 — 목은 함수가 실제로 보는 전역에 건다
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


class OfflineCacheTests(unittest.TestCase):
    """2026-09-20: 리부트 직후 첫 셸이 Wi-Fi 결합보다 먼저 떠 네 계정이 URLError 로 굳었다.

    실패는 캐시를 덮지 않아야 한다 — 덮으면 TTL 동안 새 셸마다 '조회 실패' 가 그려진다.
    """
    OFFLINE = {"label": "claude", "dir": "/unused/claude", "kind": "claude",
               "state": "offline", "error": "DNS 실패"}

    def cached(self, **over):
        account = copy.deepcopy(ACCOUNT)
        account.update(label="claude", dir="/unused/claude", **over)
        return {"fetched_at": 1788962076, "accounts": [account]}

    def test_total_outage_never_touches_the_cache(self):
        state, cacheable = usage["merge_offline"]([dict(self.OFFLINE)], self.cached())
        self.assertFalse(cacheable)
        self.assertTrue(state["offline"])
        self.assertEqual(state["accounts"][0]["state"], "ok")
        self.assertEqual(state["fetched_at"], 1788962076)     # 조회 시각을 위조하지 않는다

    def test_cold_outage_is_reported_but_still_not_cached(self):
        state, cacheable = usage["merge_offline"]([dict(self.OFFLINE)], None)
        self.assertFalse(cacheable)
        self.assertIn("네트워크 없음", usage["render"](state, "bars", usage["Ink"](False), 120))

    def test_partial_outage_keeps_the_last_good_row(self):
        alive = copy.deepcopy(ACCOUNT)
        results = [dict(self.OFFLINE), alive]
        state, cacheable = usage["merge_offline"](results, self.cached())
        self.assertTrue(cacheable)
        self.assertEqual([a["state"] for a in state["accounts"]], ["ok", "ok"])
        self.assertEqual(state["accounts"][0]["as_of"], 1788962076)

    def test_success_clears_the_offline_marker(self):
        state, cacheable = usage["merge_offline"]([copy.deepcopy(ACCOUNT)], self.cached())
        self.assertTrue(cacheable)
        self.assertNotIn("offline", state)

    def test_server_errors_are_still_reported_as_failures(self):
        broken = {"label": "claude", "dir": "/unused/claude", "state": "error", "error": "HTTP 500"}
        state, cacheable = usage["merge_offline"]([broken], self.cached())
        self.assertTrue(cacheable)                            # 서버가 답한 실패는 사실이므로 캐시한다
        self.assertIn("조회 실패 (HTTP 500)", usage["render"](state, "bars", usage["Ink"](False), 120))

    def test_transport_errors_say_what_broke(self):
        import socket as _socket
        import urllib.error as _urlerr
        cases = {_socket.gaierror(8, "nodename nor servname provided"): "DNS 실패",
                 ConnectionRefusedError(61, "Connection refused"): "연결 거부",
                 TimeoutError(): "타임아웃"}
        for reason, expected in cases.items():
            with self.subTest(expected=expected):
                self.assertEqual(usage["_transport_error"](_urlerr.URLError(reason)), expected)

    def test_unreachable_api_leaves_the_good_render_in_place(self):
        """실제 전송 실패를 일으켜(닫힌 포트) 캐시가 그대로인지 끝단에서 확인한다."""
        import json as _json
        import socket as _socket
        with _socket.socket() as probe:                        # 지금 아무도 안 듣는 포트
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache, config = root / "cache", root / "claude"
            cache.mkdir(), config.mkdir()
            (config / ".credentials.json").write_text(_json.dumps(
                {"claudeAiOauth": {"accessToken": "unused", "expiresAt": (time.time() + 3600) * 1000}}))
            good = {"fetched_at": time.time() - 60,
                    "accounts": [{**copy.deepcopy(ACCOUNT), "label": "claude", "dir": str(config)}]}
            (cache / "state.json").write_text(_json.dumps(good))
            (cache / "render-bars-120.txt").write_text("GOOD_RENDER\n")
            before = (cache / "state.json").stat().st_mtime
            env = {**os.environ, "CLAUDE_USAGE_CACHE": str(cache),
                   "CLAUDE_USAGE_ACCOUNTS": f"claude:{config}", "CLAUDE_USAGE_CHATGPT": "0",
                   "CLAUDE_USAGE_API": f"http://127.0.0.1:{port}", "CLAUDE_USAGE_RETRY": "0",
                   "CLAUDE_USAGE_TIMEOUT": "2", "NO_COLOR": "1"}
            result = subprocess.run(
                ["python3", str(ROOT / "private_dot_local/bin/executable_claude-usage"),
                 "--refresh", "--style", "bars", "--width", "120", "--no-color"],
                env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("네트워크 없음", result.stdout)
            self.assertIn("52%", result.stdout)                # 마지막 성공값은 그대로 보인다
            self.assertNotIn("조회 실패", result.stdout)
            self.assertEqual((cache / "render-bars-120.txt").read_text(), "GOOD_RENDER\n")
            self.assertEqual((cache / "state.json").stat().st_mtime, before)
            self.assertEqual(_json.loads((cache / "state.json").read_text()), good)


class TokenStateTests(unittest.TestCase):
    """2026-09-27: 유휴 계정(access token 8h 만 만료)을 "토큰 만료" 로 그려 재로그인하게 만들었다.

    진짜 로그인 만료(CLI 가 refresh 거절을 겪어 refreshToken 을 비움 · 서버 401)만 /login 을 안내한다.
    """
    NOW = 1790000000
    LIVE = {"accessToken": "a", "refreshToken": "r", "expiresAt": (NOW + 3600) * 1000,
            "refreshTokenExpiresAt": (NOW + 30 * 86400) * 1000}

    def fetch(self, oauth, source="keychain", http=(200, {"limits": []})):
        with patch.dict(LIVE, {"_creds": lambda _d: (oauth, source),
                                "_get": lambda *_a: http}), \
                patch("time.time", return_value=self.NOW):
            return usage["fetch_account"]("claude3", "/unused/claude-c", 1)

    def test_expired_access_token_with_live_refresh_is_idle(self):
        rec = self.fetch({**self.LIVE, "expiresAt": (self.NOW - 60) * 1000})
        self.assertEqual(rec["state"], "idle")
        text = usage["render"]({"fetched_at": self.NOW, "accounts": [rec]}, "bars", usage["Ink"](False), 120)
        self.assertIn("유휴", text)
        self.assertIn("재로그인 불필요", text)
        self.assertNotIn("토큰 만료", text)
        self.assertNotIn("/login", text)

    def test_refresh_token_the_cli_marked_dead_needs_login(self):
        rec = self.fetch({**self.LIVE, "refreshToken": "", "expiresAt": (self.NOW - 60) * 1000})
        self.assertEqual((rec["state"], rec["error"]), ("login_expired", "refresh 토큰 폐기"))
        text = usage["render"]({"fetched_at": self.NOW, "accounts": [rec]}, "compact", usage["Ink"](False), 120)
        self.assertIn("`claude3` 실행 후 /login", text)

    def test_expired_refresh_token_needs_login(self):
        rec = self.fetch({**self.LIVE, "expiresAt": (self.NOW - 60) * 1000,
                          "refreshTokenExpiresAt": (self.NOW - 1) * 1000})
        self.assertEqual(rec["state"], "login_expired")

    def test_server_rejecting_a_live_token_needs_login(self):
        rec = self.fetch(dict(self.LIVE), http=(401, None))
        self.assertEqual((rec["state"], rec["error"]), ("login_expired", "HTTP 401"))

    def test_locked_keychain_is_not_reported_as_logged_out(self):
        rec = self.fetch(None, source="locked")
        self.assertEqual(rec["state"], "keychain_locked")

    def test_keychain_wins_over_a_later_expiring_file(self):
        """hermes 가 회전시켜 파일에만 쓴 포크(09-26)를 CLI 는 안 본다 — 패널도 안 본다."""
        keychain = {"accessToken": "cli", "expiresAt": 1}
        fork = {"accessToken": "hermes-fork", "expiresAt": 9_999_999_999_999}
        with patch.dict(LIVE, {"_keychain_lookup": lambda _d: ([keychain], False),
                                "_oauth_from_file": lambda _d: [fork]}):
            self.assertEqual(usage["_creds"]("/unused"), (keychain, "keychain"))
        with patch.dict(LIVE, {"_keychain_lookup": lambda _d: ([], True),
                                "_oauth_from_file": lambda _d: [fork]}):
            self.assertEqual(usage["_creds"]("/unused"), (None, "locked"))
        with patch.dict(LIVE, {"_keychain_lookup": lambda _d: ([], False),
                                "_oauth_from_file": lambda _d: [fork]}):
            self.assertEqual(usage["_creds"]("/unused"), (fork, "file"))   # 키체인에 항목이 없을 때만

    def test_chatgpt_idle_and_rejected(self):
        import base64 as _b64
        import json as _json

        def jwt(exp):
            body = _b64.urlsafe_b64encode(_json.dumps({"exp": exp}).encode()).decode().rstrip("=")
            return f"h.{body}.s"
        with tempfile.TemporaryDirectory() as home:
            auth = Path(home) / "auth.json"
            auth.write_text(_json.dumps({"tokens": {"access_token": jwt(time.time() - 60),
                                                    "refresh_token": "r"}}))
            self.assertEqual(usage["fetch_chatgpt_account"]("chatgpt", home, 1)["state"], "idle")
            auth.write_text(_json.dumps({"tokens": {"access_token": jwt(time.time() + 3600)}}))
            with patch.dict(LIVE, {"_http_get": lambda *_a: (401, None)}):
                rec = usage["fetch_chatgpt_account"]("chatgpt", home, 1)
            self.assertEqual(rec["state"], "login_expired")
            self.assertIn("`codex login`", usage["problem_of"](rec)[1])


class IdleCarryTests(unittest.TestCase):
    """유휴 계정은 숫자를 지우지 않고 직전 성공값을 '언제 값인지' 와 함께 들고 간다."""

    def prev(self, age):
        account = {**copy.deepcopy(ACCOUNT), "label": "claude3", "dir": "/unused/claude-c"}
        return {"fetched_at": time.time() - age, "accounts": [account]}

    IDLE = {"label": "claude3", "dir": "/unused/claude-c", "kind": "claude", "state": "idle"}

    def test_idle_keeps_last_values_with_a_note_in_every_style(self):
        state, cacheable = usage["merge_offline"]([dict(self.IDLE)], self.prev(3600))
        self.assertTrue(cacheable)
        acct = state["accounts"][0]
        self.assertEqual((acct["state"], acct["stale"]), ("ok", "idle"))
        for style in ("bars", "panel", "compact"):
            with self.subTest(style=style):
                text = usage["render"](state, style, usage["Ink"](False), 120)
                self.assertIn("52%", text)
                self.assertIn("유휴", text)
                self.assertIn("조회값", text)

    def test_idle_values_older_than_stale_max_are_dropped(self):
        state, _ = usage["merge_offline"]([dict(self.IDLE)], self.prev(usage["STALE_MAX"] + 60))
        self.assertEqual(state["accounts"][0]["state"], "idle")

    def test_carry_survives_repeated_idle_refreshes_with_the_original_time(self):
        first, _ = usage["merge_offline"]([dict(self.IDLE)], self.prev(3600))
        second, _ = usage["merge_offline"]([dict(self.IDLE)], first)
        self.assertEqual(second["accounts"][0]["as_of"], first["accounts"][0]["as_of"])

    def test_all_locked_keychains_never_touch_the_cache(self):
        locked = {"label": "claude3", "dir": "/unused/claude-c", "state": "keychain_locked"}
        state, cacheable = usage["merge_offline"]([locked], self.prev(60))
        self.assertFalse(cacheable)
        self.assertIn("키체인을 못 엶", usage["render"](state, "bars", usage["Ink"](False), 120))

    def test_attention_follows_account_states(self):
        self.assertFalse(usage["needs_attention"](self.prev(60)))
        state, _ = usage["merge_offline"]([dict(self.IDLE)], self.prev(60))
        self.assertTrue(usage["needs_attention"](state))

    def test_quick_recheck_only_when_the_cli_actually_refreshed(self):
        """유휴가 몇 시간 이어져도 60초마다 API 를 두드리지 않는다 — 토큰이 바뀐 뒤에만."""
        idle = {**self.IDLE, "token_expires_at": 1790000000.5}
        state, _ = usage["merge_offline"]([idle], self.prev(60))
        same = ({"expiresAt": 1790000000500, "refreshToken": "r"}, "keychain")
        fresh = ({"expiresAt": 1790030000500, "refreshToken": "r"}, "keychain")
        with patch.dict(LIVE, {"_creds": lambda _d: same}):
            self.assertFalse(usage["creds_changed"](state))
        with patch.dict(LIVE, {"_creds": lambda _d: fresh}):
            self.assertTrue(usage["creds_changed"](state))
        with patch.dict(LIVE, {"_creds": lambda _d: fresh}):     # 주의 계정이 없으면 안 본다
            self.assertFalse(usage["creds_changed"](self.prev(60)))


class EventLogTests(unittest.TestCase):
    def test_only_transitions_are_logged_without_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "events.log"
            prev = {"accounts": [{"label": "claude", "dir": "/d", "state": "ok"},
                                 {"label": "claude3", "dir": "/c", "state": "ok", "stale": "idle"}]}
            results = [{"label": "claude", "dir": "/d", "state": "login_expired", "error": "refresh 토큰 폐기",
                        "cred_src": "keychain", "token_expires_at": 1790000000},
                       {"label": "claude3", "dir": "/c", "state": "idle"},
                       {"label": "chatgpt", "dir": "/x", "state": "offline"}]
            with patch.dict(LIVE, {"EVENT_LOG": str(log), "CACHE_DIR": directory}):
                usage["log_transitions"](results, prev)
                usage["log_transitions"](results, {"accounts": results})     # 같은 상태 반복 = 무기록
            lines = log.read_text().splitlines()
            self.assertEqual(len(lines), 1)
            self.assertIn("claude ok → login_expired src=keychain", lines[0])
            self.assertIn("why=refresh 토큰 폐기", lines[0])


class ShellCacheTests(unittest.TestCase):
    def startup(self, age, attention=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "cache"
            cache.mkdir()
            state = cache / "state.json"
            state.write_text("{}")
            os.utime(state, (time.time() - age, time.time() - age))
            (cache / "render-bars-120.txt").write_text("CACHED_USAGE\n")
            if attention:
                (cache / "attention").write_text("")
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
                if (age < 300 and not attention) or (root / "refresh").exists():
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

    def test_attention_rechecks_quietly_before_ttl(self):
        """유휴·로그인 만료가 있으면 5분을 안 기다린다 — /login·`claude3` 직후 다음 셸에 반영."""
        text, refreshed = self.startup(90, attention=True)
        self.assertIn("CACHED_USAGE", text)
        self.assertNotIn("이전 조회값", text)                 # 조용히 — 경고 줄 없음
        self.assertIn("--startup --quiet", refreshed)

    def test_attention_still_waits_a_minute(self):
        text, refreshed = self.startup(5, attention=True)
        self.assertEqual(refreshed, "")

    def test_no_attention_keeps_the_normal_ttl(self):
        text, refreshed = self.startup(90)
        self.assertEqual(refreshed, "")

    def test_expired_cache_is_hidden(self):
        text, refreshed = self.startup(90000)
        self.assertNotIn("CACHED_USAGE", text)
        self.assertIn("오래된 사용량 숨김", text)
        self.assertIn("--startup --quiet", refreshed)


if __name__ == "__main__":
    unittest.main()
