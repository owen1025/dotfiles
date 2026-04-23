# OpenClaw Skills (clawskills.sh) — 설치 및 환경변수

`run_once_install-opencode-skills.sh`가 `github.com/openclaw/skills` 모노레포에서 sparse-checkout으로 선별 설치하는 스킬들. OpenCode는 `~/.config/opencode/skills/openclaw/skills/<author>/<name>/SKILL.md`를 재귀적으로 스캔해서 자동 인식함.

## 설치되는 스킬 (cross-OS, 9개)

| 스킬 | 의존성 바이너리 | 자동 설치 방식 | 환경변수 |
|---|---|---|---|
| steipete/markdown-converter | `uvx` | Brewfile `uv` | (없음) |
| steipete/gog | `gog` | Brewfile `steipete/tap/gogcli` | `GOG_ACCOUNT` (옵션) |
| steipete/1password | `op` | Brewfile `1password-cli` (macOS only) | `OP_ACCOUNT` (옵션, 다중 계정 시) |
| arnarsson/git-essentials | `git` | 이미 있음 | (없음) |
| jk-0001/automation-workflows | (없음) | 문서 | (없음) |
| oyi77/data-analyst | `python3` + pandas/matplotlib (사용 시) | 수동 `uv pip install` | 데이터 소스별 (DB 연결 문자열 등) |
| shawnpana/browser-use | `browser-use` + Chromium | uv-tool-packages.txt | `BROWSER_USE_API_KEY` (cloud mode 시) |
| whiteknight07/exa-web-search-free | `mcporter` | npm-global-packages.txt | (없음 — Exa free tier) |
| udiedrichsen/stock-analysis | `uv` | Brewfile `uv` | `AUTH_TOKEN`, `CT0` (Twitter/X 연동 시) |

## 설치되는 스킬 (macOS 전용, 2개)

`run_once_install-opencode-skills.sh`의 darwin 블록에서 sparse-checkout에 자동 추가:

| 스킬 | 바이너리 | 자동 설치 방식 | 권한 |
|---|---|---|---|
| steipete/apple-notes | `memo` | Brewfile `antoniorodr/memo/memo` | Notes.app Automation 권한 (최초 실행 시 프롬프트) |
| steipete/apple-reminders | `remindctl` | Brewfile `steipete/tap/remindctl` | Reminders.app 권한 (`remindctl authorize`) |

## `~/.zshrc.local`에 추가할 환경변수 템플릿

chezmoi가 관리하지 않는 시크릿이므로 각 머신에서 직접 편집. 필요한 것만 넣으면 됨 (전부 옵셔널):

```bash
# ─── openclaw skills ─────────────────────────────────────────────

# steipete/gog — 기본 Google 계정 (--account 플래그 생략 가능)
export GOG_ACCOUNT="owen@example.com"

# steipete/1password — 다중 계정 쓸 때만
# export OP_ACCOUNT="my.1password.com"

# shawnpana/browser-use — cloud 모드 쓸 때만 (headless만 쓰면 불필요)
# export BROWSER_USE_API_KEY="bu_xxxxx"

# udiedrichsen/stock-analysis — Twitter/X 트렌드 분석 쓸 때만
# export AUTH_TOKEN="xxxxx"   # twitter.com 쿠키에서 추출
# export CT0="xxxxx"
```

## 자동 설치 (chezmoi apply)

다음은 dotfiles가 자동으로 설치함:

- **Brewfile.tmpl (cross-OS)**: `uv`, `steipete/tap/gogcli`
- **Brewfile.tmpl (darwin block)**: `1password-cli`, `antoniorodr/memo/memo`, `steipete/tap/remindctl`
- **npm-global-packages.txt**: `mcporter`
- **uv-tool-packages.txt**: `browser-use --python 3.13` (Python 3.14 비호환으로 3.13 고정)
- **run_once_install-opencode-skills.sh**: openclaw/skills sparse-checkout 9개 (+ darwin에서 2개)

## 최초 1회 수동 셋업 (머신별 인증/권한)

### 공통 (cross-OS)

```bash
# browser-use 검증 + profile-use 컴포넌트 설치
browser-use doctor
browser-use profile update

# gog OAuth 1회 셋업
#   Google Cloud Console → Desktop OAuth client 생성 → client_secret.json 다운로드
gog auth credentials ~/Downloads/client_secret.json
gog auth add owen@example.com --services gmail,calendar,drive,contacts,sheets,docs
gog auth list

# Exa MCP 등록 (home scope = 글로벌, ~/.mcporter/mcporter.json에 저장)
mcporter config add exa https://mcp.exa.ai/mcp --scope home
```

### macOS 전용

```bash
op signin                    # 1Password CLI 로그인
memo notes                   # 최초 실행 → Notes.app Automation 권한 프롬프트 수락
remindctl authorize          # Reminders.app 권한 요청
remindctl status             # 확인
```

### Linux 전용

`1password-cli`는 Linuxbrew 미지원. 필요 시 [공식 apt repo](https://developer.1password.com/docs/cli/get-started/#install) 수동 설치.

## 업데이트 (다른 머신에서 반영)

```bash
# 스킬 업데이트 (repo 전체 최신화)
cd ~/.config/opencode/skills/openclaw && git pull --ff-only

# 새 머신에서 이 스크립트 최초 적용
chezmoi apply    # run_once_install-opencode-skills.sh 자동 실행
```

스크립트는 idempotent (디렉토리 존재 시 skip). 새 스킬 추가하려면 `sparse_clone_subset` 인자 리스트에 경로만 추가하고 기존 디렉토리 삭제 후 재실행:

```bash
rm -rf ~/.config/opencode/skills/openclaw
chezmoi state delete --bucket=scriptState --key=/home/owen/install-opencode-skills.sh
chezmoi apply
```

## 비설치 스킬 (skip 사유)

| 스킬 | 사유 |
|---|---|
| zlc000190/using-superpowers | `obra/superpowers`와 내용 중복 |
| matrixy/agent-browser-clawdbot | `thesethrose/agent-browser`와 중복 (둘 다 agent-browser CLI 사용) |
| spiceman161/playwright-mcp | `opencode.json`에 이미 playwright MCP 글로벌 등록됨 |
| robin797860/stock-watcher | 중국 A주 전용 (10jqka.com.cn) |
| thesethrose/agent-browser | shawnpana/browser-use와 용도 중복 (후자 선택) |
| nextfrontierbuilds/elite-longterm-memory | 이미 있는 Memory MCP와 중복 + LanceDB MCP 추가 필요 |
| ide-rea/ai-ppt-generator | Baidu API 키 필요 (중국 서비스) |
| adboio/agentmail | AgentMail 구독 필요 |
| adrianmiller99/google-calendar | `steipete/gog`가 상위 호환 |
| ram-raghav-s/computer-use | Linux 헤드리스 서버 전용, 현재 불필요 |
