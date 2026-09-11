# Claude Code 다중 계정 — CLAUDE_CONFIG_DIR 로 크레덴셜만 격리한다.
#   계정 A = ~/.claude    → `claude`   (myartame)
#   계정 B = ~/.claude-b  → `claude2`  (owenchoi1025)
#   계정 C = ~/.claude-c  → `claude3`  (2026-09-11 결제 — 디렉터리·공유 심링크는 만들어 뒀다.
#                                      최초 1회 `claude3` 실행 = 브라우저 로그인)
#   새 계정 추가 = 아래 `claude4() { _claude_alt "$HOME/.claude-d" "$@" }` 한 줄.
#
# 공유(심링크): projects(세션 트랜스크립트 + 자동 메모리) · file-history · skills · plugins · settings.json
# 격리(계정별): 크레덴셜 · <configdir>/.claude.json · history.jsonl
#   (크레덴셜은 macOS 에선 키체인 `Claude Code-credentials-<sha256(configdir)[:8]>`, 그 외 OS 는 .credentials.json.
#    셸 시작 패널(claude-usage)도 같은 곳을 읽으므로 파일이 없어도 "미로그인" 으로 뜨지 않는다.)
#
# 한쪽이 리밋에 걸리면 세션 id 로 이어받는다:
#   claude --resume <id>   ↔   claude2 --resume <id>   ↔   claude3 --resume <id>
# ⚠️ --continue / -c 는 계정별 .claude.json 의 lastSessionId 를 보므로 교차로 안 먹는다. 반드시 id 로 resume.
#
# 세션은 $CLAUDE_CONFIG_DIR/projects/<cwd-슬러그>/<id>.jsonl 에 저장된다. 이 링크가 끊기면
# (claude-b 재생성·재설치) 상대 계정 세션이 통째로 "No conversation found" 가 되므로 매 호출마다 확인한다.

