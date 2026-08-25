# Claude Code 듀얼 계정 — CLAUDE_CONFIG_DIR 로 크레덴셜만 격리한다.
#   계정 A = ~/.claude    → `claude`
#   계정 B = ~/.claude-b  → `claude2`  (최초 1회 `claude2` 실행 후 브라우저 로그인)
# 세션 기록·스킬·플러그인은 공유되므로, 한쪽이 리밋에 걸리면 같은 세션을 이어받을 수 있다:
#   claude --resume <id>   ↔   claude2 --resume <id>

alias claude2='CLAUDE_CONFIG_DIR=$HOME/.claude-b claude'

# ── 사용량 대시보드 ──────────────────────────────────────────────────────────
#   claude-usage          캐시 기준으로 즉시 출력
#   claude-usage -r       지금 다시 조회        (= claude-limits)
#   claude-usage --json   원본 JSON
#   --style bars|panel|compact                  (기본값 $CLAUDE_USAGE_STYLE, 없으면 bars)
alias claude-limits='claude-usage --refresh'
alias claude-status='claude-usage --refresh'   # 예전 이름 호환

# 셸 시작 시 출력. 미리 그려 둔 렌더 캐시를 cat 할 뿐이라 비용이 사실상 0이다.
# 캐시가 낡았으면 일단 출력한 뒤 백그라운드로만 갱신하므로 셸 시작이 절대 느려지지 않는다.
#   끄기: CLAUDE_USAGE_STARTUP=0   /   스타일 바꾸기: CLAUDE_USAGE_STYLE=panel
_claude_usage_startup() {
  command -v claude-usage >/dev/null 2>&1 || return 0

  local dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage"
  local style="${CLAUDE_USAGE_STYLE:-bars}"
  local cols="${COLUMNS:-100}"
  local ttl="${CLAUDE_USAGE_TTL:-300}"
  local render="$dir/render-${style}-${cols}.txt"

  if [[ -r $render ]]; then
    cat -- "$render"
    # state.json 이 ttl 보다 낡았으면 조용히 백그라운드 갱신 → 다음 셸부터 신선해진다
    local -a fresh=( "$dir"/state.json(Nms-$ttl) )
    (( $#fresh )) || ( claude-usage --refresh --quiet --style "$style" --width "$cols" &! ) 2>/dev/null
  else
    claude-usage --startup --style "$style" --width "$cols" 2>/dev/null
  fi
}

# CLAUDECODE 가드: Claude Code 가 띄우는 셸에서는 패널을 찍지 않는다.
if [[ -o interactive ]] && [[ -z "$CLAUDECODE" ]] && [[ "${CLAUDE_USAGE_STARTUP:-1}" == 1 ]]; then
  _claude_usage_startup
fi
