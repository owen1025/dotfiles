#!/bin/bash
set -e
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true

if command -v brew &>/dev/null; then
	FZF_PREFIX="$(brew --prefix fzf 2>/dev/null || true)"
	if [ -n "$FZF_PREFIX" ] && [ -f "$FZF_PREFIX/install" ] && [ ! -f "$HOME/.fzf.zsh" ]; then
		"$FZF_PREFIX/install" --all --no-bash --no-fish
	fi
fi
