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
SSH = "AllowUsers owen@100.64.0.0/10 owen@fd7a:115c:a1e0::/48 owen@192.168.219.0/24\n"
PF = '''login_ports = "{ 22 88 3283 5900 }"
pass in quick on lo0 all no state
pass in quick inet proto { tcp udp } from 100.64.0.0/10 to any port $login_ports no state
pass in quick inet6 proto { tcp udp } from fd7a:115c:a1e0::/48 to any port $login_ports no state
block drop in quick proto { tcp udp } to any port $login_ports
'''


class LanAccessTests(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(SCRIPT))
        self.globals = self.module["main"].__globals__

    def test_already_updated_ssh_does_not_skip_pf(self):
        with tempfile.TemporaryDirectory() as temp:
            ssh, pf = Path(temp) / "ssh", Path(temp) / "pf"
            ssh.write_text(SSH)
            pf.write_text(PF)
            with patch.dict(self.globals, CONFIG=ssh, PF_CONFIG=pf), \
                    patch("sys.argv", ["mac-lan-ssh", "--apply"]), \
                    patch("platform.system", return_value="Darwin"), \
                    patch("os.geteuid", return_value=0), \
                    patch.dict(self.globals, apply_pf=unittest.mock.Mock()) as values, \
                    contextlib.redirect_stdout(io.StringIO()):
                self.module["main"]()
                values["apply_pf"].assert_called_once_with(PF, self.module["updated_pf"](PF))

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
                    self.module["apply_pf"](PF, self.module["updated_pf"](PF))
            self.assertEqual(config.read_text(), PF)
            self.assertEqual(Path(calls[-1][-1]).read_text(), live)
            self.assertTrue(all("-a" in call and self.module["PF_ANCHOR"] in call for call in calls))

    def test_only_requested_ports_precede_existing_blocks(self):
        updated = self.module["updated_pf"](PF)
        self.assertEqual(self.module["updated_pf"](updated), updated)
        lan_rules = self.module["PF_LAN_RULES"]
        self.assertLess(updated.index(lan_rules), updated.index("block drop"))
        self.assertNotIn("3283", lan_rules)
        self.assertNotIn("88", lan_rules)
        self.assertIn("on { en0 en1 }", lan_rules)
        with self.assertRaises(ValueError):
            self.module["updated_pf"](PF + "pass in all\n")


if __name__ == "__main__":
    unittest.main()
