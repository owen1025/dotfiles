"""python3 -m unittest discover -s docs -p 'test_sys_usage.py' -v

렌더·임계값·CPU 샘플 재사용은 가짜 수치와 임시 캐시로 검증한다. 마지막 스모크 테스트만
이 머신의 실제 커널 값을 읽는다(네트워크 없음).
"""
import io
import json
import os
from pathlib import Path
import re
import runpy
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sysu = runpy.run_path(str(ROOT / "private_dot_local/bin/executable_sys-usage"))
LIVE = sysu["render"].__globals__   # run_path 는 사본을 돌려준다 — 목은 함수가 실제로 보는 전역에 건다
GIB = 1024 ** 3
STATS = {
    "host": "testhost", "uptime": 3 * 86400 + 4 * 3600,
    "cpu": {"percent": 47.0, "source": "10s", "cores": 12, "model": "Apple M6", "load": [6.3, 6.2, 5.3]},
    "mem": {"used": 11 * GIB, "total": 16 * GIB, "swap_used": 4.6 * GIB, "swap_total": 6 * GIB,
            "pressure": "normal"},
    "gpus": [{"name": "Apple M6", "percent": 3.0, "cores": 12, "mem_used": None, "mem_total": None}],
    "disks": [{"label": "DISK", "path": "/", "dev": 1, "used": 278 * GIB, "free": 182 * GIB,
               "total": 460 * GIB, "percent": 60.4}],
}
ANSI = re.compile(r"\033\[[0-9;]*m")


def plain(text):
    return ANSI.sub("", text)


def with_(base, **parts):
    stats = json.loads(json.dumps(base))
    for key, value in parts.items():
        stats[key] = value
    return stats


class RenderTests(unittest.TestCase):
    def render(self, stats, style="bars", width=120, color=False):
        return sysu["render"](stats, style, sysu["Ink"](color), width)

    def test_every_style_fits_the_terminal_width(self):
        for style in ("bars", "panel", "compact"):
            for width in (60, 76, 90, 120):
                with self.subTest(style=style, width=width):
                    text = self.render(STATS, style, width, color=True)
                    for line in plain(text).splitlines():
                        self.assertLessEqual(sysu["dwidth"](line), width, line)
                    names = [n for n in ("CPU", "RAM", "GPU", "DISK") if n in text]
                    self.assertEqual(names, ["CPU", "RAM", "GPU", "DISK"])

    def test_bars_columns_line_up_with_claude_usage_panel(self):
        # 시작 화면에서 두 패널이 한 표처럼 읽히는 건 게이지·% 열이 같은 칸이라서다.
        claude = runpy.run_path(str(ROOT / "private_dot_local/bin/executable_claude-usage"))
        account = {"label": "claude", "dir": "/unused", "kind": "claude", "state": "ok", "usage": {"limits": [
            {"kind": "session", "group": "session", "percent": 7},
            {"kind": "weekly_all", "group": "weekly", "percent": 76},
            {"kind": "weekly_scoped", "group": "weekly", "percent": 7,
             "scope": {"model": {"display_name": "Fable"}}},
        ]}}
        theirs = claude["render"]({"fetched_at": 1788962076, "accounts": [account]}, "bars", claude["Ink"](False), 120)
        ours = self.render(STATS)

        def gauge_col(text, name):
            line = next(l for l in text.splitlines() if l.lstrip().startswith(name))
            start = min(i for i, ch in enumerate(line) if ch in "█░")
            return sysu["dwidth"](line[:start])
        self.assertEqual(gauge_col(ours, "CPU"), gauge_col(theirs, "주간 전체"))

    def test_memory_pressure_outranks_the_used_percentage(self):
        def ram_level(pressure, used=6):
            mem = dict(STATS["mem"], used=used * GIB, pressure=pressure)
            return next(r for r in sysu["rows_of"](with_(STATS, mem=mem), True) if r["name"] == "RAM")["lvl"]
        self.assertEqual(ram_level("normal"), 0)            # 37% → 초록
        self.assertEqual(ram_level("warn"), 2)              # 37% 라도 압박 주의 → 주황
        self.assertEqual(ram_level("critical"), 3)
        self.assertEqual(ram_level(None, used=15), 3)       # Linux(압박 없음) 94% → 빨강
        text = self.render(with_(STATS, mem=dict(STATS["mem"], pressure="warn")), "compact", 120)
        self.assertIn("압박 주의", text)

    def test_disk_free_space_is_flagged_relative_to_disk_size(self):
        def free_level(total_g, free_g):
            d = dict(STATS["disks"][0], total=total_g * GIB, free=free_g * GIB, used=(total_g - free_g) * GIB,
                     percent=100 * (total_g - free_g) / total_g)
            row = sysu["rows_of"](with_(STATS, disks=[d]), True)[-1]
            return row["detail"][-1]
        self.assertEqual(free_level(460, 15), ("여유 15G", 3))     # disk-cleanup 경고선(20GiB) 아래
        self.assertEqual(free_level(460, 35), ("여유 35G", 2))
        self.assertEqual(free_level(460, 182), ("여유 182G", None))
        self.assertEqual(free_level(30, 12), ("여유 12G", None))   # 작은 서버 디스크는 10% 상한

    def test_missing_gpu_drops_the_row_instead_of_showing_zero(self):
        text = self.render(with_(STATS, gpus=[]))
        self.assertNotIn("GPU", text)
        self.assertIn("DISK", text)

    def test_linux_style_names_and_vram(self):
        gpu = {"name": "RTX 4090", "percent": 81.0, "cores": None, "mem_used": 3 * GIB, "mem_total": 24 * GIB}
        stats = with_(STATS, gpus=[gpu], cpu=dict(STATS["cpu"], model="Intel Xeon E5-2680 v4"))
        text = self.render(stats)
        self.assertIn("RTX 4090", text)
        self.assertIn("VRAM 3G / 24G", text)


class CpuSampleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = os.path.join(self.tmp.name, "cpu.json")
        self.addCleanup(self.tmp.cleanup)
        p = patch.dict(LIVE, {"CPU_CACHE": self.cache, "IS_MAC": False})
        p.start()
        self.addCleanup(p.stop)

    def run_measure(self, samples, now=1000.0, boot=1):
        it = iter(samples)
        sleeps = []
        with patch.dict(LIVE, {"cpu_sample": lambda _m: next(it)}), \
                patch("time.sleep", lambda s: sleeps.append(s)):
            out = sysu["measure_cpu"](None, boot, 0.1, now)
        return out, sleeps

    def write_cache(self, t, ticks, boot=1):
        with open(self.cache, "w") as f:
            json.dump({"t": t, "boot": boot, "ticks": ticks}, f)

    def test_no_previous_sample_measures_a_short_window(self):
        a = [100, 0, 0, 900, 0, 0, 0, 0]
        b = [130, 0, 0, 970, 0, 0, 0, 0]                    # 30 busy / 100 → 30%
        out, sleeps = self.run_measure([a, b])
        self.assertEqual(sleeps, [0.1])
        self.assertAlmostEqual(out["percent"], 30.0)
        with open(self.cache) as f:
            self.assertEqual(json.load(f)["ticks"], b)

    def test_recent_previous_sample_is_reused_without_waiting(self):
        self.write_cache(990.0, [0, 0, 0, 0, 0, 0, 0, 0])
        out, sleeps = self.run_measure([[60, 0, 20, 100, 20, 0, 0, 0]])   # busy 80 / 200; iowait = idle
        self.assertEqual(sleeps, [])
        self.assertAlmostEqual(out["percent"], 40.0)
        self.assertEqual(out["source"], "10s")

    def test_too_fresh_sample_is_kept_as_the_reference(self):
        # 셸을 연달아 열어도(1초 간격) 기준점을 덮지 않아야 3초 뒤 셸이 대기 없이 쓴다.
        self.write_cache(999.0, [0] * 8)
        out, sleeps = self.run_measure([[1] + [0] * 3 + [1] + [0] * 3, [2] + [0] * 3 + [2] + [0] * 3])
        self.assertEqual(sleeps, [0.1])
        with open(self.cache) as f:
            self.assertEqual(json.load(f)["t"], 999.0)

    def test_sample_from_another_boot_is_ignored(self):
        self.write_cache(990.0, [0] * 8, boot=0)
        _, sleeps = self.run_measure([[10, 0, 0, 10, 0, 0, 0, 0], [20, 0, 0, 20, 0, 0, 0, 0]])
        self.assertEqual(sleeps, [0.1])

    def test_mac_tick_counters_wrap_around(self):
        a = [2 ** 32 - 10, 0, 0, 0]                          # user 가 uint32 끝에서 감김
        b = [5, 0, 85, 0]
        self.assertAlmostEqual(sysu["cpu_busy_pct"](a, b, mac=True), 15.0)


class ParserTests(unittest.TestCase):
    def test_meminfo_uses_mem_available(self):
        text = "MemTotal: 16000 kB\nMemFree: 1000 kB\nMemAvailable: 6000 kB\nSwapTotal: 2000 kB\nSwapFree: 500 kB\n"
        mem = sysu["parse_meminfo"](text)
        self.assertEqual(mem["used"], 10000 * 1024)
        self.assertEqual(mem["swap_used"], 1500 * 1024)

    def test_ioreg_device_utilization(self):
        text = ('+-o AGXAcceleratorG18G  <class AGXAcceleratorG18G>\n  {\n    "model" = "Apple M6"\n'
                '    "gpu-core-count" = 12\n    "PerformanceStatistics" = {"Device Utilization %"=37,'
                '"Renderer Utilization %"=30}\n  }\n')
        self.assertEqual(sysu["parse_ioreg"](text),
                         [{"name": "Apple M6", "percent": 37.0, "cores": 12, "mem_used": None, "mem_total": None}])

    def test_nvidia_smi_csv(self):
        gpu = sysu["parse_nvidia"]("NVIDIA GeForce RTX 4090, 81, 3072, 24564\n")[0]
        self.assertEqual((gpu["name"], gpu["percent"], gpu["mem_used"]), ("GeForce RTX 4090", 81.0, 3 * GIB))

    def test_cpu_model_is_tidied(self):
        self.assertEqual(sysu["tidy_model"]("Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz"), "Intel Xeon E5-2680 v4")
        self.assertEqual(sysu["tidy_model"]("AMD EPYC 7763 64-Core Processor"), "AMD EPYC 7763")


