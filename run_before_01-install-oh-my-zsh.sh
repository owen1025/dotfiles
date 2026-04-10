#!/bin/bash
set -e
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true

if [ ! -d "$HOME/.oh-my-zsh" ]; then
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

mkdir -p "$HOME/.oh-my-zsh/completions"
chmod -R 755 "$HOME/.oh-my-zsh/completions"

KUBECTX_PREFIX="$(brew --prefix kubectx 2>/dev/null)/share/zsh/site-functions"
if [ -d "$KUBECTX_PREFIX" ]; then
	ln -sf "${KUBECTX_PREFIX}/_kubectx" "$HOME/.oh-my-zsh/completions/_kubectx.zsh" 2>/dev/null || true
	ln -sf "${KUBECTX_PREFIX}/_kubens" "$HOME/.oh-my-zsh/completions/_kubens.zsh" 2>/dev/null || true
fi
