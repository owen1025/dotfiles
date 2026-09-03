#!/bin/bash
set -e
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true

# --no-update-rc: 기본값은 ~/.zshrc 끝에 `source ~/.fzf.zsh` 를 덧붙이는데, 그러면 chezmoi 가
# 관리하는 .zshrc 가 "수정됨" 으로 바뀌어 다음 apply 가 TTY 확인을 요구하며 멈춘다
# (.zshrc 는 이미 `source <(fzf --zsh)` 로 fzf 를 로드한다). 2026-09-03 owen-macmini 에서 발견.
if command -v brew &>/dev/null; then
	FZF_PREFIX="$(brew --prefix fzf 2>/dev/null || true)"
	if [ -n "$FZF_PREFIX" ] && [ -f "$FZF_PREFIX/install" ] && [ ! -f "$HOME/.fzf.zsh" ]; then
		"$FZF_PREFIX/install" --all --no-bash --no-fish --no-update-rc
	fi
fi
