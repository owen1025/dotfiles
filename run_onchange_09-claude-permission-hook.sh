#!/bin/bash
# claude-permission-hook(~/.local/bin)을 공유 settings.json 의 PermissionRequest 훅으로 등록한다.
#
#   2026-09-27: 보조 계정 세션(quote-contract-docs-update)의 ~/.claude-b/projects/…/memory 쓰기가
#   auto mode 인데도 권한 프롬프트로 떴다 — 훅 스크립트는 있었지만 등록이 안 돼 있었다.
#   판정 기준은 스크립트 docstring, 기록은 ~/.local/state/claude-permission-hook/decisions.log.
#
#   끄기(일시) : CLAUDE_PERMISSION_HOOK=0 로 claude 실행
#   끄기(영구) : CLAUDE_PERMISSION_HOOK_REGISTER=0 로 이 스크립트 실행 → 항목 제거
#   보조 계정의 settings.json 은 ~/.claude 로 가는 심링크라 실제 기록은 한 번뿐이다.
#   다른 도구가 넣은 PermissionRequest 항목(orca 등)은 건드리지 않는다.
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
	echo "WARN: python3 가 없어 권한 훅 등록을 건너뛴다" >&2
	exit 0
fi

python3 - "${CLAUDE_PERMISSION_HOOK_REGISTER:-1}" <<'PY'
import json
import os
import sys

register = sys.argv[1] not in ("0", "false", "no", "off")
COMMAND = "$HOME/.local/bin/claude-permission-hook"
path = os.path.realpath(os.path.expanduser("~/.claude/settings.json"))

try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError("최상위가 JSON 객체가 아니다")
except FileNotFoundError:
    data = {}
except Exception as exc:  # 깨진 settings.json 을 덮어쓰지 않는다
    print(f"WARN: {path} 를 읽지 못해 건너뛴다 ({exc})", file=sys.stderr)
    sys.exit(0)


def ours(group):
    return any("claude-permission-hook" in h.get("command", "") for h in group.get("hooks", []))


groups = data.setdefault("hooks", {}).setdefault("PermissionRequest", [])
present = any(ours(g) for g in groups)

if register and present:
    print(f"[ok] {path} — PermissionRequest 훅 이미 등록")
    sys.exit(0)
if not register and not present:
    print(f"[ok] {path} — PermissionRequest 훅 없음")
    sys.exit(0)

if register:
    groups.append({"matcher": "*", "hooks": [{"type": "command", "command": COMMAND, "timeout": 10}]})
else:
    data["hooks"]["PermissionRequest"] = [g for g in groups if not ours(g)]

tmp = f"{path}.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
if os.path.exists(path):
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
os.replace(tmp, path)
print(f"[{'set' if register else 'unset'}] {path} — PermissionRequest 훅 {'등록' if register else '제거'}")
PY
