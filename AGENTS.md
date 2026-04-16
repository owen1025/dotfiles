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
sudo apt-get update && sudo apt-get install -y curl git ca-certificates build-essential procps file zstd && sudo -v
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
  ├── dot_claude/                 ← Claude Code 설정 (.mcp.json, settings.json, .omc-config.json)
  ├── dot_config/
  │   ├── nvim/                   ← neovim (init.vim → sources .vimrc, coc-settings.json)
  │   ├── opencode/               ← OpenCode CLI 설정 (opencode.json, oh-my-openagent.json 등)
  │   └── k9s/                    ← k9s 쿠버네티스 UI (config, hotkey, skin, views)
  ├── private_Library/            ← Ghostty 터미널 설정
  ├── private_dot_ssh/                    ← SSH 설정 (config.tmpl — macOS 1Password IdentityAgent 분기)
  ├── Brewfile                    ← Homebrew 패키지 목록 (138+)
  ├── npm-global-packages.txt     ← npm 글로벌 패키지 목록
  ├── run_before_*.sh             ← 부트스트랩 (brew, oh-my-zsh, antigen, fzf, vim plugins, tmux, zsh-kubecolor)
  ├── run_before_-1-install-prerequisites.sh ← Linux prereq 체크 (apt 패키지 존재 확인)
  ├── run_onchange_*.sh.tmpl      ← 변경 감지 자동 실행 (brew bundle, npm install)
  ├── run_once_*.sh               ← 1회 실행 (Claude Code 설치, zshrc.local 복사)
  ├── run_once_install-linux-zsh-default.sh  ← Linux only: /etc/shells 등록 + chsh 자동화
  ├── run_once_install-docker.sh             ← Linux only: Docker CE + compose plugin
  └── run_once_install-ngrok.sh              ← Linux only: ngrok CLI
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
- opencode.json, .mcp.json의 `${VAR}` 참조는 런타임 환경변수 확장 (템플릿화하지 않음)

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

### Prerequisites (MANDATORY before one-liner)

Ubuntu 22.04 / 24.04 LTS 기준:

```bash
sudo apt-get update && \
  sudo apt-get install -y curl git ca-certificates build-essential procps file zstd && \
  sudo -v
```

`sudo -v` 는 sudo 세션을 유지하기 위함. chezmoi apply 중 `/etc/shells` 편집, docker/ngrok 설치 시 재프롬프트 방지.

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

### Post-install (수동)

- `sudo usermod -aG docker $USER` 후 재로그인 — docker 그룹 추가 (sudo 없이 docker 명령 사용)
- `ngrok config add-authtoken <YOUR_TOKEN>` — ngrok authtoken 설정
- 새 shell 세션 열기 — chsh로 zsh 전환 확인

### Known Limitations (Ubuntu 헤드리스 서버)

- macOS-only GUI 앱 (raycast, ghostty, stats, swiftbar 등) 설치 안 됨 (의도적)
- EdgeMark, Ghostty 설정 (`private_Library/`, `private_Documents/EdgeMark/`) 배포 안 됨
- 1Password SSH IdentityAgent 비활성화 (macOS 전용 socket)
- Android SDK, iCloud 환경 변수 설정 안 됨
- osascript 기반 macOS notification 비활성화 (ntfy.sh 알림은 여전히 작동)
- Linuxbrew 첫 설치 시 20-30분 소요 (소스 컴파일)

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
