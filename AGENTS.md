# AGENTS.md — chezmoi dotfiles

## Project Overview

chezmoi로 관리되는 macOS & Ubuntu (headless server) dotfiles. 새 맥에서 원라이너 하나로 전체 개발 환경 구성.

**macOS:**
```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply owen1025
```

**Ubuntu (22.04 / 24.04 LTS):**
```bash
# 1. Prerequisites 먼저 설치
sudo apt-get update && sudo apt-get install -y curl git ca-certificates build-essential procps file zstd zsh && sudo -v
# 2. 동일한 원라이너
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply owen1025
```

## Architecture

```
~/Desktop/owen/dotfiles/          ← chezmoi source directory (이 프로젝트)
  ├── .chezmoi.toml.tmpl          ← 머신별 데이터 (email, name)
  ├── .chezmoiignore              ← chezmoi 제외 패턴
  ├── dot_zshrc.tmpl              ← zsh 설정 (Go 템플릿 — homeDir, email 치환)
  ├── dot_zshrc.local.example     ← 시크릿 템플릿 (각 머신에서 수동 복사+편집)
  ├── dot_vimrc                   ← vim 설정 (plain copy)
  ├── dot_p10k.zsh                ← powerlevel10k 프롬프트 (plain copy)
  ├── dot_tmux.conf               ← tmux 설정 (gpakosz/.tmux fork)
  ├── dot_tmux.conf.local         ← tmux 로컬 오버라이드
  ├── dot_config/
  │   ├── nvim/                   ← neovim (init.vim → sources .vimrc, coc-settings.json)
  │   ├── opencode/               ← OpenCode CLI 설정 (opencode.json, plugins, MCP, skills)
  │   │   └── skills/             ← 관리 skill (Slack bridge/factory)
  │   └── k9s/                    ← k9s 쿠버네티스 UI (config, hotkey, skin, views)
  ├── private_Library/            ← Ghostty 터미널 설정
  ├── private_dot_ssh/                    ← SSH 설정 (config.tmpl — macOS 1Password IdentityAgent 분기)
  ├── Brewfile.tmpl               ← Homebrew 패키지 목록 (템플릿 — cask는 darwin block에 격리)
  ├── npm-global-packages.txt     ← npm 글로벌 패키지 목록
  ├── run_before_*.sh             ← 부트스트랩 (brew, oh-my-zsh, antigen, fzf, vim plugins, tmux, zsh-kubecolor)
  ├── run_before_-1-install-prerequisites.sh ← Linux prereq 체크 (apt 패키지 존재 확인)
  ├── run_onchange_*.sh.tmpl      ← 변경 감지 자동 실행 (brew bundle, npm install)
  ├── run_once_*.sh               ← 1회 실행 (zshrc.local 복사, OpenCode skills, migration cleanup)
  ├── run_once_install-linux-zsh-default.sh  ← Linux only: /etc/shells 등록 + chsh 자동화
  ├── run_once_install-docker.sh             ← Linux only: Docker CE + compose plugin
  ├── run_once_install-ngrok.sh              ← Linux only: ngrok CLI
  └── run_once_install-opencode-skills.sh    ← OpenCode/Agent skill 설치 (git clone + npx skills)
```

## Key Conventions

### chezmoi 파일 네이밍
- `dot_` 접두사 → 홈 디렉토리의 `.` 파일 (예: `dot_zshrc` → `~/.zshrc`)
- `.tmpl` 접미사 → Go 템플릿 (chezmoi가 렌더링)
- `private_` 접두사 → 퍼미션 제한 디렉토리
- `run_before_` → chezmoi apply 전 실행 (부트스트랩)
- `run_onchange_` → 파일 해시 변경 시 실행 (패키지 설치)
- `run_once_` → 최초 1회만 실행

### 템플릿 변수
- `{{ .chezmoi.homeDir }}` → 홈 디렉토리 경로 (머신별 자동)
- `{{ .email }}` → Git 이메일 (.chezmoi.toml.tmpl에서 promptStringOnce)
- `{{ .name }}` → Git 이름

