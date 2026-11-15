"""실제 관리자 권한·네트워크 변경 없이 내부망 허용 도구의 회귀를 확인한다."""

import contextlib
import io
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "private_dot_local/bin/executable_mac-lan-ssh"
OLD, NEW = "192.168.219.0/24", "192.168.45.0/24"
SSH_BASE = "AllowUsers owen@100.64.0.0/10 owen@fd7a:115c:a1e0::/48\n"
SSH = "AllowUsers owen@100.64.0.0/10 owen@fd7a:115c:a1e0::/48 owen@192.168.219.0/24\n"
PF = '''login_ports = "{ 22 88 3283 5900 }"
pass in quick on lo0 all no state
pass in quick inet proto { tcp udp } from 100.64.0.0/10 to any port $login_ports no state
pass in quick inet6 proto { tcp udp } from fd7a:115c:a1e0::/48 to any port $login_ports no state
block drop in quick proto { tcp udp } to any port $login_ports
'''
# 2026-10-19 에 적용돼 2026-11-15 까지 이 Mac 에 있던 실제 파일 그대로(공백 두 칸 포함).
SSH_LIVE_1019 = '''# lazyowen 2026-10-03 (Owen "전부 막고 나만 키 연결 · tailscale 로만"): 공개키만 · owen 만 · tailnet 출처만.
PasswordAuthentication no
AuthenticationMethods publickey
# 2026-10-19 Owen 요청: 기존 공개키 인증 유지, 내부망 192.168.219.0/24 추가.
AllowUsers owen@100.64.0.0/10 owen@fd7a:115c:a1e0::/48 owen@192.168.219.0/24
'''
PF_LIVE_1019 = '''# lazyowen 2026-10-03 (Owen): 로그인 포트는 tailnet·루프백 출처만 — 공인·사무실 LAN 차단
login_ports = "{ 22 88 3283 5900 }"
pass  in quick on lo0 all no state
pass  in quick inet  proto { tcp udp } from 100.64.0.0/10       to any port $login_ports no state
pass  in quick inet6 proto { tcp udp } from fd7a:115c:a1e0::/48 to any port $login_ports no state
# 2026-10-19 Owen: 내부망 SSH·화면 공유 허용, 외부 차단 유지
pass in quick on { en0 en1 } inet proto tcp from 192.168.219.0/24 to any port { 22 5900 } no state
pass in quick on { en0 en1 } inet proto udp from 192.168.219.0/24 to any port { 5900 5901 5902 } no state
block drop in quick proto { tcp udp } to any port $login_ports
'''
IFCONFIG = {
    "en0": "en0: flags=8863<UP>\n\tinet6 fe80::1%en0 prefixlen 64\n"
           "\tinet 192.168.45.212 netmask 0xffffff00 broadcast 192.168.45.255\n",
    "en1": "en1: flags=8863<UP>\n\tinet 192.168.45.24 netmask 0xffffff00 broadcast 192.168.45.255\n",
}


def fake_ifconfig(table):
    def run(command, **kwargs):
        out = table.get(command[-1])
        return subprocess.CompletedProcess(command, 0 if out is not None else 1, stdout=out or "")
    return run