class LinuxPathTests(unittest.TestCase):
    """Ubuntu 서버에서 도는 경로를 가짜 /proc 으로 끝까지 돌린다(이 맥에는 컨테이너 런타임이 없다)."""

    PROC = {
        "/proc/stat": "cpu  600 0 200 1000 200 0 0 0 0 0\ncpu0 300 0 100 500 100 0 0 0 0 0\nbtime 1790000000\n",
        "/proc/meminfo": "MemTotal: 8000000 kB\nMemFree: 500000 kB\nMemAvailable: 2000000 kB\n"
                         "SwapTotal: 0 kB\nSwapFree: 0 kB\n",
        "/proc/cpuinfo": "processor : 0\nmodel name : AMD EPYC 7763 64-Core Processor\n",
    }

    def test_collect_and_render_on_linux(self):
        real_open = open

        def fake_open(path, *a, **k):
            if path in self.PROC:
                return io.StringIO(self.PROC[path])
            return real_open(path, *a, **k)

        with tempfile.TemporaryDirectory() as tmp:
            cache = os.path.join(tmp, "cpu.json")
            with real_open(cache, "w") as f:      # 10초 전 셸이 남긴 샘플 → busy 400 / 1000 = 40%
                json.dump({"t": time.time() - 10, "boot": 1790000000, "ticks": [400, 0, 0, 600, 0, 0, 0, 0]}, f)
            with patch.dict(LIVE, {"IS_MAC": False, "open": fake_open, "CPU_CACHE": cache}), \
                    patch("shutil.which", lambda _n: None):
                stats = sysu["collect"](0)
        self.assertAlmostEqual(stats["cpu"]["percent"], 40.0)
        self.assertEqual(stats["cpu"]["model"], "AMD EPYC 7763")
        self.assertEqual(stats["mem"]["used"], 6000000 * 1024)
        self.assertEqual(stats["disks"][0]["path"], "/")
        self.assertEqual(stats["gpus"], [])                 # GPU 없는 서버 → 행 생략
        text = sysu["render"](stats, "bars", sysu["Ink"](False), 100)
        self.assertIn("AMD EPYC 7763", text)
        self.assertRegex(text, r"RAM\s+█+░*\s+75%")
        self.assertNotIn("GPU", text)
        self.assertNotIn("압박", text)

    def test_amd_sysfs_reads_cards_but_not_connectors(self):
        with tempfile.TemporaryDirectory() as root:
            for name in ("card0", "card0-DP-1"):
                dev = os.path.join(root, name, "device")
                os.makedirs(dev)
                for fname, value in (("gpu_busy_percent", "42"), ("mem_info_vram_used", str(2 * GIB)),
                                     ("mem_info_vram_total", str(16 * GIB))):
                    with open(os.path.join(dev, fname), "w") as f:
                        f.write(value + "\n")
            gpus = sysu["gpus_amd_sysfs"](root)
        self.assertEqual(len(gpus), 1)
        self.assertEqual((gpus[0]["percent"], gpus[0]["mem_total"]), (42.0, 16 * GIB))


class StartupTests(unittest.TestCase):
    def test_startup_prints_nothing_when_collection_fails(self):
        def boom(*_a, **_k):
            raise RuntimeError("kernel said no")
        out = io.StringIO()
        with patch.dict(LIVE, {"collect": boom}), patch.object(sys, "argv", ["sys-usage", "--startup"]), \
                patch.object(sys, "stdout", out):
            self.assertEqual(sysu["main"](), 0)
        self.assertEqual(out.getvalue(), "")

    def test_live_collect_smoke(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(LIVE, {"CPU_CACHE": os.path.join(tmp, "cpu.json")}):
            started = time.monotonic()
            stats = sysu["collect"](0.05)
            elapsed = time.monotonic() - started
        self.assertLess(elapsed, 1.5)
        pct = stats["cpu"]["percent"]
        self.assertTrue(pct is None or 0 <= pct <= 100)
        self.assertGreater(stats["mem"]["total"], 0)
        self.assertLessEqual(stats["mem"]["used"], stats["mem"]["total"])
        self.assertTrue(stats["disks"])
        if sys.platform == "darwin":
            self.assertTrue(stats["gpus"], "IOAccelerator 의 Device Utilization % 를 못 읽었다")


if __name__ == "__main__":
    unittest.main()
