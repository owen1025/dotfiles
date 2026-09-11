#!/bin/bash
# Claude Code 의 Remote Control(claude.ai/code · 모바일 앱에서 이 세션 조종)을
# 세션이 열릴 때마다 자동으로 켠다.
#
#   settings.json 의 remoteControlAtStartup = "Start Remote Control bridge automatically
#   each session" (/config 의 "Enable Remote Control for all sessions" 와 같은 값).
#   유저 스코프에서만 켤 수 있다 — 프로젝트/로컬 settings 의 true 는 CLI 가 무시한다.
#
#   세션이 끝날 때의 수거는 CLI 가 알아서 한다: 종료 시 bridge teardown → 원격 세션 archive
#   (claude.ai/code 목록에서 사라짐). 터미널이 강제 종료돼 소켓이 끊긴 세션도 서버가 정리한다.
#   그래서 SessionEnd 훅 같은 별도 청소 장치는 필요 없다.
#
#   끄기       : CLAUDE_REMOTE_CONTROL_AT_STARTUP=false 로 이 스크립트를 실행 (또는 /config)
#   대상 계정  : CLAUDE_CONFIG_DIRS="$HOME/.claude $HOME/.claude-b" (기본값 = claude, claude2, claude3)
#                보조 계정의 settings.json 은 ~/.claude 로 가는 심링크라 실제 기록은 한 번뿐이다.
#   한 세션만  : claude --remote-control [이름]  /  세션 안에서 /remote-control
set -euo pipefail

eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true

VALUE="${CLAUDE_REMOTE_CONTROL_AT_STARTUP:-true}"
case "$VALUE" in
	true | 1 | yes | on) VALUE=true ;;
	false | 0 | no | off) VALUE=false ;;
	*)
		echo "ERROR: CLAUDE_REMOTE_CONTROL_AT_STARTUP 은 true/false 여야 한다 (받은 값: $VALUE)" >&2
		exit 1
		;;
esac

read -r -a CONFIG_DIRS <<<"${CLAUDE_CONFIG_DIRS:-$HOME/.claude $HOME/.claude-b $HOME/.claude-c}"

if ! command -v python3 >/dev/null 2>&1; then
	echo "WARN: python3 가 없어 Remote Control 설정을 건너뛴다" >&2
	exit 0
fi

python3 - "$VALUE" "${CONFIG_DIRS[@]}" <<'PY'
import json
import os
import sys

value = sys.argv[1] == "true"

for raw in sys.argv[2:]:
    config_dir = os.path.expanduser(raw)
    if not os.path.isdir(config_dir):
        print(f"[skip] {config_dir} — 계정 설정 디렉터리가 없다")
        continue

    # 보조 계정의 settings.json 은 ~/.claude/settings.json 심링크다. realpath 로 원본을 열어야
    # os.replace 가 심링크를 일반 파일로 바꿔치기해 공유를 끊어 버리는 일이 없다.
    path = os.path.realpath(os.path.join(config_dir, "settings.json"))
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ValueError("최상위가 JSON 객체가 아니다")
    except FileNotFoundError:
        data = {}
    except Exception as exc:  # 깨진 settings.json 을 덮어쓰지 않는다
        print(f"WARN: {path} 를 읽지 못해 건너뛴다 ({exc})", file=sys.stderr)
        continue

    if data.get("remoteControlAtStartup") == value:
        print(f"[ok] {path} — 이미 remoteControlAtStartup={json.dumps(value)}")
        continue

    data["remoteControlAtStartup"] = value
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    if os.path.exists(path):
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)
    print(f"[set] {path} — remoteControlAtStartup={json.dumps(value)}")
PY