class LanAccessTests(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(SCRIPT))
        self.globals = self.module["main"].__globals__
        self.pf = lambda text, subnet=NEW: self.module["updated_pf"](text, subnet)
        self.ssh = lambda text, subnet=NEW: self.module["updated_config"](text, subnet)

    def test_already_updated_ssh_does_not_skip_pf(self):
        with tempfile.TemporaryDirectory() as temp:
            ssh, pf = Path(temp) / "ssh", Path(temp) / "pf"
            ssh.write_text(SSH)
            pf.write_text(PF)
            with patch.dict(self.globals, CONFIG=ssh, PF_CONFIG=pf), \
                    patch("sys.argv", ["mac-lan-ssh", "--apply", "--subnet", OLD]), \
                    patch("platform.system", return_value="Darwin"), \
                    patch("os.geteuid", return_value=0), \
                    patch.dict(self.globals, apply_pf=unittest.mock.Mock()) as values, \
                    contextlib.redirect_stdout(io.StringIO()):
                self.module["main"]()
                values["apply_pf"].assert_called_once_with(PF, self.pf(PF, OLD), OLD)

    def test_failed_pf_reload_restores_file_and_live_rules(self):
        calls = []
        live = "pass in quick on lo0 all no state\nblock drop in quick all\n"
        with tempfile.TemporaryDirectory() as temp:
            config = Path(temp) / "pf.conf"
            config.write_text(PF)

            def run(command, **kwargs):
                calls.append(command)
                if "-s" in command:
                    return subprocess.CompletedProcess(command, 0, stdout=live)
                if "-q" in command and command[-1] == str(config):
                    raise subprocess.CalledProcessError(1, command)
                return subprocess.CompletedProcess(command, 0)

            with patch.dict(self.globals, PF_CONFIG=config), patch("subprocess.run", side_effect=run):
                with self.assertRaises(subprocess.CalledProcessError):
                    self.module["apply_pf"](PF, self.pf(PF), NEW)
            self.assertEqual(config.read_text(), PF)
            self.assertEqual(Path(calls[-1][-1]).read_text(), live)
            self.assertTrue(all("-a" in call and self.module["PF_ANCHOR"] in call for call in calls))

    def test_pf_reload_that_keeps_old_subnet_is_rolled_back(self):
        """교체 뒤 실행 규칙에 이전 대역이 남으면 실패로 보고 되돌린다."""
        live_old = "pass in quick on { en0 en1 } inet proto tcp from 192.168.219.0/24 to any port = 22\n" \
                   "block drop in quick proto tcp from any to any port = 22\n"
        with tempfile.TemporaryDirectory() as temp:
            config = Path(temp) / "pf.conf"
            config.write_text(PF_LIVE_1019)

            def run(command, **kwargs):
                if "-s" in command:
                    return subprocess.CompletedProcess(command, 0, stdout=live_old + f"from {NEW}\n")
                return subprocess.CompletedProcess(command, 0)

            with patch.dict(self.globals, PF_CONFIG=config), patch("subprocess.run", side_effect=run):
                with self.assertRaises(ValueError):
                    self.module["apply_pf"](PF_LIVE_1019, self.pf(PF_LIVE_1019), NEW)
            self.assertEqual(config.read_text(), PF_LIVE_1019)

    def test_only_requested_ports_precede_existing_blocks(self):
        updated = self.pf(PF)
        self.assertEqual(self.pf(updated), updated)
        lan_rules = self.module["pf_lan_rules"](NEW)
        self.assertLess(updated.index(lan_rules), updated.index("block drop"))
        self.assertNotIn("3283", lan_rules)
        self.assertNotIn(" 88 ", lan_rules)
        self.assertIn("on { en0 en1 }", lan_rules)
        with self.assertRaises(ValueError):
            self.pf(PF + "pass in all\n")

    def test_office_move_replaces_old_subnet_in_pf(self):
        """2026-11-15 사무실 이전: 219 대역 규칙을 45 대역으로 바꾸고 나머지는 그대로 둔다."""
        updated = self.pf(PF_LIVE_1019)
        self.assertNotIn(OLD, updated)
        self.assertEqual(updated.count(f"from {NEW}"), 2)
        self.assertEqual(updated.count("내부망 SSH·화면 공유 허용"), 1)
        self.assertIn("pass  in quick inet  proto { tcp udp } from 100.64.0.0/10       to any", updated)
        self.assertTrue(updated.rstrip().endswith("block drop in quick proto { tcp udp } to any port $login_ports"))
        self.assertEqual(self.module["current_pf_subnet"](updated), NEW)
        self.assertEqual(self.pf(updated), updated)
        self.assertEqual(self.pf(PF_LIVE_1019, OLD), PF_LIVE_1019)

    def test_office_move_replaces_old_subnet_in_ssh(self):
        updated = self.ssh(SSH_LIVE_1019)
        allow = [line for line in updated.splitlines() if line.startswith("AllowUsers")]
        self.assertEqual(allow, [f"AllowUsers owen@100.64.0.0/10 owen@fd7a:115c:a1e0::/48 owen@{NEW}"])
        self.assertNotIn(OLD, updated)
        self.assertEqual(updated.count("기존 공개키 인증 유지, 내부망"), 1)
        self.assertIn("AuthenticationMethods publickey", updated)
        self.assertEqual(self.ssh(updated), updated)
        self.assertEqual(self.ssh(SSH_LIVE_1019, OLD), SSH_LIVE_1019)

    def test_fresh_ssh_gets_lan_entry_and_comment(self):
        updated = self.ssh(SSH_BASE)
        self.assertEqual(updated.splitlines()[-1],
                         f"AllowUsers owen@100.64.0.0/10 owen@fd7a:115c:a1e0::/48 owen@{NEW}")
        self.assertIn("기존 공개키 인증 유지, 내부망", updated.splitlines()[0])

    def test_ssh_rejects_unknown_allow_entries(self):
        for text in (SSH_BASE.rstrip() + " root@192.168.45.0/24\n",
                     SSH_BASE.rstrip() + " owen@0.0.0.0/0\n",
                     SSH_BASE.rstrip() + " owen@192.168.45.0/24 owen@10.0.0.0/24\n",
                     "AllowUsers owen@100.64.0.0/10\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.ssh(text)

    def test_pf_rejects_foreign_lan_rule(self):
        foreign = PF_LIVE_1019.replace("192.168.219.0/24", "0.0.0.0/0")
        with self.assertRaises(ValueError):
            self.pf(foreign)

    def test_subnet_must_be_private_and_narrow(self):
        ok = self.module["lan_subnet"]
        self.assertEqual(ok("192.168.45.0/24"), NEW)
        self.assertEqual(ok("10.20.0.0/16"), "10.20.0.0/16")
        for bad in ("0.0.0.0/0", "8.8.8.0/24", "100.64.0.0/10", "10.0.0.0/8",
                    "192.168.45.7/24", "fd00::/64", "nonsense"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                ok(bad)

    def test_detect_subnet_from_both_interfaces(self):
        subnet, seen = self.module["detect_subnet"](run=fake_ifconfig(IFCONFIG))
        self.assertEqual(subnet, NEW)
        self.assertEqual(seen, ["en0 192.168.45.212", "en1 192.168.45.24"])

    def test_detect_subnet_ignores_link_local_and_missing_interface(self):
        table = {"en0": IFCONFIG["en0"] + "\tinet 169.254.3.4 netmask 0xffff0000 broadcast 169.254.255.255\n"}
        subnet, seen = self.module["detect_subnet"](run=fake_ifconfig(table))
        self.assertEqual((subnet, seen), (NEW, ["en0 192.168.45.212"]))

    def test_detect_subnet_refuses_ambiguous_or_empty(self):
        mixed = dict(IFCONFIG, en1="en1:\n\tinet 10.1.2.3 netmask 0xffffff00 broadcast 10.1.2.255\n")
        for table in (mixed, {}, {"en0": "en0: flags=0<>\n"}):
            with self.subTest(table=table), self.assertRaises(ValueError):
                self.module["detect_subnet"](run=fake_ifconfig(table))


if __name__ == "__main__":
    unittest.main()