### 시크릿 관리
- **1Password 사용 안 함** — 각 머신에서 `~/.zshrc.local` 수동 관리
- `dot_zshrc.local.example` → 새 머신에서 `run_once_setup-zshrc-local.sh`가 자동 복사
- `.zshrc.local`은 chezmoi managed 아님 (`.chezmoiignore`에 `*.example` 제외)
- opencode.json의 `${VAR}` 참조는 런타임 환경변수 확장 (템플릿화하지 않음)

### OS-specific 코드
- chezmoi template: `{{ if eq .chezmoi.os "darwin" }}` / `{{ if eq .chezmoi.os "linux" }}`
- 스크립트 분기: `case "$(uname -s)" in Darwin) ... ;; Linux) ... ;; *) exit 1 ;; esac`
- Unified brew shellenv (모든 스크립트에 동일하게):
  ```bash
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true
  ```

### 스크립트 규칙
- 모든 `run_before_` 스크립트는 **idempotent** (이미 설치됐으면 skip)
- brew 의존 스크립트는 반드시 `eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true` 포함
- `run_onchange_` 스크립트는 해시 주석으로 변경 감지: `# hash: {{ include "파일" | sha256sum }}`

## Common Tasks

### 설정 파일 추가
```bash
chezmoi add ~/.config/새설정파일
# chezmoi source에 자동 추가 → git commit + push
```

### Brewfile에 패키지 추가
```bash
# Brewfile 직접 편집 후:
chezmoi apply  # run_onchange_01이 brew bundle 자동 실행
```

### npm 글로벌 패키지 추가
```bash
# npm-global-packages.txt에 패키지명 추가 후:
chezmoi apply  # run_onchange_02가 npm install 자동 실행
```

### 변경사항 다른 머신에 반영 (push 측)
```bash
chezmoi cd && git add -A && git commit -m "msg" && git push && exit
```

### 원격 머신에서 변경사항 동기화 (pull 측)

원격 머신에서 에이전트가 dotfiles 업데이트를 요청받으면:

```bash
# 1. 원격 변경사항 가져오기 + 적용 (git pull + chezmoi apply 한 번에)
chezmoi update

# 2. 적용 결과 확인
chezmoi status  # 비어있으면 정상
```

**에이전트 프롬프트 예시:**
> "dotfiles 최신으로 동기화해줘" 또는 "chezmoi update 실행해줘"

**주의:**
- `chezmoi update`는 `git pull` + `chezmoi apply`를 한 번에 수행
- `run_onchange_` 스크립트가 트리거될 수 있음 (brew bundle, npm install 등)
- config만 동기화하려면: `chezmoi update --exclude=scripts`
- 충돌 시: `chezmoi diff`로 확인 후 수동 해결

### 드리프트 확인
```bash
chezmoi status   # 변경된 파일 목록
chezmoi diff     # 구체적 차이
```

## Agent Workflow (필수)

이 프로젝트는 chezmoi source directory이자 git repo다.
설정을 수정/추가/삭제할 때 반드시 아래 순서를 따라야 한다.

### 변경 후 반영 흐름 (MANDATORY)

```
1. chezmoi source 파일 수정 (이 프로젝트의 파일 직접 편집)
2. git add + commit + push
3. chezmoi apply (로컬 홈 디렉토리에 반영)
```

### 구체적 예시

**설정 파일 수정 시:**
```bash
# 1. source 파일 편집 (예: dot_zshrc.tmpl)
# 2. git 반영
git add -A && git commit -m "update zshrc" && git push
# 3. 로컬에 적용
chezmoi apply --exclude=scripts
```

**새 설정 파일 추가 시:**
```bash
# 방법 A: 라이브 파일에서 가져오기
chezmoi add --follow ~/.config/새파일
git add -A && git commit -m "add 새파일" && git push

# 방법 B: source에 직접 생성
# dot_config/새파일 생성 후:
git add -A && git commit -m "add 새파일" && git push
chezmoi apply --exclude=scripts
```

**설정 파일 삭제 시:**
```bash
# 1. source에서 삭제
rm dot_config/삭제할파일
# 2. git 반영
git add -A && git commit -m "remove 삭제할파일" && git push
# 3. 홈 디렉토리에서도 수동 삭제 (chezmoi는 managed 파일을 자동 삭제하지 않음)
rm ~/.config/삭제할파일
```

