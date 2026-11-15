"""studio-lan-name 의 주소 선택·다시 등록 동작을 실제 dns-sd 없이 확인한다."""

from pathlib import Path
import contextlib
import io
import runpy
import subprocess
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "private_dot_local/bin/executable_studio-lan-name"
EN0 = "en0: flags=8863<UP>\n\tinet6 fe80::1%en0 prefixlen 64\n" \
      "\tinet 192.168.45.212 netmask 0xffffff00 broadcast 192.168.45.255\n\tstatus: active\n"
EN1 = "en1: flags=8863<UP>\n\tinet 192.168.45.24 netmask 0xffffff00 broadcast 192.168.45.255\n\tstatus: active\n"


def ifconfig(table):
    def run(command, **kwargs):
        out = table.get(command[-1])
        return subprocess.CompletedProcess(command, 0 if out is not None else 1, stdout=out or "")
    return run


class FakeChild:
    def __init__(self, command):
        self.command, self.returncode, self.terminated = command, None, False

    def poll(self):
        return self.returncode

    def terminate(self):
        self.terminated, self.returncode = True, -15

    def wait(self, timeout=None):
        return self.returncode


class StudioLanNameTests(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(SCRIPT))

    def test_prefers_wired_then_wifi(self):
        lan_ip = self.module["lan_ip"]
        self.assertEqual(lan_ip(run=ifconfig({"en0": EN0, "en1": EN1})), ("en0", "192.168.45.212"))
        unplugged = "en0: flags=8863<UP>\n\tstatus: inactive\n"
        self.assertEqual(lan_ip(run=ifconfig({"en0": unplugged, "en1": EN1})), ("en1", "192.168.45.24"))

    def test_ignores_link_local_public_and_missing(self):
        lan_ip = self.module["lan_ip"]
        odd = "en0:\n\tinet 169.254.3.4 netmask 0xffff0000\n\tinet 8.8.8.8 netmask 0xffffff00\n"
        self.assertIsNone(lan_ip(run=ifconfig({"en0": odd})))
        self.assertIsNone(lan_ip(run=ifconfig({})))

    def test_register_command_publishes_only_the_name(self):
        command = self.module["register_command"]("192.168.45.212")
        self.assertEqual(command[:2], ["/usr/bin/dns-sd", "-P"])
        self.assertIn("studio.local", command)
        self.assertEqual(command[command.index("studio.local") + 1], "192.168.45.212")
        self.assertIn("_device-info._tcp", command)  # Finder 네트워크 목록에 새 항목을 만들지 않는다
        self.assertEqual(command[command.index("local") + 1], "0")

    def test_mdns_answers_exclude_unicast_dns(self):
        # 2026-11-15 m4 실측 출력 — 인터페이스 0 줄은 통신사 DNS 가 없는 이름에 준 광고 서버 주소.
        output = """DATE: ---Sun 15 Nov 2026---
23:03:35.439  ...STARTING...
Timestamp     A/R  Flags         IF  Hostname                               Address                                      TTL
23:03:35.439  Add  40000003       7  studio.local.                          192.168.45.212                               240
23:03:35.439  Add  40000002      16  studio.local.                          192.168.45.212                               240
23:03:35.444  Add  2              0  studio.local.                          218.38.137.27                                4320
23:03:40.000  Rmv  0              7  studio.local.                          192.168.45.99                                0
"""
        self.assertEqual(self.module["mdns_addresses"](output), {"192.168.45.212"})
        self.assertEqual(self.module["mdns_addresses"](""), set())

    def test_reregisters_on_ip_change_and_child_exit(self):
        started, state = [], {"found": ("en0", "192.168.45.212")}

        def popen(command, **kwargs):
            child = FakeChild(command)
            started.append(child)
            return child

        advertiser = self.module["Advertiser"](popen=popen, find=lambda: state["found"])
        with contextlib.redirect_stdout(io.StringIO()):
            advertiser.tick()
            advertiser.tick()  # 그대로면 다시 띄우지 않는다
            self.assertEqual(len(started), 1)

            state["found"] = ("en1", "192.168.45.24")  # 유선이 빠짐
            advertiser.tick()
            self.assertTrue(started[0].terminated)
            self.assertEqual(started[1].command[-2], "192.168.45.24")

            started[1].returncode = 1  # dns-sd 가 끝남(이름 충돌 등)
            advertiser.tick()
            self.assertEqual(len(started), 3)

            state["found"] = None  # 망에서 빠짐
            advertiser.tick()
            self.assertTrue(started[2].terminated)
            self.assertIsNone(advertiser.child)
            advertiser.tick()
            self.assertEqual(len(started), 3)

            state["found"] = ("en0", "192.168.45.212")  # 다시 붙음
            advertiser.tick()
            self.assertEqual(len(started), 4)


if __name__ == "__main__":
    unittest.main()
