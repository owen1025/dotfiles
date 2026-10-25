#!/usr/bin/env python3
"""관리자가 하니의 셸·Claude/Codex 공통 설정을 맞춘다. 인증·대화는 복사하지 않는다.

sudo python3 docs/setup_hani_agents.py --apply [--login]
기본은 변경 계획만 출력한다. --login은 설치 뒤 하니 계정으로 두 CLI의 공식 로그인을 실행한다.
"""
from __future__ import annotations

import argparse
import copy
import datetime
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import shlex
import subprocess
import sys
import tempfile
import tomllib

SOURCE = Path('/Users/owen')
TARGET = Path('/Users/hani')
ROOT = Path(__file__).resolve().parents[1]
CLAUDE_KEYS = (
    'cleanupPeriodDays', 'model', 'effortLevel', 'language', 'modelSettings',
    'autoUpdatesChannel', 'tui', 'theme', 'switchModelsOnFlag',
    'remoteControlAtStartup', 'agentPushNotifEnabled', 'enabledPlugins',
    'extraKnownMarketplaces', 'statusLine',
)
CODEX_KEYS = (
    'model', 'model_reasoning_effort', 'service_tier', 'skills',
    'plugins', 'marketplaces', 'mcp_servers',
)
IGNORE = shutil.ignore_patterns('.git', '.trash', 'learned', '__pycache__',
                               '*.bak*', '.env', '.env.*', 'auth.json', '.credentials.json')


def rehome(value, source=None, target=None):
    source, target = source or SOURCE, target or TARGET
    if isinstance(value, str):
        return value.replace(str(source), str(target))
    if isinstance(value, dict):
        return {rehome(k, source, target): rehome(v, source, target) for k, v in value.items()}
    if isinstance(value, list):
        return [rehome(v, source, target) for v in value]
    return value


def merge_claude(source, target):
    """기존 하니 permissions/sandbox/hooks를 보존하고 일반 설정만 동기화한다."""
    result = copy.deepcopy(target)
    for key in CLAUDE_KEYS:
        if key in source:
            result[key] = rehome(source[key])
    return result


def toml_text(data):
    """CLI 설정에서 쓰는 문자열·숫자·배열·테이블을 TOML로 쓴다."""
    lines = []

    def scalar(v):
        if isinstance(v, (str, bool, int, float)):
            return json.dumps(v, ensure_ascii=False)
        if isinstance(v, list):
            return '[' + ', '.join(scalar(x) for x in v) + ']'
        raise TypeError(f'지원하지 않는 TOML 값: {type(v).__name__}')

    def table(obj, path=()):
        if path:
            lines.append('[' + '.'.join(json.dumps(x) for x in path) + ']')
        for k, v in obj.items():
            if not isinstance(v, dict):
                lines.append(f'{json.dumps(k)} = {scalar(v)}')
        lines.append('')
        for k, v in obj.items():
            if isinstance(v, dict):
                table(v, (*path, k))

    table(data)
    text = '\n'.join(lines)
    assert tomllib.loads(text) == data
    return text