**Brewfile/npm-global-packages.txt 수정 시:**
```bash
# 1. 파일 편집
# 2. git 반영
git add -A && git commit -m "add package X" && git push
# 3. 적용 (스크립트 포함 — brew bundle / npm install 자동 실행)
chezmoi apply
```

### 주의사항
- `chezmoi apply` 없이 git push만 하면 **로컬에 반영 안 됨**
- `chezmoi apply --exclude=scripts` → config 파일만 적용 (brew bundle 등 skip)
- `chezmoi apply` → 전체 적용 (스크립트 포함, brew bundle이 오래 걸릴 수 있음)
- 다른 머신에서 가져오기: `chezmoi update` (= git pull + apply)

## Ubuntu (Headless Server) Bootstrap

### Non-root user 필수

**Linuxbrew는 root로 설치 불가** (`Don't run this as root!` 에러). 반드시 일반 사용자 계정에서 실행:

```bash
# root로 로그인되어 있다면 먼저 일반 사용자 생성:
useradd -m -s /bin/bash -G sudo owen
echo "owen ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/owen
chmod 0440 /etc/sudoers.d/owen
su - owen   # 전환 후 아래 과정 진행
```

비밀번호 없는 sudo가 권장됨 — `chsh` PAM 인증 실패 시 `sudo usermod` 폴백이 작동해야 함.

### Prerequisites (MANDATORY before one-liner)

Ubuntu 22.04 / 24.04 LTS 기준:

```bash
sudo apt-get update && \
  sudo apt-get install -y curl git ca-certificates build-essential procps file zstd zsh && \
  sudo -v
```

`sudo -v` 는 sudo 세션을 유지하기 위함. chezmoi apply 중 `/etc/shells` 편집, docker/ngrok 설치 시 재프롬프트 방지.

`zsh` 필수 — macOS는 `/bin/zsh` 내장이지만 Ubuntu는 별도 설치 필요 (oh-my-zsh 설치의 전제조건).

### One-liner

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply owen1025
```

### 실행되는 일 (Linux 분기)

1. `run_before_-1-install-prerequisites.sh` — apt prereq 존재 확인 (없으면 exit 1)
2. `run_before_00-install-homebrew.sh` — Linuxbrew 설치 (`/home/linuxbrew/.linuxbrew`)
3. `run_before_01~06` — oh-my-zsh, antigen, fzf, vim plugins 등
4. `run_onchange_01` — `brew bundle` (cask 자동 제외, 100+ formula 설치)
5. `run_onchange_02/03` — npm global + opencode MCP servers
6. `run_once_install-linux-zsh-default.sh` — `/etc/shells` 편집 + `chsh -s` 자동
7. `run_once_install-docker.sh` — Docker CE + compose plugin
8. `run_once_install-ngrok.sh` — ngrok CLI
9. `run_once_install-opencode-skills.sh` — OpenCode/Agent skill 설치 (git clone + npx skills add)

### Post-install (수동)

- `sudo usermod -aG docker $USER` 후 재로그인 — docker 그룹 추가 (sudo 없이 docker 명령 사용)
- `ngrok config add-authtoken <YOUR_TOKEN>` — ngrok authtoken 설정
- 새 shell 세션 열기 — chsh로 zsh 전환 확인
- (필요 시) `sudo passwd owen` — 원격 SSH 비밀번호 로그인용 비밀번호 설정

### 비대화형 chezmoi init (CI/자동화)

TTY가 없는 환경에서 `chezmoi init`은 prompt 입력을 받을 수 없으므로 플래그로 전달:

```bash
chezmoi init --apply --promptString email=you@example.com \
  --promptString name="Your Name" --promptBool useAnthropicAuth=false owen1025
