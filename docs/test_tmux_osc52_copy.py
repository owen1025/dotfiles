"""tmux-osc52-copy 테스트. 임시 tmux 서버(-L, TMUX_TMPDIR 격리)와 pty 를 "손앞 터미널" 로 쓰고
pbcopy 는 가짜로 바꾼다 — 실제 클립보드·실제 tmux 서버·네트워크를 건드리지 않는다.

    python3 -m unittest discover -s docs -p 'test_tmux_osc52_copy.py' -v
"""
import base64
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "private_dot_local/bin/executable_tmux-osc52-copy"
OSC52 = re.compile(rb"\x1b\]52;c;([A-Za-z0-9+/=]*)\x07")
TMUX = shutil.which("tmux")


def read_pty(fd, seconds=0.5):
    """아무것도 안 와도 막히지 않는다 — 실패가 멈춤이 아니라 단언 실패로 보이게."""
    out, end = b"", time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            out += os.read(fd, 65536)
    return out


class Client:
    """tmux 클라이언트를 pty 에 붙여 둔 가짜 터미널. master 로 나온 바이트를 모은다."""

    def __init__(self, env, sock, session):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execvpe(TMUX, ["tmux", "-L", sock, "-f", "/dev/null", "new-session", "-A", "-s", session,
                              "-x", "100", "-y", "30", "printf 'COPYME_LINE\\n'; sleep 600"], env)
        self.seen = b""

    def read(self, seconds=0.6):
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([self.fd], [], [], 0.05)
            if ready:
                try:
                    self.seen += os.read(self.fd, 65536)
                except OSError:
                    break
        return self.seen

    def osc52(self):
        return [base64.b64decode(m) for m in OSC52.findall(self.read(0.3))]

    def close(self):
        try:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        except OSError:
            pass
        try:
            os.close(self.fd)
        except OSError:
            pass


