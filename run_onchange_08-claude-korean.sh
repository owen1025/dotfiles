#!/bin/bash
# Claude Code 가 어느 디렉터리·어느 계정(claude/claude2/claude3)에서 떠도 한국어로 답하게 한다.
# (2026-09-27: Fable 은 괜찮은데 Opus 5.5 가 가끔 영어로 답하는 문제)
#
# 두 겹으로 건다:
#   1) settings.json "language": "korean" — CLI 공식 설정(/config 의 Language). 시스템 프롬프트에 들어간다.
#      보조 계정의 settings.json 은 ~/.claude 로 가는 심링크라 실제 기록은 한 번뿐이다.
#   2) 유저 메모리 <configdir>/CLAUDE.md 의 관리 블록 — 모든 프로젝트에서 읽히는 전역 지시.
#      ~/.claude/CLAUDE.md 가 원본, -b/-c 는 심링크(dot_claude-accounts.zsh 의 _claude_alt 도 매 호출 확인).
#      블록 밖에 손으로 적은 내용은 건드리지 않는다.
#
#   대상 계정 : CLAUDE_CONFIG_DIRS="$HOME/.claude $HOME/.claude-b" (기본값 = claude, claude2, claude3)
#   문구를 바꾸면 이 파일 내용이 바뀌므로 chezmoi apply 때 다시 돈다.
set -euo pipefail

read -r -a CONFIG_DIRS <<<"${CLAUDE_CONFIG_DIRS:-$HOME/.claude $HOME/.claude-b $HOME/.claude-c}"

if ! command -v python3 >/dev/null 2>&1; then
	echo "WARN: python3 가 없어 Claude 한국어 설정을 건너뛴다" >&2
	exit 0
fi

python3 - "${CONFIG_DIRS[@]}" <<'PY'
import json
import os
import sys

BEGIN = "<!-- BEGIN dotfiles:claude-korean (run_onchange_08-claude-korean.sh 가 관리) -->"
END = "<!-- END dotfiles:claude-korean -->"
BLOCK = f"""{BEGIN}
# 응답 언어 — 한국어 (가드레일)

- 사용자에게 보이는 모든 텍스트는 **한국어**로 쓴다: 답변, 진행 상황 안내, 질문, 요약, 계획, 에러 설명, 최종 보고.
- 사용자가 영어로 묻거나, 읽은 파일·도구 출력·에러 메시지·문서가 영어여도 답은 한국어로 한다.
- 긴 작업 중간이나 컨텍스트 요약(compaction) 뒤에도 영어로 넘어가지 않는다.
- 코드, 명령어, 파일 경로, 식별자, 로그·에러 원문 인용은 원래 언어 그대로 두고, 설명만 한국어로 한다.
- 커밋 메시지·코드 주석·문서는 해당 repo 의 기존 컨벤션(AGENTS.md 등)을 따른다.
- 사용자가 명시적으로 다른 언어를 요청했을 때만 그 언어로 바꾼다.
{END}
"""

home_claude = os.path.expanduser("~/.claude")


def set_language(config_dir):
    # 심링크를 일반 파일로 바꿔치기하지 않게 realpath 원본에 쓴다.
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
        return
    if data.get("language") == "korean":
        print(f"[ok] {path} — 이미 language=korean")
        return
    data["language"] = "korean"
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    if os.path.exists(path):
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)
    print(f"[set] {path} — language=korean")


def write_block(path):
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError:
        text = ""
    if BEGIN in text and END in text:
        head, rest = text.split(BEGIN, 1)
        tail = rest.split(END, 1)[1].lstrip("\n")
        new = head + BLOCK + ("\n" + tail if tail else "")
    else:
        new = BLOCK + ("\n" + text if text else "")
    if new == text:
        print(f"[ok] {path} — 한국어 블록 최신")
        return
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(new)
    os.replace(tmp, path)
    print(f"[set] {path} — 한국어 블록 기록")


primary_md = os.path.join(home_claude, "CLAUDE.md")
if os.path.isdir(home_claude):
    write_block(primary_md)

for raw in sys.argv[1:]:
    config_dir = os.path.expanduser(raw)
    if not os.path.isdir(config_dir):
        print(f"[skip] {config_dir} — 계정 설정 디렉터리가 없다")
        continue
    set_language(config_dir)
    if os.path.realpath(config_dir) == os.path.realpath(home_claude):
        continue
    md = os.path.join(config_dir, "CLAUDE.md")
    if os.path.islink(md):
        print(f"[ok] {md} — 심링크")
    elif os.path.exists(md):
        # 계정별로 따로 쓰던 파일이면 공유로 바꾸지 않고 블록만 넣는다.
        write_block(md)
    else:
        os.symlink(primary_md, md)
        print(f"[link] {md} -> {primary_md}")
PY
