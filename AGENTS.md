# AGENTS.md — chezmoi dotfiles

## Project Overview

chezmoi로 관리되는 macOS dotfiles. 새 맥에서 원라이너 하나로 전체 개발 환경 구성.

```bash
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
  ├── Brewfile                    ← Homebrew 패키지 목록 (138+)
  ├── npm-global-packages.txt     ← npm 글로벌 패키지 목록
  ├── run_before_*.sh             ← 부트스트랩 (brew, oh-my-zsh, antigen, fzf, vim plugins, tmux, zsh-kubecolor)
  ├── run_onchange_*.sh.tmpl      ← 변경 감지 자동 실행 (brew bundle, npm install)
  └── run_once_*.sh               ← 1회 실행 (Claude Code 설치, zshrc.local 복사)
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

### 변경사항 다른 머신에 반영
```bash
chezmoi cd && git add -A && git commit -m "msg" && git push && exit
# 다른 머신에서:
chezmoi update
```

### 드리프트 확인
```bash
chezmoi status   # 변경된 파일 목록
chezmoi diff     # 구체적 차이
```

## Gotchas

- **Ghostty 경로에 공백** — `Library/Application Support/` chezmoi가 네이티브 처리하므로 따옴표 불필요
- **`.zshrc`의 `gopen`** — alias가 아닌 함수 (셸 시작 시 git 에러 방지)
- **`.zshrc`의 openclaw completion** — `[ -f ... ] && source`로 조건부 로드 (미설치 대응)
- **새 머신 첫 실행** — Xcode CLT 필수 (`xcode-select --install` 먼저), Homebrew 설치 시 RETURN + sudo 필요
- **vim 플러그인** — `run_before_04`가 Vundle+vim-plug 설치 후 `PluginInstall`+`PlugInstall` 자동 실행. 첫 실행 시 colorscheme 에러가 나오지만 플러그인 설치 후 해결됨
- **`run_onchange_` brew bundle** — 첫 실행 시 20분+ 소요. cask 설치 시 sudo 비밀번호 요청 가능
- **opencode.json의 `${VAR}`** — chezmoi 템플릿이 아닌 런타임 환경변수 확장. 절대 `.tmpl`로 만들지 않음
