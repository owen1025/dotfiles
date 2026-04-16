#!/bin/bash
set -e
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-kubecolor" ]; then
	git clone https://github.com/devopstales/zsh-kubecolor.git "${ZSH_CUSTOM}/plugins/zsh-kubecolor"
fi