# ── 세션별 프롬프트 바 색상 ──────────────────────────────────────────────────
# claude 를 "프롬프트 없이" 띄우면 시작 인자로 `/color <색>` 을 붙여, 세션마다 입력
# 상자 테두리 색이 달라지게 한다. /color 는 로컬 슬래시 명령이라 API 호출도
# 토큰 소모도 없다. (사용 가능한 색: red blue green yellow purple orange pink cyan)
#
# 색은 랜덤이되, 지금 살아 있는 다른 셸이 예약한 색은 피한다 → 동시에 띄운
# 세션끼리 색이 겹치지 않는다. 8개를 다 쓰면 그때부터 전체 팔레트에서 다시 뽑는다.
#
#   끄기      CLAUDE_AUTO_COLOR=0
#   고정      CLAUDE_FORCE_COLOR=cyan       (예: 운영 서버용 셸은 늘 빨강)
#   팔레트    CLAUDE_COLOR_PALETTE=(red cyan)
: ${CLAUDE_COLOR_DIR:="/tmp/claude-session-colors-${UID}"}
typeset -ga CLAUDE_COLOR_PALETTE
(( $#CLAUDE_COLOR_PALETTE )) || CLAUDE_COLOR_PALETTE=(red blue green yellow purple orange pink cyan)

# 살아 있는 세션이 안 쓰는 색 하나를 골라 $$ 이름으로 예약하고 $REPLY 에 담는다.
# ($RANDOM 이 서브셸에서 늘 같은 값을 내주므로 command substitution 을 쓰지 않는다)
_claude_pick_color() {
  emulate -L zsh
  local -a palette=($CLAUDE_COLOR_PALETTE)
  (( $#palette )) || return 1
  if [[ -n $CLAUDE_FORCE_COLOR ]]; then
    REPLY=$CLAUDE_FORCE_COLOR
    return 0
  fi
  if ! mkdir -p -- "$CLAUDE_COLOR_DIR" 2>/dev/null; then
    REPLY=${palette[RANDOM % ${#palette} + 1]}
    return 0
  fi

  local f pid
  # 예약 파일 이름은 그 셸의 PID. 셸이 죽었으면 색을 회수한다.
  for f in "$CLAUDE_COLOR_DIR"/*.color(N); do
    pid=${${f:t}%.color}
    [[ $pid == <-> ]] && kill -0 "$pid" 2>/dev/null || rm -f -- "$f"
  done

  local -A used
  for f in "$CLAUDE_COLOR_DIR"/*.color(N); do used[$(<"$f")]=1; done
  local c; local -a free
  for c in $palette; do (( ${+used[$c]} )) || free+=("$c"); done
  (( $#free )) || free=($palette)

  local n=$#free
  REPLY=${free[RANDOM % n + 1]}
  print -r -- "$REPLY" >| "$CLAUDE_COLOR_DIR/$$.color" 2>/dev/null
  return 0
}

# 시작 인자 끝에 `/color …` 를 덧붙여도 안전한 호출인지 판정한다.
# 서브커맨드·사용자 프롬프트가 이미 있거나, 뒤따르는 위치인자를 삼켜 버리는
# 플래그(-r, -w, --tools …)가 섞여 있으면 아무것도 하지 않는다.
_claude_wants_color() {
  emulate -L zsh
  [[ ${CLAUDE_AUTO_COLOR:-1} == 1 ]] || return 1
  [[ -t 0 && -t 1 ]] || return 1            # TUI 가 아니면 의미 없음
  local -a one=(                            # 값 하나를 먹는 플래그
    --agent --agents --append-system-prompt --append-system-prompt-file
    --autocompact --debug-file --effort --environment --fallback-model
    --input-format --json-schema --max-budget-usd --model -n --name
    --output-format --permission-mode --plugin-dir --plugin-url
    --remote-control-session-name-prefix --session-id --setting-sources
    --settings --system-prompt --system-prompt-file
  )
  local -a stop=(
    -p --print -h --help -v --version                     # TUI 가 아님
    -c --continue -r --resume --teleport --from-pr        # 기존 세션 색을 유지
    --cloud -w --worktree -d --debug --prompt-suggestions # 값이 선택적 → 위치인자를 삼킴
    --remote-control --rc --bg --background
    --add-dir --allowedTools --allowed-tools --tools      # 가변 인자 → 위치인자를 삼킴
    --disallowedTools --disallowed-tools --betas --file --mcp-config
  )
  local a skip=0
  for a in "$@"; do
    (( skip )) && { skip=0; continue }
    [[ $a == -- ]] && return 1
    (( ${stop[(Ie)$a]} )) && return 1
    [[ $a == --*=* ]] && continue
    (( ${one[(Ie)$a]} )) && { skip=1; continue }
    [[ $a == -* ]] && continue
    return 1                                # 맨 토큰 = 서브커맨드 또는 사용자 프롬프트
  done
  return 0
}

# claude / claude2 공통 진입점. $1 = CLAUDE_CONFIG_DIR (없으면 기본 계정)
_claude_launch() {
  emulate -L zsh
  local cfg=$1; shift
  # 설치/업데이트 중에는 PATH 에서 실행파일이 잠깐 사라진다. 그때 Homebrew 의
  # command_not_found_handler 가 "$*" 를 통째로 찍는 바람에
  # `command not found: claude /color orange` 처럼 보여 원인이 가려진다 → 여기서 먼저 잡는다.
  if ! whence -p claude >/dev/null 2>&1; then
    print -u2 "claude: PATH 에 실행파일이 없다 (설치/업데이트 중일 수 있다). 잠시 뒤 다시 시도할 것."
    return 127
  fi
  local -a args=("$@")
  local color='' REPLY=''
  if _claude_wants_color "$@" && _claude_pick_color && [[ -n $REPLY ]]; then
    color=$REPLY
    args+=("/color $color")
  fi
  local rc=0
  if [[ -n $cfg ]]; then
    CLAUDE_CONFIG_DIR=$cfg command claude "${args[@]}"
  else
    command claude "${args[@]}"
  fi
  rc=$?
  [[ -n $color ]] && rm -f -- "$CLAUDE_COLOR_DIR/$$.color" 2>/dev/null
  return $rc
}

claude() { _claude_launch '' "$@" }

# 보조 계정 공통 진입점. $1 = 그 계정의 CLAUDE_CONFIG_DIR. 디렉터리가 없으면 만들고
# (첫 실행 = 온보딩 + 로그인), 공유 심링크 5개를 호출마다 확인한다.
_claude_alt() {
  emulate -L zsh
  local b=$1 d; shift
  mkdir -p -- "$b"
  for d in projects file-history skills plugins settings.json; do
    if [[ -L $b/$d ]]; then
      continue
    elif [[ -e $b/$d ]]; then
      print -u2 "${b:t}: $b/$d 가 심링크가 아니다 — ~/.claude 와 분리됨. 병합 후 ln -s 할 것."
    else
      ln -s "$HOME/.claude/$d" "$b/$d"
    fi
  done
  _claude_launch "$b" "$@"
}

claude2() { _claude_alt "$HOME/.claude-b" "$@" }
claude3() { _claude_alt "$HOME/.claude-c" "$@" }

# ── 사용량 대시보드 ──────────────────────────────────────────────────────────
#   claude-usage          캐시 기준으로 즉시 출력 (계정은 ~/.claude-* 자동 발견: -b→claude2, -c→claude3.
#                         디렉터리만 있고 로그인 전이면 "미로그인" 줄로 뜬다 — 남은 할 일이 로그인뿐이란 뜻)
#                         + ChatGPT 계정 한 줄(2026-09-08): Codex CLI 로그인(~/.codex/auth.json)을 읽기만 해서
#                           주간(플랜에 따라 5시간도) 한도를 같은 패널에 그린다. 끄기 CLAUDE_USAGE_CHATGPT=0,
#                           다른 CODEX_HOME 은 CLAUDE_USAGE_CHATGPT="chatgpt:~/.codex-b". 토큰 만료면 `codex` 한 번.
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

  local dir="${CLAUDE_USAGE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage}"
  local style="${CLAUDE_USAGE_STYLE:-bars}"
  local cols="${COLUMNS:-100}"
  local ttl="${CLAUDE_USAGE_TTL:-300}"
  local stale_max="${CLAUDE_USAGE_STALE_MAX:-86400}"
  local render="$dir/render-${style}-${cols}.txt"

  if [[ -r $render ]]; then
    zmodload zsh/datetime
    zmodload zsh/stat
    local -A cache_stat
    local age=$(( stale_max + 1 ))
    if zstat -H cache_stat -- "$dir/state.json" 2>/dev/null; then
      age=$(( EPOCHSECONDS - cache_stat[mtime] ))
    fi
    # `command cat`: zshrc 의 cat() 은 tty 면 bat 으로 감싼다 — bat 은 테마 감지로 터미널에 색상 질의
    # (OSC 10/11·DA1)를 보내고 늦게 온 응답이 프롬프트 입력줄에 찍히며, 화면보다 길면 페이저까지 연다
    # (2026-09-08 "새 셸의 커서가 다른 인풋에 들어가 있다" 실측 원인). 렌더 캐시는 이미 색을 품고 있다.
    if (( age <= stale_max )); then
      command cat -- "$render"
    fi
    if (( age >= ttl )); then
      if (( age <= stale_max )); then
        print -r -- ' ⚠ 이전 조회값 · 백그라운드 갱신 중 (`claude-usage -r` 즉시 조회)'
      else
        print -r -- ' ⚠ 오래된 사용량 숨김 · 백그라운드 갱신 중 (`claude-usage -r` 즉시 조회)'
      fi
      # --startup 이 갱신 락을 잡는다. 여러 셸을 열어도 API 갱신은 하나만 실행.
      ( command claude-usage --startup --quiet --style "$style" --width "$cols" &! ) 2>/dev/null
    fi
  else
    claude-usage --startup --style "$style" --width "$cols" 2>/dev/null
  fi
}

# CLAUDECODE 가드: Claude Code 가 띄우는 셸에서는 패널을 찍지 않는다.
if [[ -o interactive ]] && [[ -z "$CLAUDECODE" ]] && [[ "${CLAUDE_USAGE_STARTUP:-1}" == 1 ]]; then
  _claude_usage_startup
fi
