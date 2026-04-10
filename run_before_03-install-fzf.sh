#!/bin/bash
set -e

FZF_INSTALL="/opt/homebrew/opt/fzf/install"
if [ -f "$FZF_INSTALL" ] && [ ! -f "$HOME/.fzf.zsh" ]; then
	"$FZF_INSTALL" --all --no-bash --no-fish
fi
