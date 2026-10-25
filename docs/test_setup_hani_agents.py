"""일반 설정 복제 시 인증·기존 접근 제한·개인 문서를 보존하는 회귀 검사."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('setup_hani', Path(__file__).with_name('setup_hani_agents.py'))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SettingsSyncTests(unittest.TestCase):
    def test_preserves_hani_policies_hooks_and_unknown_settings(self):
        original = {'permissions': {'deny': ['Read(**/.env)']}, 'sandbox': {'enabled': True},
                    'hooks': {'Stop': []}, 'custom': 'hani'}
        source = {'permissions': {'allow': ['Read(**)']}, 'hooks': {'Stop': ['owen']},
                  'model': 'opus[1m]', 'enabledPlugins': {'ecc@ecc': True}}
        merged = setup.merge_claude(source, original)
        for key in original:
            self.assertEqual(merged[key], original[key])
        self.assertEqual(merged['enabledPlugins'], source['enabledPlugins'])
        self.assertNotIn('model', original)

    def test_toml_handles_plugin_names_and_nested_mcp_json(self):
        source = {'plugins': {'ecc@ecc': {'enabled': True}}, 'skills': {'max_context_tokens': 10000},
                  'mcp_servers': {'node_repl': {'args': [], 'env': {'SERVICES': '{"browser":"/Users/owen/.codex/x"}'}}}}
        result = setup.rehome(source)
        self.assertEqual(tomllib.loads(setup.toml_text(result)), result)
        self.assertIn('/Users/hani/.codex', result['mcp_servers']['node_repl']['env']['SERVICES'])

    def test_install_keeps_credentials_and_personal_documents_out(self):
        with tempfile.TemporaryDirectory() as temp:
            source, target = Path(temp).resolve() / 'source', Path(temp).resolve() / 'target'

            def put(home, rel, value):
                p = home / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(value)

            put(source, '.claude/settings.json', json.dumps({'model': 'opus', 'enabledPlugins': {'ecc@ecc': True}}))
            put(source, '.claude/plugins/installed_plugins.json', json.dumps({'version': 2, 'plugins': {
                'ecc@ecc': [{'scope': 'user', 'installPath': str(source / '.claude/plugins/cache/ecc')},
                            {'scope': 'project', 'projectPath': '/private/project'}]}}))
            put(source, '.codex/config.toml', 'model="gpt-6-astra"\n[plugins."ecc@ecc"]\nenabled=true\n')
            put(source, '.claude/.credentials.json', 'SOURCE_SECRET')
            put(source, '.codex/auth.json', 'SOURCE_SECRET')
            put(source, '.claude/projects/session.jsonl', 'PRIVATE_HISTORY')
            put(source, '.agents/skills/demo/SKILL.md', 'public instructions')
            put(source, '.agents/skills/demo/.env', 'SOURCE_SECRET')
            put(source, '.agents/skills/learned/SKILL.md', 'PRIVATE_LEARNING')
            for rel, marker in [('.claude/CLAUDE.md', 'claude-korean'), ('.codex/AGENTS.md', 'Codex-korean')]:
                put(source, rel, f'<!-- BEGIN dotfiles:{marker} -->\n한국어\n<!-- END dotfiles:{marker} -->')
            put(source, '.codex/packages/standalone/releases/test/bin/codex', 'fake binary')
            (source / '.codex/packages/standalone/current').symlink_to('releases/test')
            put(target, '.claude/settings.json', '{"permissions":{"deny":["Read(**/.env)"]}}')
            put(target, '.claude/.credentials.json', 'TARGET_SECRET')
            put(target, '.codex/auth.json', 'TARGET_SECRET')
            put(target, 'AGENTS.md', 'HANI_INSTRUCTIONS')
            account = SimpleNamespace(pw_dir=str(target), pw_uid=os.getuid(), pw_gid=os.getgid())
            with patch.object(setup, 'SOURCE', source), patch.object(setup, 'TARGET', target), \
                 patch('sys.argv', ['setup', '--apply']), patch('os.geteuid', return_value=0), \
                 patch('pwd.getpwnam', return_value=account), patch('os.getgrouplist', return_value=[os.getgid()]), \
                 patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, '', '')), \
                 contextlib.redirect_stdout(io.StringIO()):
                setup.main()
                setup.main()
            for rel in ['.claude/.credentials.json', '.codex/auth.json']:
                self.assertEqual((target / rel).read_text(), 'TARGET_SECRET')
            self.assertEqual((target / 'AGENTS.md').read_text(), 'HANI_INSTRUCTIONS')
            self.assertFalse((target / '.claude/projects/session.jsonl').exists())
            self.assertFalse((target / '.agents/skills/learned').exists())
            self.assertFalse((target / '.agents/skills/demo/.env').exists())
            self.assertTrue((target / '.agents/skills/demo/SKILL.md').exists())
            self.assertEqual((target / '.zshrc').read_text().count('# BEGIN dotfiles:hani-agents'), 1)
            entries = json.loads((target / '.claude/plugins/installed_plugins.json').read_text())['plugins']['ecc@ecc']
            self.assertEqual(len(entries), 1)
            self.assertTrue(entries[0]['installPath'].startswith(str(target)))
            self.assertEqual((target / '.claude-b/settings.json').resolve(), target / '.claude/settings.json')


if __name__ == '__main__':
    unittest.main()