```

### Known Limitations (Ubuntu 헤드리스 서버)

- **Non-root user 필수** — Linuxbrew는 root 계정에서 설치 불가
- macOS-only GUI 앱 (raycast, ghostty, stats, swiftbar 등) 설치 안 됨 (의도적)
- EdgeMark, Ghostty 설정 (`private_Library/`, `private_Documents/EdgeMark/`) 배포 안 됨
- 1Password SSH IdentityAgent 비활성화 (macOS 전용 socket)
- Android SDK, iCloud 환경 변수 설정 안 됨
- osascript 기반 macOS notification 비활성화 (ntfy.sh 알림은 여전히 작동)
- **실제 부트스트랩 소요시간 ~25분** (brew bundle 설치가 대부분, 269개 formula + 의존성)

## Gotchas

- **Ghostty 경로에 공백** — `Library/Application Support/` chezmoi가 네이티브 처리하므로 따옴표 불필요
- **`.zshrc`의 `gopen`** — alias가 아닌 함수 (셸 시작 시 git 에러 방지)
- **`.zshrc`의 openclaw completion** — `[ -f ... ] && source`로 조건부 로드 (미설치 대응)
- **새 머신 첫 실행** — Xcode CLT 필수 (`xcode-select --install` 먼저), Homebrew 설치 시 RETURN + sudo 필요
- **vim 플러그인** — `run_before_04`가 Vundle+vim-plug 설치 후 `PluginInstall`+`PlugInstall` 자동 실행. 첫 실행 시 colorscheme 에러가 나오지만 플러그인 설치 후 해결됨
- **`run_onchange_` brew bundle** — 첫 실행 시 20분+ 소요. cask 설치 시 sudo 비밀번호 요청 가능
- **opencode.json of `${VAR}`** — chezmoi 템플릿이 아닌 런타임 환경변수 확장. 절대 `.tmpl`로 만들지 않음
- **Linuxbrew PATH 우선순위** — Linuxbrew > /usr/bin. `git`, `zsh` 등은 brew 버전 사용됨
- **systemd/cron에서 PATH** — non-interactive 컨텍스트에서는 `/home/linuxbrew/.linuxbrew/bin/<tool>` 직접 호출 권장
- **Ubuntu 24.04 pip3** — PEP 668 적용. `pip3 install --break-system-packages` 또는 brew python3 pip3 사용
- **`.chezmoiignore`는 target path 사용** — source의 `private_Library/` 가 아니라 deploy 경로인 `Library/**` 로 패턴 작성. chezmoi는 target filename 기준으로 매칭함
- **Linux zshrc의 brew PATH** — macOS는 시스템이 자동으로 brew PATH 설정하지만 Linux는 zshrc 내에서 `eval "$($_BREW_PREFIX/bin/brew shellenv)"` 명시 필요 (chezmoi template `{{ if eq .chezmoi.os "linux" }}` 블록으로 처리)
- **macOS-only brew formulas** — `telnet`, `chrome-cli`, `scrcpy`, `openfortivpn` 등은 Linuxbrew 미지원 → `Brewfile.tmpl`의 darwin block에 격리 필수. `brew install` 시 "macOS is required" 에러로 식별
- **Linux `chsh` PAM 인증 실패** — 비밀번호 없는 sudo 환경에서 `chsh -s`는 PAM 에러 발생. `run_once_install-linux-zsh-default.sh`는 `sudo usermod -s` 폴백으로 처리
- **forgit config 변수 export 필요** — forgit 최신 버전은 `_FORGIT_PATH` 등 설정 변수를 `export`로 요구 (미지원 시 deprecation warning)
- **tmux 3.6a + mosh OSC 52 클립보드 (macOS & Linux 동일)** — tmux built-in `set-clipboard on`은 OSC 52를 tmux의 controlling terminal(= mosh-server의 *내부* pty)에 쓰고 mosh가 client로 forward하는 outer pty에는 도달하지 않음. DCS passthrough via `#{pane_tty}`도 같은 이유로 실패 (tmux가 strip한 OSC 52를 똑같은 내부 pty로 내보냄). 실험 증거: `> /dev/ttysXXX` (tmux client_tty) 직접 write는 성공, `> #{pane_tty}` 는 실패. 참고 이슈: https://github.com/mobile-shell/mosh/pull/1104 (delbao 2022). **해결책**: `tmux-osc52-copy` 스크립트가 `tmux list-clients -t $session -F '#{client_activity} #{client_tty}'`로 가장 최근 activity 클라이언트의 outer tty를 찾아 raw OSC 52(`\e]52;c;<base64>\a`)를 직접 write. DCS wrap 불필요. 설정: `set -s set-clipboard off` + `set -g allow-passthrough on` (OSC 11 bg color query용, OSC 52에는 무관). mosh 1.4.0은 selection prefix `c;` 강제. `dot_tmux.conf.local.tmpl`의 OS 분기 없음 (양쪽 동일 로직). `tmux-osc52-copy`의 `pbcopy` fallback은 `command -v` guard로 Linux에서 no-op. ⚠️ 다중 user가 같은 tmux server에 붙는 경우 타 user의 tty는 write 불가 — `[ -w "$target_tty" ]` 체크로 silent skip
- **Ghostty `clipboard-write` 설정** — 기본값 `ask`이면 OSC 52 수신 시 팝업으로 허용 요청. 반복 사용 시 `clipboard-write = allow`로 바꿔야 매끄러움. (`deny`면 OSC 52 무시됨)

## Managed Skills

이 dotfiles repo는 OpenCode를 단일 agent runtime으로 사용한다. MCP와 skill의 canonical source는 `dot_config/opencode/`이다.

### 외부 스킬 설치 (`run_once_install-opencode-skills.sh`)

외부 스킬은 세 가지 방식으로 설치:

1. **전체 리포 clone** (`clone_if_missing`) — 리포 전체가 스킬 모음인 경우
   - `trailofbits/skills`, `obra/superpowers`, `automazeio/ccpm`

2. **Sparse-checkout** (`sparse_clone_subset`) — 모노레포에서 몇 개만 선별
   - `openclaw/skills` → curated subset (`docs/openclaw-skills.md` 참고)
   - `ComposioHQ/awesome-claude-skills` → `mcp-builder`, `skill-creator`
   - `sickn33/antigravity-awesome-skills` → `bash-linux`, `analyze-project`, `autonomous-agent-patterns`
   - 1400+ 스킬 중 일부만 pull → 디스크 절약 (~5MB)
   - 주의: 리포 내 symlink가 sparse-checkout 범위 밖을 가리키면 dangling link 발생 (무해)

### Discovery Pipeline Sources (MCP + Skill 자동 발견용)

봇이 새 MCP/Skill을 Slack으로 알려주고 승인 시 자동 설치하는 파이프라인의 데이터 소스:

**MCP 레지스트리 (opencode.json.tmpl MCP 등록):**
- `mcp-registry` (`@mcpfinder/server`) — Official MCP Registry + MCPfinder 다중 소스 검색
- `pulsemcp` (`pulsemcp-server`) — PulseMCP sub-registry (Official 포함 + 인기 메트릭)
- `glama` (`mcp-glama-registry` via uvx) — Glama directory (21K+ 서버)

**Skill 소스 (`run_once_install-opencode-skills.sh` 신규 clone 4개):**
- `anthropic-official` ← `anthropics/skills` (공식 Anthropic 스킬 — PDF/DOCX 등)
- `voltagent-awesome` ← `VoltAgent/awesome-agent-skills` (1000+ 큐레이션, No-slop)
- `awesome-claude-code` ← `hesreallyhim/awesome-claude-code` (40K stars, 통합 리스트)
- `awesome-claude-skills` ← `travisvn/awesome-claude-skills` (11K stars, 실용 모음)
- `skills.sh` — 런타임에 `npx skills find` 으로 쿼리 (clone 없음)

탐색 데몬은 각 소스의 최신 변경을 diff하여 신규 후보를 Slack 승인 채널로 푸시.

3. **`npx skills add`** (글로벌) — skills.sh 생태계
   - `phuryn/pm-skills`, `pchalasani/claude-code-tools`, `vercel-labs/agent-skills`, `vercel-labs/skills`

**새 외부 스킬 추가 시:**
- 리포 전체 쓰면 `clone_if_missing` 한 줄
- 일부만 쓰면 `sparse_clone_subset` 한 줄 (paths 인자에 서브디렉토리 추가)
- `npx skills add` 지원하면 npx 블록에 한 줄
- 스크립트 수정 → chezmoi apply → 다른 머신에서 `chezmoi update`로 자동 반영

### Skill 평탄화 (Flatten Deep Skills)

**문제**: OpenCode의 Skill MCP tool은 `~/.config/opencode/skills/` 기준 **depth ≤3 까지만** path-based registry에 등록한다. 더 깊은 SKILL.md는 시스템 프롬프트의 `<available_skills>` 리스트에는 description으로 노출되지만 `Skill(name=...)` 호출 시 "not found" 에러로 실패한다 (그리고 `task(load_skills=[...])` 주입에도 실패할 가능성이 있음).

**영향받는 스킬 (총 82개):**
- `trailofbits/plugins/{plugin}/skills/{skill}` (5-level) — 72개 (semgrep, codeql, address-sanitizer, 모든 vulnerability scanner 등)
- `openclaw/skills/{maintainer}/{skill}` (4-level) — 9개 (1password, gog, markdown-converter 등)
- `trailofbits/.codex/skills/gh-cli` (4-level) — 1개

**해결**: `run_once_install-opencode-skills.sh` 의 `flatten_deep_skills` 함수가 depth ≥4 SKILL.md 마다 depth-1 위치에 basename symlink 생성:

```
~/.config/opencode/skills/semgrep -> trailofbits/plugins/static-analysis/skills/semgrep
~/.config/opencode/skills/1password -> openclaw/skills/steipete/1password
```

**메커니즘:**
- 추적: `.flatten-manifest.txt` (생성된 symlink 이름 목록)
- 재실행 시 manifest 기반 cleanup 후 재생성 (idempotent)
- 충돌 (실제 디렉토리/파일과 같은 이름) 발생 시 skip + 경고
- relative symlink 사용 → `$HOME` 경로 다른 머신에서도 동작

**제약:**
- Symlink 자체는 chezmoi managed 아님 (런타임 생성). install script 실행 시점에 새로 생성.
- `.flatten-manifest.txt` 는 머신별 상태 — `.chezmoiignore` 에 명시 안 해도 source에 없으므로 git 추적 안 됨
- basename 충돌 검사: 현재 82개 deep skill 모두 unique. 새 sparse_clone_subset 추가 시 **conflict check 필요** (script에서 자동 skip 하지만 의도된 skill을 놓칠 수 있음)
- OpenCode session 재시작 후에야 새 symlink 인식. 단순히 chezmoi apply 후엔 즉시 안 잡힘

**검증:**
```bash
# Symlink 개수 확인
ls -la ~/.config/opencode/skills/ | grep -c '^l'  # → 82
# Manifest 일치 확인
wc -l ~/.config/opencode/skills/.flatten-manifest.txt  # → 82
# 특정 skill 호출 가능한지 (OpenCode 재시작 후)
# Skill(name="semgrep") → SKILL.md content 반환되어야 함
```

### OpenCode 관리 스킬

#### Slack bot/bridge skills

**위치:**
- `dot_config/opencode/skills/slack-opencode-bridge-factory/`
- `dot_config/opencode/skills/slack-bot-factory/`
- `dot_config/opencode/skills/slack-bot-permissions/`

**역할:** OpenCode 에이전트를 Slack 봇으로 브릿지하고, Slack App 생성/권한 관리를 자동화한다.

**서브커맨드:** `create`, `finalize`, `list`, `restart`, `logs`, `update`, `delete`, `migrate`, `refresh-peers`

**디렉토리 구조:**
```
dot_config/opencode/skills/slack-opencode-bridge-factory/
├── SKILL.md                            # skill 엔트리 + triggers
├── scripts/
│   ├── main.sh                         # 서브커맨드 라우터 (chezmoi target)
│   ├── create.sh, finalize.sh, ...     # 각 커맨드 (chezmoi target)
│   └── lib/
│       ├── detect_os.sh                # OS 감지 + brew_bin_path (macOS/Linux)
│       ├── daemon.sh → daemon_macos.sh OR daemon_linux.sh
│       ├── registry.sh                 # ~/.config/opencode-bridges/registry.json CRUD
│       ├── env_manager.sh              # ~/.zshrc.local 안전 업서트
│       ├── opencode_json.sh            # 기존 opencode.json 병합 (JSONC 거부)
│       ├── kg_writer.sh                # Memory MCP 엔티티 JSON 출력
│       ├── agents_md.sh                # BRIDGE_PEERS/BRIDGE_INFO 마커 주입
│       ├── slack_integration.sh        # slack-bot-factory wrapper
│       └── port_scan.sh                # 4096-4196 충돌 회피
└── templates/
    ├── bridge/bridge.py                # Slack↔OpenCode 브릿지 (파라미터화)
    ├── opencode.json.tmpl              # agent.build 설정
    ├── AGENTS.md.tmpl                  # role placeholder
    ├── slack_manifest.json.tmpl        # Slack App manifest (scopes 포함)
    ├── env_file.tmpl                   # 에이전트별 env
    ├── launchd_{opencode,bridge}.plist.tmpl     # macOS 데몬
    ├── systemd_{opencode,bridge}.service.tmpl   # Linux 데몬
    └── wrapper_{opencode,bridge}.sh.tmpl        # launchd/systemd exec 타겟
```

**외부 상태 (chezmoi 밖):**
- `~/.config/opencode-bridges/registry.json` — 에이전트 메타데이터 (single source of truth)
- `~/.config/opencode-bridges/{agent}.env` — 에이전트별 env 파일
- `~/.local/bin/{agent}-*.sh` — wrapper 스크립트 (create 시 생성)
- `~/Library/LaunchAgents/com.owen.{agent}-*.plist` (macOS) or `~/.config/systemd/user/{agent}-*.service` (Linux)
- `~/.local/log/opencode-bridges/{agent}/{opencode,bridge}.log`

**의존성:**
- `dot_config/opencode/skills/slack-bot-factory/` — Slack App 생성 (Manifest API) 위임
- `~/.zshrc.local`에 `SLACK_{WORKSPACE}_{AGENT}_{BOT,APP}_TOKEN` 환경변수
- `opencode.json`의 MCP (playwright, slack 등 — 글로벌 `dot_config/opencode/opencode.json.tmpl`에서 관리)

**관련 글로벌 설정:**
- `dot_config/opencode/opencode.json.tmpl` — 글로벌 MCP 정의 (playwright MCP 포함)
- wrapper 스크립트에 `{{BREW_PATH}}` 치환 주입됨 (launchd/systemd minimal PATH 대응)

**에이전트가 스킬 파일 수정 시 주의사항:**

1. **commit은 반드시 dotfiles에서:**
   ```bash
   cd ~/Desktop/owen/dotfiles
   git add dot_config/opencode/skills/slack-opencode-bridge-factory      dot_config/opencode/skills/slack-bot-factory      dot_config/opencode/skills/slack-bot-permissions
   git commit -m "..." && git push
   ```
   스킬 디렉토리 내부에서 `git init`/`git commit` 하면 chezmoi가 `.git` 포함해버림.

2. **`.tmpl` 파일명 주의** — chezmoi가 내부적으로 `.literal` suffix 처리. 스크립트에서 `ls templates/opencode.json.tmpl*`로 와일드카드 검색.

3. **`__pycache__/`** — chezmoi add 시 실수로 포함될 수 있음. `.chezmoiignore`나 commit 전 `rm -rf` 필요.

4. **스킬 변경 후 기존 에이전트 반영:**
   - bridge.py 코드 변경 → main.sh의 `update --sync-bridge` (동시 재시작)
   - wrapper 템플릿 변경 → main.sh의 `update <agent>` 또는 `delete` + `create` 재설치
   - env 파일 변경 → `agent_env_set` 사용, 전체 재작성 금지
   - 모든 호출은 `bash ~/.config/opencode/skills/slack-opencode-bridge-factory/scripts/main.sh <subcommand>` 형식으로.

5. **OS-agnostic:**
   - macOS + Ubuntu 24.04 양쪽에서 동작해야 함
   - `local path=` 금지 (zsh PATH 변수 충돌)
   - bare `rm`, `cp` 대신 `/bin/rm`, `/bin/cp` (function 내부)
   - `brew_bin_path` 함수로 Homebrew 경로 분기

### 새 관리 대상 스킬 추가 시

1. `dot_config/opencode/skills/<skill-name>/` 작성 (chezmoi 자동 관리)
2. AGENTS.md의 "Managed Skills" 섹션에 항목 추가 (이 섹션)