def login_accounts(email, report_path=None):
    """공식 CLI를 실제 하니 로그인 셸에서 실행한다. 실패는 설치와 분리해 기록한다."""
    report = json.loads(report_path.read_text()) if report_path and report_path.exists() else {}
    outcomes = {}
    for label, command in (
        ('claude2', 'CLAUDE_CONFIG_DIR="$HOME/.claude-b" command claude auth login --claudeai --email ' + shlex.quote(email)),
        ('codex', 'command codex login --device-auth'),
    ):
        print(f'\n하니 {label} 공식 로그인 — {email if label == "claude2" else "사용할 ChatGPT 계정을 선택하세요"}', flush=True)
        env = {**os.environ, 'CLAUDE_USAGE_STARTUP': '0', 'SYS_USAGE_STARTUP': '0',
               'TERM': os.environ.get('TERM', 'xterm-256color')}
        process = subprocess.Popen(['/usr/bin/sudo', '-H', '-u', 'hani', '/bin/zsh', '-lc', command],
                                   env=env, cwd=TARGET, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = []
        while char := process.stdout.read(1):
            sys.stdout.buffer.write(char)
            sys.stdout.buffer.flush()
            output.append(char)
        code = process.wait()
        # 로그인 URL·인증 코드·토큰은 결과 파일에 남기지 않는다.
        text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', b''.join(output).decode(errors='replace'))
        errors = [line for line in text.splitlines()
                  if re.search(r'error|failed|unknown option|permission denied|오류|실패', line, re.I)]
        errors = [re.sub(r'https?://\S+|[A-Za-z0-9_+#=/.-]{24,}', '[비공개 값 생략]', line)[:500]
                  for line in errors[-5:]]
        outcomes[label] = {'exit_code': code, 'errors': errors}
        if code:
            print(f'\n{label} 로그인 미완료(종료 코드 {code}). 설치된 설정은 유지됩니다.', flush=True)
        report['login_results'] = outcomes
        report['logins_completed'] = len(outcomes) == 2 and all(v['exit_code'] == 0 for v in outcomes.values())
        if report_path:
            fd, tmp = tempfile.mkstemp(prefix='.agent-login-report-', dir=report_path.parent)
            with os.fdopen(fd, 'w') as f:
                json.dump(report, f, ensure_ascii=False, indent=2)
            os.chown(tmp, int(os.environ.get('SUDO_UID', '0')), int(os.environ.get('SUDO_GID', '0')))
            os.replace(tmp, report_path)
    result = subprocess.run(['/usr/bin/sudo', '-H', '-u', 'hani', '/bin/zsh', '-lc',
                             'export CLAUDE_USAGE_ACCOUNTS="claude:$HOME/.claude,claude2:$HOME/.claude-b"; '
                             'export CLAUDE_USAGE_CHATGPT="chatgpt:$HOME/.codex"; '
                             'command claude-usage -r --style compact'],
                            env={**os.environ, 'CLAUDE_USAGE_STARTUP': '0', 'SYS_USAGE_STARTUP': '0'},
                            cwd=TARGET, capture_output=True, text=True, timeout=30)
    print(result.stdout)
    if report_path:
        # 앞에서 만든 관리자 소유 일반 파일만 갱신한다.
        report['usage_panel'] = result.stdout
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    return all(v['exit_code'] == 0 for v in outcomes.values())


def main():
    global SOURCE, TARGET
    SOURCE, TARGET = SOURCE.resolve(), TARGET.resolve()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--login', action='store_true')
    ap.add_argument('--login-only', action='store_true', help='설치를 반복하지 않고 하니 로그인만 재시도')
    ap.add_argument('--email', help='새 Claude 계정 이메일(--login 사용 시 필수)')
    ap.add_argument('--report', type=Path, help='관리자가 읽을 검증 결과 파일(토큰 값 제외)')
    args = ap.parse_args()
    if (args.login or args.login_only) and not args.email:
        ap.error('--login에는 --email이 필요합니다.')
    if args.login_only:
        if os.geteuid() != 0:
            raise SystemExit('하니 사용자로 로그인하려면 sudo로 실행해야 합니다.')
        raise SystemExit(0 if login_accounts(args.email, args.report) else 1)
    if not args.apply:
        print('하니: claude/claude2/Codex 3행, Claude 일반 설정·플러그인, Codex CLI·설정·플러그인 설치')
        print('인증·대화·메모리·기존 권한·스튜디오 안내·개인 알림 설정은 복사하거나 덮어쓰지 않음')
        print('적용: sudo python3 docs/setup_hani_agents.py --apply --login --email <새 계정 이메일>')
        return
    if os.geteuid() != 0:
        raise SystemExit('하니 홈에 기록하려면 이 명령을 sudo로 실행해야 합니다.')
    account = pwd.getpwnam('hani')
    if Path(account.pw_dir).resolve() != TARGET:
        raise SystemExit('하니 홈 경로가 예상과 다릅니다.')
    stamp = datetime.datetime.now().strftime('%Y%m%d%H%M%S')
    changed = []

    def own(path):
        os.chown(path, account.pw_uid, account.pw_gid, follow_symlinks=False)

    def directory(path):
        missing = []
        p = path
        while not p.exists():
            missing.append(p)
            p = p.parent
        for p in reversed(missing):
            p.mkdir(mode=0o700)
            own(p)

    def checked(path):
        if not path.resolve().is_relative_to(TARGET):
            raise RuntimeError(f'하니 홈 밖으로 향하는 경로: {path}')
        return path.resolve()

    def write(rel, content, mode=0o600):
        path = checked(TARGET / rel)
        directory(path.parent)
        if path.exists() and path.read_text() == content:
            return
        if path.exists():
            backup = path.with_name(path.name + '.bak.agent-setup-' + stamp)
            shutil.copy2(path, backup)
            own(backup)
        tmp = path.with_name(path.name + '.tmp.agent-setup')
        tmp.write_text(content)
        tmp.chmod(mode)
        own(tmp)
        os.replace(tmp, path)
        changed.append(str(path.relative_to(TARGET)))

    def write_json(rel, value):
        write(rel, json.dumps(value, ensure_ascii=False, indent=2) + '\n')

    def load_json(path):
        return json.loads(path.read_text()) if path.exists() else {}

    def copy_artifact(rel):
        src, dst = SOURCE / rel, checked(TARGET / rel)
        if not src.exists():
            return
        directory(dst.parent)
        if src.is_dir():
            # 관리자 실행에서도 기존 심링크를 통해 다른 사용자·시스템 파일을 덮지 않는다.
            if dst.exists():
                for base, dirs, files in os.walk(dst):
                    for name in dirs + files:
                        checked(Path(base) / name)
            # 재설치 가능한 공개 코드만 대상. 사용자 데이터 디렉터리는 호출 목록에 없다.
            shutil.copytree(src, dst, symlinks=True, dirs_exist_ok=True, ignore=IGNORE)
            for base, dirs, files in os.walk(dst):
                own(base)
                for name in dirs + files:
                    p = Path(base) / name
                    if p.is_symlink():
                        link = str(p.readlink())
                        new = rehome(link)
                        if new != link:
                            p.unlink()
                            p.symlink_to(new)
                    own(p)
        else:
            if dst.exists():
                backup = dst.with_name(dst.name + '.bak.agent-setup-' + stamp)
                shutil.copy2(dst, backup)
                own(backup)
            shutil.copy2(src, dst)
            own(dst)
        changed.append(rel)

    source_claude = load_json(SOURCE / '.claude/settings.json')
    previous_claude = load_json(TARGET / '.claude/settings.json')
    source_codex = tomllib.loads((SOURCE / '.codex/config.toml').read_text())
    target_codex_path = TARGET / '.codex/config.toml'
    target_codex = tomllib.loads(target_codex_path.read_text()) if target_codex_path.exists() else {}
    for key in CODEX_KEYS:
        if key in source_codex:
            target_codex[key] = rehome(source_codex[key])

    for rel in (
        '.claude/plugins/cache', '.claude/plugins/marketplaces',
        '.codex/plugins/cache', '.codex/.tmp/bundled-marketplaces/openai-bundled',
        '.cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime',
        '.codex/computer-use/Codex Computer Use.app',
        '.agents/skills', '.claude/skills', '.codex/skills',
        '.claude/statusline-command.sh',
    ):
        copy_artifact(rel)
    installed = load_json(SOURCE / '.claude/plugins/installed_plugins.json')
    installed['plugins'] = {
        name: [rehome(entry) for entry in entries if entry.get('scope') == 'user']
        for name, entries in installed.get('plugins', {}).items()
        if any(e.get('scope') == 'user' for e in entries)
    }
    write_json('.claude/plugins/installed_plugins.json', installed)
    write_json('.claude/plugins/known_marketplaces.json',
               rehome(load_json(SOURCE / '.claude/plugins/known_marketplaces.json')))
    write_json('.claude/settings.json', merge_claude(source_claude, previous_claude))
    write('.codex/config.toml', toml_text(target_codex))

    # 한국어 지시만 추가한다. 하니의 홈 AGENTS.md/CLAUDE.md와 스튜디오 문서는 유지한다.
    for rel, marker in [('.claude/CLAUDE.md', 'claude-korean'), ('.codex/AGENTS.md', 'Codex-korean')]:
        source_text = (SOURCE / rel).read_text()
        block = re.search(r'<!-- BEGIN dotfiles:' + marker + r'.*?<!-- END dotfiles:' + marker + r' -->',
                          source_text, flags=re.S).group()
        path = TARGET / rel
        previous = path.read_text() if path.exists() else ''
        if f'<!-- BEGIN dotfiles:{marker}' not in previous:
            write(rel, block + '\n\n' + previous)

    write('.claude-accounts.zsh', (ROOT / 'dot_claude-accounts.zsh').read_text(), 0o644)
    for name in ('claude-usage', 'sys-usage', 'claude-autoupdate-guard'):
        write('.local/bin/' + name, (ROOT / ('private_dot_local/bin/executable_' + name)).read_text(), 0o755)
    # Codex는 같은 릴리스의 공개 실행 패키지만 복사한다(auth.json 등은 건드리지 않는다).
    release = (SOURCE / '.codex/packages/standalone/current').resolve()
    copy_artifact(str(release.relative_to(SOURCE)))
    codex_bin = TARGET / '.local/bin/codex'
    if codex_bin.exists() or codex_bin.is_symlink():
        codex_bin.rename(codex_bin.with_name('codex.bak.agent-setup-' + stamp))
    codex_bin.symlink_to(TARGET / release.relative_to(SOURCE) / 'bin/codex')
    own(codex_bin)

    secondary = TARGET / '.claude-b'
    directory(secondary)
    for name in ('projects', 'file-history', 'skills', 'plugins', 'settings.json', 'CLAUDE.md'):
        path = secondary / name
        expected = TARGET / '.claude' / name
        if path.exists() or path.is_symlink():
            if not path.is_symlink() or path.resolve() != expected.resolve():
                raise RuntimeError(f'기존 파일을 자동 병합할 수 없습니다: {path}')
        else:
            path.symlink_to(expected)
            own(path)
    profile = TARGET / '.zshrc'
    previous = profile.read_text() if profile.exists() else ''
    begin, end = '# BEGIN dotfiles:hani-agents', '# END dotfiles:hani-agents'
    block = '''# BEGIN dotfiles:hani-agents
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
export CLAUDE_USAGE_ACCOUNTS="claude:$HOME/.claude,claude2:$HOME/.claude-b"
export CLAUDE_USAGE_CHATGPT="chatgpt:$HOME/.codex"
if [[ -o interactive && -t 1 && -z "$CLAUDECODE" ]]; then
  [[ "${SYS_USAGE_STARTUP:-1}" == 1 ]] && command sys-usage --startup --style "${CLAUDE_USAGE_STYLE:-bars}" --width "${COLUMNS:-100}" 2>/dev/null
fi
[[ -f "$HOME/.claude-accounts.zsh" ]] && source "$HOME/.claude-accounts.zsh"
# END dotfiles:hani-agents'''
    if begin in previous:
        previous = re.sub(re.escape(begin) + '.*?' + re.escape(end), lambda _: block, previous, flags=re.S)
    else:
        previous = previous.rstrip() + '\n\n' + block + '\n'
    write('.zshrc', previous, 0o644)

    env = {'HOME': str(TARGET), 'USER': 'hani', 'LOGNAME': 'hani', 'LANG': 'ko_KR.UTF-8',
           'PATH': f'{TARGET}/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
           'CLAUDE_USAGE_STARTUP': '0', 'CLAUDE_USAGE_ACCOUNTS': f'claude:{TARGET}/.claude,claude2:{secondary}',
           'CLAUDE_USAGE_CHATGPT': f'chatgpt:{TARGET}/.codex', 'CLAUDE_USAGE_RETRY': '0'}

    def run(command, **kwargs):
        return subprocess.run(command, env=env, cwd=TARGET, user=account.pw_uid,
                              group=account.pw_gid, extra_groups=os.getgrouplist('hani', account.pw_gid), **kwargs)

    report = {'changed': changed, 'claude_common_settings_equal': True,
              'codex_common_settings_equal': True, 'claude_permissions_preserved': True,
              'claude_plugins': list(source_claude.get('enabledPlugins', {})),
              'codex_plugins': list(target_codex.get('plugins', {})),
              'accounts': ['claude', 'claude2', 'chatgpt']}
    after = load_json(TARGET / '.claude/settings.json')
    assert all(after.get(k) == rehome(source_claude.get(k)) for k in CLAUDE_KEYS)
    assert all(after.get(k) == previous_claude.get(k) for k in ('permissions', 'sandbox', 'hooks'))
    for cmd in [ ['/bin/zsh', '-n', str(profile)], [str(codex_bin), '--version'],
                 [str(TARGET / '.local/bin/claude'), 'plugin', 'list', '--json'] ]:
        result = run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError(f'검증 실패: {cmd[0]} ({result.returncode}) {result.stderr[:300]}')
    usage = run([str(TARGET / '.local/bin/claude-usage'), '-r', '--style', 'compact'],
                capture_output=True, text=True, timeout=30)
    report['usage_panel'] = usage.stdout
    write_json('.local/state/agent-settings-sync/report.json', report)

    def export_report():
        if not args.report:
            return
        fd, tmp = tempfile.mkstemp(prefix='.agent-report-', dir=args.report.parent)
        with os.fdopen(fd, 'w') as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        os.chown(tmp, int(os.environ.get('SUDO_UID', '0')), int(os.environ.get('SUDO_GID', '0')))
        os.replace(tmp, args.report)

    export_report()
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if args.login:
        raise SystemExit(0 if login_accounts(args.email, args.report) else 1)


if __name__ == '__main__':
    main()
