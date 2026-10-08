#!/bin/bash
# Claude Code 대화 기록 보존 기간을 365일로 늘린다 (2026-10-08 Owen 결정, 편집 자동화 재검토 Q8).
#
# 기본값은 30일이라 30일 지난 세션 jsonl 이 자동으로 지워진다. 09-07 편집 자동화 PRD 인터뷰 세션 원본이 이렇게 사라졌고,
# 재검토가 근거로 쓴 09-23~10-01 세션도 10-23 부터 지워질 참이었다.
# 보조 계정(-b, -c)의 settings.json 은 ~/.claude 로 가는 심링크라 realpath 원본에 한 번만 쓴다. 다른 키는 건드리지 않는다.
# 값을 바꾸면 이 파일 내용이 바뀌므로 chezmoi apply 때 다시 돈다.
set -euo pipefail

read -r -a CONFIG_DIRS <<<"${CLAUDE_CONFIG_DIRS:-$HOME/.claude $HOME/.claude-b $HOME/.claude-c}"

if ! command -v python3 >/dev/null 2>&1; then
	echo "WARN: python3 가 없어 Claude 대화 기록 보존 설정을 건너뛴다" >&2
	exit 0
fi

python3 - "${CONFIG_DIRS[@]}" <<'PY'
import json
import os
import sys

DAYS = 365
done = set()
for config_dir in sys.argv[1:]:
    path = os.path.realpath(os.path.join(config_dir, "settings.json"))
    if path in done or not os.path.isdir(os.path.dirname(path)):
        continue
    done.add(path)
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
    if data.get("cleanupPeriodDays") == DAYS:
        print(f"[ok] {path} — 이미 cleanupPeriodDays={DAYS}")
        continue
    data["cleanupPeriodDays"] = DAYS
    tmp = path + ".tmp-retention"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    print(f"[set] {path} — cleanupPeriodDays={DAYS}")
PY