@unittest.skipUnless(TMUX, "tmux 가 없다")
class Osc52CopyTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="o52", dir="/tmp"))  # 소켓 경로 104자 제한 때문에 짧게
        self.addCleanup(shutil.rmtree, self.root, True)
        stub = self.root / "bin"
        stub.mkdir()
        (stub / "pbcopy").write_text(f"#!/bin/sh\ncat > {self.root}/pbcopy.out\n")
        (stub / "pbcopy").chmod(0o755)
        self.env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "TMUX_PANE")}
        self.env.update(TERM="xterm-256color", TMUX_TMPDIR=str(self.root), PATH=f"{stub}:{os.environ['PATH']}",
                        XDG_STATE_HOME=str(self.root / "state"), TMUX_OSC52_DECOY_WAIT="0.05",
                        TMPDIR=str(self.root))
        self.sock = "o52t"
        self.clients = []
        self.addCleanup(self.cleanup)

    def cleanup(self):
        for c in self.clients:
            c.close()
        subprocess.run([TMUX, "-L", self.sock, "kill-server"], env=self.env, capture_output=True)

    def tm(self, *args, check=True):
        r = subprocess.run([TMUX, "-L", self.sock, *args], env=self.env, capture_output=True, text=True)
        if check:
            self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def attach(self, session="t"):
        c = Client(self.env, self.sock, session)
        self.clients.append(c)
        c.read(1.0)
        return c

    def run_script(self, data, *args, tmux_env=True):
        env = dict(self.env)
        if tmux_env:
            sock_path = self.root / f"tmux-{os.getuid()}" / self.sock
            env["TMUX"] = f"{sock_path},{self.tm('display', '-p', '#{pid}').strip()},0"
        return subprocess.run(["/bin/sh", str(SCRIPT), *args], input=data, env=env, capture_output=True, timeout=20)

    def copy_line_in_tmux(self):
        """실제 복사 경로: copy-mode → 줄 선택 → copy-pipe-and-cancel(= copy-command)."""
        self.tm("set", "-s", "copy-command", f"/bin/sh {SCRIPT}")
        self.tm("copy-mode", "-t", "t")
        self.tm("send-keys", "-X", "-t", "t", "search-backward", "COPYME_LINE")
        self.tm("send-keys", "-X", "-t", "t", "select-line")
        self.tm("send-keys", "-X", "-t", "t", "copy-pipe-and-cancel")

    def events(self):
        log = self.root / "state/tmux-osc52/events.log"
        return log.read_text() if log.exists() else ""

    def test_copy_command_path_reaches_client_tty(self):
        client = self.attach()
        self.copy_line_in_tmux()
        time.sleep(0.8)
        self.assertEqual([b"COPYME_LINE\n"], client.osc52())
        self.assertEqual("COPYME_LINE\n", (self.root / "pbcopy.out").read_text())

    def test_same_text_twice_sends_a_changed_value_between(self):
        # mosh 는 직전과 같은 클립보드 문자열을 전달하지 않는다 → 연달아 같은 내용이면 사이에 다른 값을 낀다
        client = self.attach()
        for _ in range(2):
            self.copy_line_in_tmux()
            time.sleep(0.8)
        got = client.osc52()
        self.assertEqual([b"COPYME_LINE\n", b"COPYME_LINE\n ", b"COPYME_LINE\n"], got)
        self.assertEqual([got[0], got[2]], [b"COPYME_LINE\n"] * 2)
        self.assertNotEqual(got[1], got[2])  # 직전 값과 달라야 mosh 가 보낸다
        self.assertIn("같은 내용 재복사", self.events())

    def test_different_text_sends_once_each(self):
        client = self.attach()
        self.run_script(b"first")
        self.run_script(b"second")
        self.assertEqual([b"first", b"second"], client.osc52())

    def test_missing_socket_is_revived_then_copy_goes_through(self):
        # 2026-11-23 실측 원인: /private/tmp 청소가 소켓 파일을 지우면 tmux 명령이 전부 실패했다
        client = self.attach()
        sock_path = self.root / f"tmux-{os.getuid()}" / self.sock
        server_pid = self.tm("display", "-p", "#{pid}").strip()  # 소켓이 있을 때 미리 알아 둔다 ($TMUX 의 둘째 칸과 같다)
        sock_path.unlink()
        self.assertFalse(sock_path.exists())
        self.assertNotEqual(0, subprocess.run([TMUX, "-L", self.sock, "ls"], env=self.env, capture_output=True).returncode)
        env = dict(self.env, TMUX=f"{sock_path},{server_pid},0")
        r = subprocess.run(["/bin/sh", str(SCRIPT)], input=b"after-cleanup", env=env, capture_output=True, timeout=20)
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertTrue(sock_path.exists())
        self.assertEqual([b"after-cleanup"], client.osc52())
        self.assertIn("소켓 복구", self.events())

    def guard(self, *args):
        env = dict(self.env, TMUX_SOCKET_GUARD_DIR=str(self.root.resolve()))  # 진짜 서버는 보지 않는다(lsof 는 /tmp → /private/tmp 실경로를 준다)
        guard = SCRIPT.with_name("executable_tmux-socket-guard")
        return subprocess.run(["bash", str(guard), *args], env=env, capture_output=True, text=True, timeout=30)

    def test_guard_revives_deleted_socket_and_spares_clients(self):
        # 청소가 소켓을 지운 서버를 tmux-socket-guard 가 되살린다. 클라이언트에는 SIGUSR1 을 보내지 않는다
        # (클라이언트는 SIGUSR1 에 죽는다) — 서버만 살려야 하고 붙어 있던 화면·세션은 그대로여야 한다.
        client = self.attach()
        sock_path = self.root / f"tmux-{os.getuid()}" / self.sock
        self.assertEqual(0, self.guard("--check").returncode)
        sock_path.unlink()
        r = self.guard("--check")
        self.assertEqual(1, r.returncode, r.stdout)
        self.assertIn("소켓 없음", r.stdout)
        self.assertFalse(sock_path.exists(), "--check 는 고치지 않는다")
        self.assertEqual(0, self.guard("-n").returncode)
        self.assertFalse(sock_path.exists(), "-n 도 고치지 않는다")
        r = self.guard()
        self.assertIn("소켓 복구", r.stdout, r.stderr)
        self.assertTrue(sock_path.exists())
        os.kill(client.pid, 0)  # 클라이언트 프로세스가 살아 있다
        self.assertEqual("t", self.tm("list-sessions", "-F", "#{session_name}").strip())
        self.assertEqual(1, len(self.tm("list-clients").strip().splitlines()))

    def test_guard_refreshes_timestamps_of_healthy_socket(self):
        # tmp_cleaner 는 atime·mtime·ctime 이 모두 3일 넘은 것만 지운다 → touch 로 기한을 미룬다
        self.attach()
        sock_path = self.root / f"tmux-{os.getuid()}" / self.sock
        old = time.time() - 5 * 86400
        os.utime(sock_path, (old, old))
        self.assertLess(sock_path.stat().st_mtime, time.time() - 86400)
        self.guard()
        st = sock_path.stat()
        self.assertGreater(st.st_mtime, time.time() - 60)
        self.assertGreater(st.st_atime, time.time() - 60)

    def test_most_recently_active_client_gets_it(self):
        self.attach("t")
        old, new = self.clients[0], None
        time.sleep(1.1)
        new = self.attach("t")
        os.write(new.fd, b" ")  # 키 입력 = client_activity 갱신
        time.sleep(0.4)
        self.run_script(b"only-for-active")
        self.assertEqual([], old.osc52())
        self.assertEqual([b"only-for-active"], new.osc52())

    def test_empty_input_does_not_touch_clipboard(self):
        client = self.attach()
        self.run_script(b"")
        self.assertEqual([], client.osc52())
        self.assertFalse((self.root / "pbcopy.out").exists())

    def test_explicit_tty_argument_and_no_tmux(self):
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        r = self.run_script("한글 ✓\n".encode(), os.ttyname(slave), tmux_env=False)
        self.assertEqual(0, r.returncode, r.stderr)
        data = read_pty(master)
        self.assertEqual(["한글 ✓\n".encode()], [base64.b64decode(m) for m in OSC52.findall(data)])

    def test_binary_safe_trailing_newlines_are_kept(self):
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        self.run_script(b"line\n\n\n", os.ttyname(slave), tmux_env=False)
        got = [base64.b64decode(m) for m in OSC52.findall(read_pty(master))]
        self.assertEqual([b"line\n\n\n"], got)


if __name__ == "__main__":
    unittest.main()
