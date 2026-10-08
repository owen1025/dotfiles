"""자동 삭제의 경계 테스트. 임시 폴더와 가짜 프로세스만 사용하며 Slack은 목 처리한다."""
import importlib.machinery
import importlib.util
import json
import logging
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "private_dot_local/bin/executable_disk-cleanup"
loader = importlib.machinery.SourceFileLoader("disk_cleanup", str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
gc = importlib.util.module_from_spec(spec)
sys.modules[loader.name] = gc
loader.exec_module(gc)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.now = time.time() + 60 * gc.DAY
        self.process = gc.Processes("", [])

    def file(self, name, recent=False):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("fixture\n")
        if recent:
            os.utime(p, (self.now, self.now))
        return p

    def run_rule(self, rule, apply=True, seen=None, now=None):
        return gc.clean([rule], self.process, now or self.now, apply, seen)

    def test_dry_run_does_not_delete(self):
        p = self.file("cache/old")
        report, _ = self.run_rule(gc.Rule("cache", p.parent, 3), apply=False)
        self.assertTrue(p.exists())
        self.assertEqual(report["groups"]["cache"]["eligible"], 1)
        self.assertEqual(report["removed_bytes"], 0)

    def test_old_cache_removed_and_recent_file_preserved(self):
        old = self.file("cache/old")
        new = self.file("cache/new", recent=True)
        self.run_rule(gc.Rule("cache", old.parent, 3))
        self.assertFalse(old.exists())
        self.assertTrue(new.exists())

    def test_newly_copied_old_file_is_protected_by_ctime(self):
        p = self.file("cache/copied-old")
        old = time.time() - 60 * gc.DAY
        os.utime(p, (old, old))
        self.run_rule(gc.Rule("cache", p.parent, 3), now=time.time())
        self.assertTrue(p.exists())

    def test_new_file_inside_old_directory_prevents_whole_deletion(self):
        child = self.file("work/nested/new", recent=True)
        self.run_rule(gc.Rule("work", self.root / "work", 7, "whole"))
        self.assertTrue(child.exists())

    def test_open_descendant_protects_directory(self):
        child = self.file("work/nested/input")
        self.process = gc.Processes("", [str(child)])
        self.run_rule(gc.Rule("work", self.root / "work", 7, "whole"))
        self.assertTrue(child.exists())

    def test_open_hardlink_protects_original(self):
        p = self.file("cache/input")
        alias = self.root / "in-use"
        os.link(p, alias)
        self.process = gc.Processes("", [str(alias)])
        self.run_rule(gc.Rule("cache", p.parent, 3))
        self.assertTrue(p.exists())

    def test_process_argument_protects_npx_package(self):
        p = self.file("npx/hash/node_modules/main.js")
        self.process = gc.Processes("node " + str(p), [])
        self.run_rule(gc.Rule("npx", self.root / "npx", 7, "children"))
        self.assertTrue(p.exists())

    def test_symlink_root_and_ancestor_never_followed(self):
        p = self.file("original/cache/input")
        alias = self.root / "alias"
        alias.symlink_to(self.root / "original", target_is_directory=True)
        self.run_rule(gc.Rule("cache", alias / "cache", 3))
        self.assertTrue(p.exists())
        direct = self.root / "direct"
        direct.symlink_to(p.parent, target_is_directory=True)
        self.run_rule(gc.Rule("cache", direct, 3))
        self.assertTrue(p.exists())

    def test_internal_symlink_target_not_removed(self):
        outside = self.file("outside/input")
        self.file("work/item")
        (self.root / "work/link").symlink_to(outside.parent, target_is_directory=True)
        self.run_rule(gc.Rule("work", self.root / "work", 7, "whole"))
        self.assertFalse((self.root / "work").exists())
        self.assertTrue(outside.exists())

    def test_current_and_loaded_old_versions_preserved(self):
        current = self.file("releases/1.3.0/bin/tool").parents[1]
        active = self.file("releases/1.2.0/bin/tool")
        unused = self.file("releases/1.1.0/bin/tool")
        link = self.root / "current"
        link.symlink_to(current, target_is_directory=True)
        self.process = gc.Processes("", [str(active)])
        self.run_rule(gc.Rule("versions", current.parent, 7, "versions", current=link))
        self.assertTrue(current.exists())
        self.assertTrue(active.exists())
        self.assertFalse(unused.exists())

    def test_missing_current_link_preserves_all_versions(self):
        p = self.file("versions/1.1.0")
        self.run_rule(gc.Rule("versions", p.parent, 7, "versions", current=self.root / "missing"))
        self.assertTrue(p.exists())

    def test_trash_keeps_old_file_for_30_days_after_first_observation(self):
        p = self.file("trash/old-document")
        rule = gc.Rule("trash", p.parent, 30, "trash")
        _, seen = self.run_rule(rule)
        self.assertTrue(p.exists())
        self.run_rule(rule, seen=seen, now=self.now + 29 * gc.DAY)
        self.assertTrue(p.exists())
        _, seen = self.run_rule(rule, seen=seen, now=self.now + 31 * gc.DAY)
        self.assertFalse(p.exists())
        self.assertFalse(seen)

    def test_finder_only_video_files_removed(self):
        video = self.file("finder/a/video.mp4")
        image = self.file("finder/a/image.png")
        self.run_rule(gc.Rule("finder", self.root / "finder", 7, "videos"))
        self.assertFalse(video.exists())
        self.assertTrue(image.exists())

    def test_validation_name_does_not_include_other_projects(self):
        old = self.file("cache/studio-publish-validation-20260929/file")
        safe = self.file("cache/studio-publish-validation-my-source/file")
        runtime = self.file("cache/codex-runtimes/file")
        self.run_rule(gc.Rule("build", self.root / "cache", 7, "validation"))
        self.assertFalse(old.exists())
        self.assertTrue(safe.exists())
        self.assertTrue(runtime.exists())

    def test_running_owner_app_preserves_vm(self):
        p = self.file("vm/bundle/rootfs.img")
        self.process = gc.Processes("/Applications/Claude.app/Contents/MacOS/Claude", [])
        self.run_rule(gc.Rule("Claude VM 번들", self.root / "vm", 14, "children",
                              ("/Applications/Claude.app/",)))
        self.assertTrue(p.exists())

    def test_app_starting_before_delete_is_rechecked(self):
        p = self.file("cache/input")
        def started():
            self.process.commands = "/Applications/Owner.app/main"
        with patch.object(self.process, "refresh", side_effect=started):
            self.run_rule(gc.Rule("cache", p.parent, 3, apps=("/Applications/Owner.app/",)))
        self.assertTrue(p.exists())

    def test_permission_failure_is_reported_without_sudo(self):
        p = self.file("cache/input")
        with patch.object(gc.os, "access", return_value=False):
            report, _ = self.run_rule(gc.Rule("cache", p.parent, 3))
        self.assertTrue(p.exists())
        self.assertEqual(report["groups"]["cache"]["kept"]["관리자 권한 필요"], 1)

    def test_lsof_failure_blocks_cleanup(self):
        responses = [subprocess.CompletedProcess([], 0, "running", ""),
                     subprocess.CompletedProcess([], 1, "", "denied")]
        with patch.object(gc.subprocess, "run", side_effect=responses):
            with self.assertRaisesRegex(RuntimeError, "삭제 중단"):
                gc.Processes.capture()

    def test_midrun_process_check_failure_keeps_partial_receipt(self):
        a = self.file("cache/a")
        self.file("cache/b")
        with patch.object(self.process, "refresh", side_effect=[None, RuntimeError("조회 실패")]):
            report, _ = self.run_rule(gc.Rule("cache", a.parent, 3))
        self.assertEqual(report["groups"]["cache"]["removed"], 1)
        self.assertEqual(report["fatal"], "조회 실패")
        self.assertEqual(len(list(a.parent.iterdir())), 1)

    def test_replaced_identity_is_not_deleted(self):
        p = self.file("cache/input")
        with self.assertRaisesRegex(ValueError, "파일 교체"):
            gc.remove(p, (-1, -1))
        self.assertTrue(p.exists())

    def test_notification_failure_queues_same_delivery_id_for_retry(self):
        state = self.root / "state"
        state.mkdir()
        report = {"id": "one", "finished": "test", "free_before": 0, "free_after": 20 * 1024**3,
                  "groups": {}, "removed_bytes": 0, "errors": []}
        logger = logging.getLogger("test")
        logger.addHandler(logging.NullHandler())
        failure = subprocess.CompletedProcess([], 1, "", "network failure")
        with patch.object(gc.subprocess, "run", return_value=failure):
            self.assertEqual(gc.deliver(self.root, state, {"slack_channel": "COPS"}, report, logger), "대기")
        self.assertEqual(json.loads((state / "pending-slack.json").read_text())[0]["id"], "one")
        report = {**report, "id": "two"}
        success = subprocess.CompletedProcess([], 0, "ok 123.456", "")
        with patch.object(gc.subprocess, "run", return_value=success) as send:
            self.assertEqual(gc.deliver(self.root, state, {"slack_channel": "COPS"}, report, logger), "전달 완료")
        self.assertIn("disk-cleanup:one", send.call_args_list[0].args[0])
        self.assertIn("disk-cleanup:two", send.call_args_list[1].args[0])
        self.assertEqual(json.loads((state / "pending-slack.json").read_text()), [])

    def test_permission_error_is_not_reported_as_full_success(self):
        report = {"finished": "test", "free_before": 0, "free_after": 20 * 1024**3,
                  "groups": {}, "removed_bytes": 0, "errors": ["휴지통: PermissionError"]}
        message = gc.notification(report)
        self.assertIn("일부 완료", message)
        self.assertIn("휴지통: PermissionError", message)

    def test_live_cache_cleaned_while_owner_app_runs(self):
        old = self.file("cache/old-entry")
        held = self.file("cache/open-entry")
        new = self.file("cache/new-entry", recent=True)
        self.process = gc.Processes("/Applications/Owner.app/main", [str(held)])
        self.run_rule(gc.Rule("cache", old.parent, 3, apps=("/Applications/Owner.app/",), live=True))
        self.assertFalse(old.exists())
        self.assertTrue(held.exists())
        self.assertTrue(new.exists())

    def test_tcc_denial_is_kept_reason_not_error(self):
        p = self.file("trash/item")
        rule = gc.Rule("trash", p.parent, 30, "trash", needs_fda=True)
        with patch.object(gc.Path, "iterdir", side_effect=PermissionError):
            report, _ = self.run_rule(rule)
        self.assertEqual(report["errors"], [])
        self.assertEqual(report["groups"]["trash"]["kept"]["전체 디스크 접근 권한 필요"], 1)
        with patch.object(gc.Path, "iterdir", side_effect=PermissionError):
            report, _ = self.run_rule(gc.Rule("cache", p.parent, 3, "children"))
        self.assertEqual(report["errors"], ["cache: PermissionError"])

    def test_chrome_clone_rule_is_beside_user_temp(self):
        temp = self.root / "folders/xx/T"
        roots = {rule.name: rule.root for rule in gc.rules(self.root / "home", temp)}
        self.assertEqual(roots["Chrome 앱 복제본"],
                         self.root / "folders/xx/X/com.google.Chrome.code_sign_clone")

    def test_capcut_rules_touch_only_caches_capcut_rebuilds(self):
        # 2026-10-08 git-trick: a mask package under Cache/effect was emptied and CapCut rendered the edit without it
        home = self.root / "home"
        cache = home / "Movies/CapCut/User Data/Cache"
        roots = {rule.root for rule in gc.rules(home, None) if rule.name == "CapCut 캐시"}
        self.assertEqual(roots, {cache / sub for sub in gc.CAPCUT_REBUILT_CACHES})
        for kept in ("effect", "artistEffect", "music", "ressdk_db", "cloudDraft"):
            self.assertFalse(any(cache / kept == root or (cache / kept) in root.parents for root in roots), kept)

    def test_low_free_space_warns_before_macos_purge(self):
        report = {"finished": "test", "free_before": 0, "free_after": 13 * 1024**3,
                  "groups": {}, "removed_bytes": 0, "errors": []}
        self.assertIn("⚠ 여유 공간 20GiB 미만", gc.notification(report))
        report["free_after"] = 25 * 1024**3
        self.assertNotIn("⚠", gc.notification(report))

    def test_monthly_preview_lists_candidates_and_deletes_nothing(self):
        # 2026-10-08 Owen 결정(Q5): 자동 삭제를 끄고 월 1회 수동 — LaunchAgent 는 미리보기만 #ops 로 보낸다
        report = {"finished": "test", "free_before": 30 * 1024**3, "free_after": 30 * 1024**3, "dry_run": True,
                  "candidate_bytes": 2 * 1024**3, "removed_bytes": 0, "errors": [],
                  "groups": {"CapCut 캐시": {"removed": 0, "bytes": 0, "eligible": 7, "kept": {}},
                             "npm 캐시": {"removed": 0, "bytes": 0, "eligible": 0, "kept": {}}}}
        message = gc.notification(report)
        self.assertIn("미리보기", message)
        self.assertIn("지울 후보: 7개 · 2.00GiB", message)
        self.assertIn("• CapCut 캐시: 7개", message)
        self.assertNotIn("npm 캐시", message)
        self.assertIn("disk-cleanup --apply", message)
        self.assertNotIn("완료", message)

    def test_launch_agent_runs_monthly_preview_only(self):
        plist = (SOURCE.parents[2] / "private_Library/private_LaunchAgents/com.owen.disk-cleanup.plist.tmpl").read_text()
        self.assertIn("<string>--dry-run</string>", plist)
        self.assertNotIn("<string>--apply</string>", plist)
        self.assertIn("<key>Day</key><integer>1</integer>", plist)


if __name__ == "__main__":
    unittest.main()
