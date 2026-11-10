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


class AccountDiscoveryTests(unittest.TestCase):
    def test_separate_homes_show_five_and_three_accounts(self):
        """Owen의 claude4를 추가해도 하니 패널에는 하니 계정 세 개만 보인다."""
        with tempfile.TemporaryDirectory() as temp:
            for user, suffixes, expected in (
                ("owen", ("b", "c", "d"), ["claude", "claude2", "claude3", "claude4", "chatgpt"]),
                ("hani", ("b",), ["claude", "claude2", "chatgpt"]),
            ):
                home = Path(temp) / user
                for name in [".claude", ".codex", *(f".claude-{s}" for s in suffixes)]:
                    (home / name).mkdir(parents=True)
                (home / ".codex/auth.json").write_text('{"tokens":{"access_token":"fake-for-discovery"}}')
                with self.subTest(user=user), patch.dict(os.environ, {}, clear=True), patch.dict(LIVE, HOME=str(home)):
                    accounts = usage["discover_accounts"]() + usage["discover_chatgpt_accounts"]()
                    self.assertEqual([label for label, _ in accounts], expected)
                    self.assertTrue(all(Path(path).parent == home for _, path in accounts))


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
        logins = ([], True) if source == "locked" else ([(oauth, source)], False)
        with patch.dict(LIVE, {"_logins": lambda _d: logins,
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
        """이 셸의 CLI 가 읽는 로그인: 키체인을 읽을 수 있으면 키체인(09-26 hermes 포크), 잠긴 셸(SSH)에선 파일(2026-11-01).

        조회에 쓸 토큰은 따로 고른다 — TwoStoreTests.
        """
        keychain = {"accessToken": "cli", "expiresAt": 1}
        fork = {"accessToken": "hermes-fork", "expiresAt": 9_999_999_999_999}
        with patch.dict(LIVE, {"_keychain_lookup": lambda _d: ([keychain], False),
                                "_oauth_from_file": lambda _d: [fork]}):
            self.assertEqual(usage["_creds"]("/unused"), (keychain, "keychain"))
        with patch.dict(LIVE, {"_keychain_lookup": lambda _d: ([], True),
                                "_oauth_from_file": lambda _d: [fork]}):
            self.assertEqual(usage["_creds"]("/unused"), (fork, "file"))   # SSH 셸의 CLI 가 쓰는 평문 폴백
        with patch.dict(LIVE, {"_keychain_lookup": lambda _d: ([], True),
                                "_oauth_from_file": lambda _d: []}):
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
        self.assertIn("SSH 셸 키체인 잠김", usage["render"](state, "bars", usage["Ink"](False), 120))

    def test_attention_follows_account_states(self):
        self.assertFalse(usage["needs_attention"](self.prev(60)))
        state, _ = usage["merge_offline"]([dict(self.IDLE)], self.prev(60))
        self.assertTrue(usage["needs_attention"](state))

    def test_quick_recheck_only_when_the_cli_actually_refreshed(self):
        """유휴가 몇 시간 이어져도 새 셸마다 API 를 두드리지 않는다 — 토큰이 바뀐 뒤에만."""
        idle = {**self.IDLE, "token_expires_at": 1790000000.5, "cred_src": "keychain",
                "cred_sig": {"keychain": 1790000000.5}}
        state, _ = usage["merge_offline"]([idle], self.prev(60))
        self.assertEqual(state["accounts"][0]["cred_sig"], {"keychain": 1790000000.5})   # 지문도 같이 들고 간다
        same = ([({"expiresAt": 1790000000500, "refreshToken": "r"}, "keychain")], False)
        fresh = ([({"expiresAt": 1790030000500, "refreshToken": "r"}, "keychain")], False)
        with patch.dict(LIVE, {"_logins": lambda _d: same}):
            self.assertFalse(usage["creds_changed"](state))
        with patch.dict(LIVE, {"_logins": lambda _d: fresh}):
            self.assertTrue(usage["creds_changed"](state))
        with patch.dict(LIVE, {"_logins": lambda _d: fresh}):    # 주의 계정이 없으면 안 본다
            self.assertFalse(usage["creds_changed"](self.prev(60)))

    def test_recheck_compares_each_store_separately(self):
        """캐시를 쓴 셸(화면 앞 — 키체인 + 파일)과 지금 셸(SSH — 파일만)이 보는 저장소가 달라도 헛돌지 않는다."""
        now = time.time()
        idle = {**self.IDLE, "token_expires_at": now - 9000, "cred_src": "keychain",
                "cred_sig": {"keychain": now - 9000, "file": now - 600}}
        state, _ = usage["merge_offline"]([idle], self.prev(60))
        file_same = ({"expiresAt": (now - 600) * 1000, "refreshToken": "r"}, "file")
        file_new = ({"expiresAt": (now + 28800) * 1000, "refreshToken": "r"}, "file")
        with patch.dict(LIVE, {"_logins": lambda _d: ([file_same], True)}):      # SSH 셸: 키체인은 안 보인다
            self.assertFalse(usage["creds_changed"](state))
        with patch.dict(LIVE, {"_logins": lambda _d: ([file_new], True)}):       # 그 셸에서 `claude3` 를 돌렸다
            self.assertTrue(usage["creds_changed"](state))
        # 반대 방향: SSH 셸이 쓴 캐시(파일만 기록)를 화면 앞 셸이 볼 때 — 키체인의 만료된 옛 토큰은 변화가 아니다
        idle = {**self.IDLE, "token_expires_at": now - 600, "cred_src": "file", "cred_sig": {"file": now - 600}}
        state, _ = usage["merge_offline"]([idle], self.prev(60))
        old_keychain = ({"expiresAt": (now - 86400) * 1000, "refreshToken": "r"}, "keychain")
        live_keychain = ({"expiresAt": (now + 3600) * 1000, "refreshToken": "r"}, "keychain")
        with patch.dict(LIVE, {"_logins": lambda _d: ([old_keychain, file_same], False)}):
            self.assertFalse(usage["creds_changed"](state))
        with patch.dict(LIVE, {"_logins": lambda _d: ([live_keychain, file_same], False)}):
            self.assertTrue(usage["creds_changed"](state))

    def test_caches_written_before_the_per_store_signature_still_work(self):
        idle = {**self.IDLE, "token_expires_at": 1790000000.5, "cred_src": "keychain"}   # cred_sig 없음
        state, _ = usage["merge_offline"]([idle], self.prev(60))
        same = ([({"expiresAt": 1790000000500, "refreshToken": "r"}, "keychain")], False)
        fresh = ([({"expiresAt": 1790030000500, "refreshToken": "r"}, "keychain")], False)
        with patch.dict(LIVE, {"_logins": lambda _d: same}):
            self.assertFalse(usage["creds_changed"](state))
        with patch.dict(LIVE, {"_logins": lambda _d: fresh}):
            self.assertTrue(usage["creds_changed"](state))


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


class TwoStoreTests(unittest.TestCase):
    """2026-11-10: 한 계정의 로그인이 키체인과 파일에 따로 산다 — 화면 앞 터미널·launchd 의 CLI 는 키체인,
    SSH 로 붙은 tmux 의 CLI 는 파일. 예전엔 읽는 순서의 첫 저장소만 봐서, 키체인이 열리는 맥락(30분마다
    도는 hermes 크론)이 조회할 때마다 며칠 전 키체인 토큰을 보고 쓰고 있는 계정을 "유휴" 로 캐시에 덮었다.
    """
    NOW = 1790000000
    LIVE = {"refreshToken": "r", "expiresAt": (NOW + 3600) * 1000,
            "refreshTokenExpiresAt": (NOW + 30 * 86400) * 1000}
    EXPIRED = {"refreshToken": "r", "expiresAt": (NOW - 3 * 86400) * 1000,
               "refreshTokenExpiresAt": (NOW + 30 * 86400) * 1000}

    def fetch(self, keychain, file, reject=(), known=None):
        """keychain·file = 그 저장소의 로그인(None 이면 없음). reject = 서버가 401 을 주는 access token."""
        logins = [({**oauth, "accessToken": source}, source)
                  for oauth, source in ((keychain, "keychain"), (file, "file")) if oauth]
        asked = []

        def get(path, token, _timeout):
            asked.append((path, token))
            if token in reject:
                return 401, None
            return 200, ({"limits": [{"kind": "weekly_all", "group": "weekly", "percent": 41}]}
                         if path.endswith("/usage") else {"account": {"email": f"{token}@example.com"}})
        with patch.dict(LIVE, {"_logins": lambda _d: (logins, False), "_get": get}), \
                patch("time.time", return_value=self.NOW):
            return usage["fetch_account"]("claude2", "/unused/claude-b", 1, known), asked

    def test_stale_keychain_does_not_hide_a_live_file_login(self):
        rec, asked = self.fetch(self.EXPIRED, self.LIVE)
        self.assertEqual((rec["state"], rec["cred_src"]), ("ok", "file"))
        self.assertEqual({token for _, token in asked}, {"file"})       # 만료된 키체인 토큰으로는 묻지 않는다
        self.assertNotIn("login_note", rec)                             # 키체인은 유휴일 뿐 — CLI 가 알아서 갱신한다
        text = usage["render"]({"fetched_at": self.NOW, "accounts": [rec]}, "bars", usage["Ink"](False), 120)
        self.assertIn("41%", text)
        self.assertNotIn("유휴", text)

    def test_live_keychain_is_still_asked_first(self):
        rec, asked = self.fetch(self.LIVE, self.LIVE)
        self.assertEqual((rec["state"], rec["cred_src"]), ("ok", "keychain"))
        self.assertEqual({token for _, token in asked}, {"keychain"})

    def test_rejected_keychain_falls_through_but_is_not_called_healthy(self):
        """숫자는 파일 로그인으로 받되, 이 셸의 CLI(키체인)가 로그아웃이라는 건 가리지 않는다(09-26 교훈)."""
        rec, _ = self.fetch(self.LIVE, self.LIVE, reject={"keychain"})
        self.assertEqual((rec["state"], rec["cred_src"]), ("ok", "file"))
        self.assertIn("키체인 로그인 만료 (HTTP 401)", rec["login_note"])
        for style in ("bars", "panel", "compact"):
            with self.subTest(style=style):
                text = usage["render"]({"fetched_at": self.NOW, "accounts": [rec]}, style, usage["Ink"](False), 160)
                self.assertIn("41%", text)
                self.assertIn("키체인 로그인 만료", text)

    def test_dead_keychain_refresh_token_is_reported_next_to_the_numbers(self):
        rec, asked = self.fetch({**self.EXPIRED, "refreshToken": ""}, self.LIVE)
        self.assertEqual(rec["state"], "ok")
        self.assertIn("`claude2` 실행 후 /login", rec["login_note"])
        self.assertEqual({token for _, token in asked}, {"file"})

    def test_without_any_live_token_the_first_login_decides(self):
        """조회가 안 될 때의 상태는 이 셸의 CLI 가 읽는 첫 로그인이 정한다."""
        rec, asked = self.fetch(self.EXPIRED, self.EXPIRED)
        self.assertEqual((rec["state"], rec["cred_src"], asked), ("idle", "keychain", []))
        rec, _ = self.fetch({**self.EXPIRED, "refreshToken": ""}, self.EXPIRED)
        self.assertEqual((rec["state"], rec["error"]), ("login_expired", "refresh 토큰 폐기"))
        rec, _ = self.fetch(self.LIVE, self.LIVE, reject={"keychain", "file"})
        self.assertEqual((rec["state"], rec["error"]), ("login_expired", "HTTP 401"))

    def test_both_stores_are_fingerprinted(self):
        rec, _ = self.fetch(self.EXPIRED, self.LIVE)
        self.assertEqual(rec["cred_sig"], {"keychain": self.NOW - 3 * 86400, "file": self.NOW + 3600})

    def test_profile_is_not_refetched_for_the_same_token(self):
        """프로필(이메일·플랜)은 토큰이 그대로면 직전 값을 쓴다 — 새 셸이 기다리는 왕복이 절반이 된다."""
        first, asked = self.fetch(None, self.LIVE)
        self.assertEqual([path for path, _ in asked], ["/api/oauth/usage", "/api/oauth/profile"])
        self.assertEqual(first["email"], "file@example.com")
        again, asked = self.fetch(None, self.LIVE, known=first)
        self.assertEqual([path for path, _ in asked], ["/api/oauth/usage"])
        self.assertEqual((again["email"], again["plan"]), (first["email"], first["plan"]))
        relogin = {**self.LIVE, "expiresAt": (self.NOW + 7200) * 1000}     # 다른 토큰 = 다른 계정일 수 있다
        _, asked = self.fetch(None, relogin, known=first)
        self.assertEqual([path for path, _ in asked], ["/api/oauth/usage", "/api/oauth/profile"])


class RateLimitTests(unittest.TestCase):
    """2026-11-10: 사용량 API 는 요청 제한이 빡빡하다 — 한 계정에 2분 동안 7~11번 묻자 HTTP 429 +
    `Retry-After: 251~276`. 예전엔 429 가 "조회 실패" 로 캐시돼 숫자가 통째로 사라졌다.
    """
    NOW = 1790000000
    LIVE = {"accessToken": "a", "refreshToken": "r", "expiresAt": (NOW + 3600) * 1000}

    def fetch(self, http, known=None, oauth=None, now=None):
        asked = []

        def get(path, _token, _timeout):
            asked.append(path)
            return http
        with patch.dict(LIVE, {"_logins": lambda _d: ([(oauth or self.LIVE, "file")], False), "_get": get}), \
                patch("time.time", return_value=now or self.NOW):
            return usage["fetch_account"]("claude", "/unused/claude", 1, known), asked

    def carried(self, rec):
        good = {**copy.deepcopy(ACCOUNT), "label": "claude", "dir": "/unused/claude",
                "token_expires_at": self.NOW + 3600}
        with patch("time.time", return_value=self.NOW):
            state, cacheable = usage["merge_offline"]([rec], {"fetched_at": self.NOW - 90, "accounts": [good]})
        self.assertTrue(cacheable)
        return state

    def test_rate_limit_keeps_the_numbers_and_says_when_it_ends(self):
        rec, _ = self.fetch((429, {"retry_after": 251.0}))
        self.assertEqual((rec["state"], rec["retry_at"]), ("throttled", self.NOW + 251))
        state = self.carried(rec)
        acct = state["accounts"][0]
        self.assertEqual((acct["state"], acct["stale"], acct["retry_at"]), ("ok", "throttled", self.NOW + 251))
        self.assertFalse(usage["needs_attention"](state))       # 사용자가 손쓸 일이 아니다
        for style in ("bars", "panel", "compact"):
            with self.subTest(style=style):
                text = usage["render"](state, style, usage["Ink"](False), 160)
                self.assertIn("52%", text)                      # 직전 값이 그대로 보인다
                self.assertIn("조회 제한", text)
                self.assertNotIn("조회 실패", text)

    def test_missing_or_zero_retry_after_backs_off_five_minutes(self):
        for body in (None, {"retry_after": 0.0}):
            with self.subTest(body=body):
                rec, _ = self.fetch((429, body))
                self.assertEqual(rec["retry_at"], self.NOW + 300)

    def test_account_is_not_asked_again_until_the_server_allows(self):
        rec, _ = self.fetch((429, {"retry_after": 251.0}))
        known = self.carried(rec)["accounts"][0]
        again, asked = self.fetch((200, {"limits": []}), known=known, now=self.NOW + 120)
        self.assertEqual((again["state"], asked), ("throttled", []))
        self.assertEqual(again["retry_at"], self.NOW + 251)     # 기한을 뒤로 밀지 않는다
        after, asked = self.fetch((200, {"limits": []}), known=known, now=self.NOW + 252)
        self.assertEqual((after["state"], asked[0]), ("ok", "/api/oauth/usage"))
        self.assertNotIn("retry_at", self.carried(after)["accounts"][0])

    def test_a_new_login_is_asked_right_away(self):
        """제한은 토큰 단위다 — 그 사이 로그인이 바뀌었으면 기다릴 이유가 없다."""
        rec, _ = self.fetch((429, {"retry_after": 251.0}))
        known = self.carried(rec)["accounts"][0]
        relogin = {**self.LIVE, "expiresAt": (self.NOW + 9000) * 1000}
        _, asked = self.fetch((200, {"limits": []}), known=known, oauth=relogin, now=self.NOW + 60)
        self.assertEqual(asked[0], "/api/oauth/usage")

    def test_rate_limit_without_earlier_values_is_explained(self):
        rec, _ = self.fetch((429, {"retry_after": 251.0}))
        text = usage["render"]({"fetched_at": self.NOW, "accounts": [rec]}, "bars", usage["Ink"](False), 120)
        self.assertIn("조회 제한 (HTTP 429)", text)
        self.assertIn("계정 이상 없음", text)
        self.assertNotIn("/login", text)

    def test_end_to_end_backoff_survives_across_shells(self):
        box = Sandbox(self, cache_age=600, status=429, retry_after=251)
        first, _ = box.run("--startup")
        self.assertIn("52%", first.stdout)
        self.assertIn("조회 제한", first.stdout)
        self.assertAlmostEqual(box.state()["accounts"][0]["retry_at"], time.time() + 251, delta=15)
        box.settle()
        state = box.state()                                     # 1분 뒤 다시 연 셸
        state["fetched_at"] -= 90
        box.seed(state)
        box.api.status = 200
        second, _ = box.run("--startup")
        self.assertIn("52%", second.stdout)
        self.assertIn("조회 제한", second.stdout)
        self.assertEqual(box.api.usage_hits(), 1)               # 서버가 막아 둔 동안은 다시 묻지 않았다
        box.settle()

    def test_back_to_back_manual_refreshes_ask_once(self):
        """`claude-usage -r` 을 연달아 쳐도(또는 여러 도구가 겹쳐 불러도) 10초 안에는 API 를 한 번만 부른다."""
        box = Sandbox(self, cache_age=600, percent=77)
        for _ in range(3):
            result, _ = box.run("--refresh")
            self.assertIn("77%", result.stdout)
        self.assertEqual(box.api.usage_hits(), 1)
        box.login()                                             # 그 사이 로그인이 바뀌면 기다리지 않는다
        box.run("--refresh")
        self.assertEqual(box.api.usage_hits(), 2)


class FakeUsageAPI:
    """`CLAUDE_USAGE_API` 로 물리는 가짜 Anthropic — 사용률·지연을 정하고 요청 수를 센다."""

    def __init__(self, percent=77, delay=0.0, status=200, retry_after=None):
        import http.server
        import json as _json
        import threading
        outer = self
        self.percent, self.delay, self.hits = percent, delay, []
        self.status, self.retry_after = status, retry_after

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                outer.hits.append(self.path)
                time.sleep(outer.delay)
                body = ({"limits": [{"kind": "weekly_all", "group": "weekly", "percent": outer.percent}]}
                        if self.path.endswith("/usage") else {"account": {"email": "fake@example.com"}})
                if outer.status != 200:
                    body = {"error": {"type": "rate_limit_error", "message": "Rate limited. Please try again later."}}
                raw = _json.dumps(body).encode()
                self.send_response(outer.status)
                if outer.retry_after is not None:
                    self.send_header("Retry-After", str(outer.retry_after))
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                try:
                    self.wfile.write(raw)
                except OSError:
                    pass

            def log_message(self, *_args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def usage_hits(self):
        return sum(1 for path in self.hits if path.endswith("/usage"))

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class Sandbox:
    """임시 홈 하나: 계정 디렉터리(파일 로그인) + 사용량 캐시 + 가짜 API. 실제 크레덴셜·네트워크는 안 쓴다."""
    SCRIPT = ROOT / "private_dot_local/bin/executable_claude-usage"

    def __init__(self, test, cache_age=600, cached=None, login_age=3600, **api):
        import json as _json
        self.json = _json
        self.tmp = tempfile.TemporaryDirectory()
        test.addCleanup(self.tmp.cleanup)
        self.api = FakeUsageAPI(**api)
        test.addCleanup(self.api.close)
        self.root = Path(self.tmp.name)
        self.cache, self.config = self.root / "cache", self.root / ".claude"
        self.cache.mkdir(), self.config.mkdir()
        self.login(age=login_age)
        if cache_age is not None:
            account = cached or {**copy.deepcopy(ACCOUNT), "label": "claude"}
            self.seed({"fetched_at": time.time() - cache_age, "accounts": [{**account, "dir": str(self.config)}]})
        # HOME 은 그대로 둔다: 계정 디렉터리가 진짜 ~/.claude 가 아니어야 키체인의 실제 로그인을 건드리지 않고
        # (서비스명이 경로 해시라 "없음" 이 된다), macOS 시스템 파이썬은 HOME 아래에 바이트코드 캐시를 쓴다.
        self.env = {**os.environ, "CLAUDE_USAGE_CACHE": str(self.cache),
                    "CLAUDE_USAGE_ACCOUNTS": f"claude:{self.config}", "CLAUDE_USAGE_CHATGPT": "0",
                    "CLAUDE_USAGE_API": self.api.url, "CLAUDE_USAGE_RETRY": "0", "CLAUDE_USAGE_TIMEOUT": "5",
                    "NO_COLOR": "1"}
        for name in ("CLAUDE_USAGE_TTL", "CLAUDE_USAGE_WAIT", "CLAUDE_USAGE_ATTENTION_TTL", "CLAUDE_USAGE_STYLE",
                     "CLAUDE_USAGE_STARTUP", "CLAUDE_USAGE_MIN_INTERVAL", "CODEX_HOME", "XDG_CACHE_HOME"):
            self.env.pop(name, None)

    def login(self, age=0, expires_in=3600, refresh="r"):
        """CLI 가 로그인·토큰 갱신을 끝냈다 — `.credentials.json` 을 다시 쓴다."""
        path = self.config / ".credentials.json"
        expires_at = (time.time() + expires_in) * 1000
        path.write_text(self.json.dumps({"claudeAiOauth": {
            "accessToken": "fake", "refreshToken": refresh, "expiresAt": expires_at}}))
        os.utime(path, (time.time() - age,) * 2)
        return expires_at / 1000

    def seed(self, state):
        path = self.cache / "state.json"
        path.write_text(self.json.dumps(state))
        os.utime(path, (state["fetched_at"],) * 2)
        (self.cache / "render-bars-120.txt").write_text("CACHED_RENDER\n")

    def state(self):
        return self.json.loads((self.cache / "state.json").read_text())

    def run(self, *args, **env):
        began = time.time()
        result = subprocess.run(["python3", str(self.SCRIPT), *args, "--style", "bars", "--width", "120"],
                                env={**self.env, **env}, capture_output=True, text=True, timeout=30)
        return result, time.time() - began

    def wait_until(self, condition, timeout=8.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if condition():
                return True
            time.sleep(0.02)
        return False

    def settle(self):
        """백그라운드 갱신이 끝날 때까지(락이 사라질 때까지) — 임시 디렉터리를 지우기 전에."""
        self.wait_until(lambda: not (self.cache / "refresh.lock").exists())


class FreshPanelTests(unittest.TestCase):
    """2026-11-10: "토큰 사용량을 실시간으로 보고 싶은데 반영까지 한참 걸린다".

    예전엔 TTL 5분에 옛 값을 찍고 백그라운드로 갱신해서, 새 값은 늘 그다음 셸에서야 보였다.
    이제 낡은 캐시를 만난 셸이 새 값을 받아 **자기 화면에** 찍는다.
    """

    def test_stale_cache_is_refreshed_in_this_very_shell(self):
        box = Sandbox(self, cache_age=600, percent=77)
        result, _ = box.run("--startup")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("77%", result.stdout)                    # 새 값
        self.assertNotIn("52%", result.stdout)                 # 캐시에 있던 10분 전 값이 아니다
        self.assertNotIn("이전 조회값", result.stdout)
        self.assertEqual(box.state()["accounts"][0]["usage"]["limits"][0]["percent"], 77)
        self.assertIn("77%", (box.cache / "render-bars-120.txt").read_text())    # 다음 셸은 cat 만 한다
        box.settle()

    def test_fresh_cache_is_printed_without_asking_the_api(self):
        box = Sandbox(self, cache_age=5)
        result, _ = box.run("--startup")
        self.assertIn("52%", result.stdout)
        self.assertEqual(box.api.hits, [])
        self.assertFalse((box.cache / "refresh.lock").exists())

    def test_a_slow_api_never_holds_the_shell_past_the_budget(self):
        box = Sandbox(self, cache_age=600, percent=77, delay=1.5)
        result, took = box.run("--startup", CLAUDE_USAGE_WAIT="0.3")
        self.assertLess(took, 1.2)                             # 상한 0.3초 + 파이썬 기동, 1.5초를 다 기다리지 않는다
        self.assertIn("52%", result.stdout)                    # 이전 값을 찍되
        self.assertIn("이전 조회값", result.stdout)            # 이전 값이라고 밝힌다
        self.assertTrue(box.wait_until(                        # 갱신은 셸이 돌아간 뒤에도 마저 돈다
            lambda: box.state()["accounts"][0]["usage"]["limits"][0]["percent"] == 77))
        box.settle()
        # 방금 한 조회가 상한보다 느렸다 → 다음 셸은 아예 기다리지 않는다(API 가 느린 동안 셸마다 상한을 채우지 않는다)
        self.assertFalse(self.patience(box, CLAUDE_USAGE_WAIT="0.3"))
        self.assertTrue(self.patience(box, CLAUDE_USAGE_WAIT="10"))    # 사용량 + 프로필 = 3초쯤 걸렸다
        # 오래전 조회가 느렸던 건 지금 사정이 아니다 — 13분 전의 느린 조회 때문에 새 셸이 옛 값을 찍으면 안 된다
        attempt = box.json.loads((box.cache / "attempt.json").read_text())
        (box.cache / "attempt.json").write_text(box.json.dumps({**attempt, "at": time.time() - 800}))
        self.assertTrue(self.patience(box, CLAUDE_USAGE_WAIT="0.3"))

    def patience(self, box, **env):
        out = subprocess.run(
            ["python3", "-c", "import runpy, sys; print(runpy.run_path(sys.argv[1])['worth_waiting']())",
             str(box.SCRIPT)], env={**box.env, **env}, capture_output=True, text=True, timeout=10)
        return out.stdout.strip() == "True"

    def test_login_shows_up_in_the_next_shell_even_inside_the_ttl(self):
        """"새로 로그인하고 새 셸을 열어도 반영이 안 된다" — 5초 전 캐시가 '로그인 만료' 라도 기다리지 않는다."""
        box = Sandbox(self, cache_age=None, percent=77)
        dead = box.login(age=3600, expires_in=-60, refresh="")  # CLI 가 refresh 거절을 겪은 로그인
        box.seed({"fetched_at": time.time() - 3, "accounts": [{
            "label": "claude", "dir": str(box.config), "kind": "claude", "state": "login_expired",
            "error": "refresh 토큰 폐기", "cred_src": "file", "token_expires_at": dead, "cred_sig": {"file": dead}}]})
        before, _ = box.run("--startup")                       # 로그인 전: 캐시가 신선하니 그대로 찍는다
        self.assertIn("로그인 만료", before.stdout)
        self.assertEqual(box.api.hits, [])
        box.login()                                            # /login 이 끝났다 — 캐시는 아직 3초 전 것이다
        after, _ = box.run("--startup")
        self.assertIn("77%", after.stdout)
        self.assertNotIn("로그인 만료", after.stdout)
        self.assertFalse((box.cache / "attention").exists())
        box.settle()

    def test_unreachable_api_does_not_block_and_keeps_the_last_values(self):
        box = Sandbox(self, cache_age=600)
        box.api.close()                                        # 아무도 안 듣는 포트 = 연결 거부
        for attempt in range(2):
            with self.subTest(attempt=attempt):
                result, took = box.run("--startup", CLAUDE_USAGE_WAIT="3")
                self.assertLess(took, 2.0)                     # 실패가 확인되는 즉시 돌아온다(상한을 채우지 않는다)
                self.assertIn("네트워크 없음", result.stdout)
                self.assertIn("52%", result.stdout)
                box.settle()
        self.assertEqual((box.cache / "render-bars-120.txt").read_text(), "CACHED_RENDER\n")

    def test_shells_opened_together_share_one_refresh(self):
        """tmux 가 창 여러 개를 한꺼번에 띄워도 API 는 한 번만 부른다 — 나머지는 그 갱신을 기다린다."""
        import concurrent.futures as _futures
        box = Sandbox(self, cache_age=600, percent=77, delay=0.3)
        with _futures.ThreadPoolExecutor(4) as pool:
            results = list(pool.map(lambda _i: box.run("--startup")[0], range(4)))
        for result in results:
            self.assertIn("77%", result.stdout)
        self.assertEqual(box.api.usage_hits(), 1)
        box.settle()

    def test_prefetch_returns_at_once_and_the_panel_joins_it(self):
        """`.zshrc` 맨 위의 선조회(`--startup --quiet`)는 갱신만 띄우고, 맨 끝의 패널이 그 갱신을 이어받는다."""
        box = Sandbox(self, cache_age=600, percent=77, delay=1.0)
        quiet, took = box.run("--startup", "--quiet")
        self.assertEqual(quiet.stdout, "")
        self.assertLess(took, 0.7)                             # API(1초)를 기다리지 않았다
        panel, _ = box.run("--startup", CLAUDE_USAGE_WAIT="6")  # 사용량 + 프로필 = 2초쯤 걸린다
        self.assertIn("77%", panel.stdout)
        self.assertEqual(box.api.usage_hits(), 1)              # 패널이 조회를 또 띄우지 않았다
        box.settle()

    def test_a_lock_left_by_a_dead_refresh_does_not_stall_the_next_one(self):
        box = Sandbox(self, cache_age=600, percent=77)
        dead = subprocess.Popen(["true"])
        dead.wait()
        (box.cache / "refresh.lock").write_text(f"{dead.pid} {time.time()}")
        result, took = box.run("--startup")
        self.assertIn("77%", result.stdout)
        self.assertLess(took, 2.5)
        box.settle()

    def test_manual_call_also_shows_current_values(self):
        box = Sandbox(self, cache_age=600, percent=77)
        result, _ = box.run()                                  # 플래그 없는 `claude-usage`
        self.assertIn("77%", result.stdout)
        box.settle()

    def test_cache_older_than_a_day_is_hidden_when_the_refresh_is_late(self):
        box = Sandbox(self, cache_age=90000, delay=1.5)
        result, _ = box.run("--startup", CLAUDE_USAGE_WAIT="0.2")
        self.assertNotIn("52%", result.stdout)
        self.assertIn("오래된 사용량 숨김", result.stdout)
        box.settle()


class ShellCacheTests(unittest.TestCase):
    """zsh 쪽 판정: 신선하면 렌더 캐시를 cat 만 하고, 아니면 claude-usage 에 넘겨 새 값을 찍게 한다."""

    def startup(self, age, attention=False, login=None, render=True, call="_claude_usage_startup", flags=(),
                background=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "cache"
            cache.mkdir()
            state = cache / "state.json"
            state.write_text("{}")
            os.utime(state, (time.time() - age, time.time() - age))
            if render:
                (cache / "render-bars-120.txt").write_text("CACHED_USAGE\n")
            if attention:
                (cache / "attention").write_text("")
            if login:                                           # 캐시보다 나중에 고쳐진 로그인 파일
                path = root / login
                path.parent.mkdir(parents=True)
                path.write_text("{}")
            # 가짜 claude-usage: 넘겨받은 인자를 적고, 새로 조회한 패널인 척 한 줄 찍는다.
            script = root / "claude-usage"
            script.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$REFRESH_CAPTURE"\necho FRESH_FROM_TOOL\n')
            script.chmod(0o755)
            env = {**os.environ, "HOME": str(root), "PATH": str(root) + os.pathsep + os.environ["PATH"],
                   "CLAUDE_USAGE_STARTUP": "0", "CLAUDE_USAGE_CACHE": str(cache),
                   "CLAUDE_USAGE_STYLE": "bars", "REFRESH_CAPTURE": str(root / "refresh")}
            for name in ("CLAUDE_USAGE_TTL", "CLAUDE_USAGE_ATTENTION_TTL", "CODEX_HOME", "CLAUDECODE"):
                env.pop(name, None)
            env.update(dict(flags))
            code = f'source "$1"; COLUMNS=120; cat() {{ print BAD_CAT_WRAPPER; }}; {call}'
            result = subprocess.run(["zsh", "-f", "-c", code, "test", str(ROOT / "dot_claude-accounts.zsh")],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("BAD_CAT_WRAPPER", result.stdout)
            for _ in range(200 if background else 0):           # 백그라운드로 보낸 호출이 도착할 때까지
                if (root / "refresh").exists() and (root / "refresh").read_text():
                    break
                time.sleep(.01)
            handed = (root / "refresh").read_text() if (root / "refresh").exists() else ""
            return result.stdout, handed

    def test_fresh_cache_is_printed_without_starting_python(self):
        text, handed = self.startup(5)
        self.assertEqual(text, "CACHED_USAGE\n")
        self.assertEqual(handed, "")

    def test_stale_cache_is_handed_over_instead_of_printed(self):
        """60초보다 낡았으면 옛 렌더를 찍지 않는다 — claude-usage 가 새로 조회해서 찍는다(기다리는 호출)."""
        text, handed = self.startup(90)
        self.assertEqual(text, "FRESH_FROM_TOOL\n")
        self.assertEqual(handed, "--startup --style bars --width 120\n")
        self.assertNotIn("--quiet", handed)

    def test_cache_younger_than_a_minute_is_not_refetched(self):
        """사용량 API 는 요청 제한이 빡빡하다 — 셸을 연달아 열어도 1분에 한 번보다 자주 묻지 않는다."""
        text, handed = self.startup(45)
        self.assertEqual((text, handed), ("CACHED_USAGE\n", ""))

    def test_ttl_is_configurable(self):
        text, handed = self.startup(90, flags={"CLAUDE_USAGE_TTL": "300"}.items())
        self.assertEqual((text, handed), ("CACHED_USAGE\n", ""))

    def test_new_login_file_beats_the_ttl(self):
        """방금 로그인했다(로그인 파일이 캐시보다 새롭다) → 5초 전 캐시라도 다시 조회한다."""
        for login in (".claude/.credentials.json", ".claude-b/.credentials.json", ".codex/auth.json"):
            with self.subTest(login=login):
                text, handed = self.startup(5, login=login)
                self.assertEqual(text, "FRESH_FROM_TOOL\n")
                self.assertIn("--startup", handed)

    def test_attention_rechecks_quietly_before_the_ttl(self):
        """유휴·로그인 만료가 있으면 토큰이 바뀌었는지 조용히 다시 본다 — 키체인에 쓴 로그인은 파일에 흔적이 없다.

        이 셸은 기다리지 않는다(캐시를 그대로 찍고 `--quiet` 호출을 백그라운드로 보낸다).
        """
        text, handed = self.startup(20, attention=True, background=True)
        self.assertEqual(text, "CACHED_USAGE\n")
        self.assertEqual(handed, "--startup --quiet --style bars --width 120\n")

    def test_attention_does_not_recheck_on_every_shell_of_a_burst(self):
        text, handed = self.startup(2, attention=True)
        self.assertEqual((text, handed), ("CACHED_USAGE\n", ""))

    def test_no_attention_keeps_the_normal_ttl(self):
        text, handed = self.startup(20)
        self.assertEqual(handed, "")

    def test_missing_render_for_this_width_is_handed_over(self):
        text, handed = self.startup(5, render=False)
        self.assertEqual(text, "FRESH_FROM_TOOL\n")

    def test_panel_is_not_drawn_into_a_pipe(self):
        """`zsh -i -c …` 자동화의 stdout(터미널 아님)에는 패널을 찍지도, API 를 기다리지도 않는다."""
        code = 'source "$1"'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "claude-usage"
            script.write_text('#!/bin/sh\necho CALLED > "$REFRESH_CAPTURE"\n')
            script.chmod(0o755)
            env = {**os.environ, "HOME": str(root), "PATH": str(root) + os.pathsep + os.environ["PATH"],
                   "CLAUDE_USAGE_STARTUP": "1", "CLAUDE_USAGE_CACHE": str(root / "cache"),
                   "REFRESH_CAPTURE": str(root / "refresh")}
            env.pop("CLAUDECODE", None)
            result = subprocess.run(["zsh", "-f", "-i", "-c", code, "test", str(ROOT / "dot_claude-accounts.zsh")],
                                    env=env, capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / "refresh").exists())

    def test_shell_and_tool_together_print_current_values(self):
        """끝단: zsh 함수 → 실제 claude-usage → (가짜) API. 낡은 캐시를 만난 셸에 새 값이 찍힌다."""
        box = Sandbox(self, cache_age=600, percent=77)
        (box.root / "bin").mkdir()
        (box.root / "bin/claude-usage").symlink_to(Sandbox.SCRIPT)
        # zsh 가 보는 로그인 파일을 이 상자 안으로 가둔다(HOME). 그 아래에서 도는 파이썬은 바이트코드를 안 남긴다.
        env = {**box.env, "PATH": str(box.root / "bin") + os.pathsep + os.environ["PATH"],
               "CLAUDE_USAGE_STARTUP": "0", "HOME": str(box.root), "PYTHONDONTWRITEBYTECODE": "1"}
        env.pop("CLAUDECODE", None)
        code = 'source "$1"; COLUMNS=120; _claude_usage_startup'
        result = subprocess.run(["zsh", "-f", "-c", code, "test", str(ROOT / "dot_claude-accounts.zsh")],
                                env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("77%", result.stdout)
        self.assertNotIn("CACHED_RENDER", result.stdout)
        again = subprocess.run(["zsh", "-f", "-c", code, "test", str(ROOT / "dot_claude-accounts.zsh")],
                               env=env, capture_output=True, text=True, timeout=20)
        self.assertIn("77%", again.stdout)                      # 두 번째 셸은 방금 그린 렌더를 cat 한다
        self.assertEqual(box.api.usage_hits(), 1)
        box.settle()


if __name__ == "__main__":
    unittest.main()
