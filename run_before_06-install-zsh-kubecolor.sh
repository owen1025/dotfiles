#!/bin/bash
set -e

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-kubecolor" ]; then
	git clone https://github.com/devopstales/zsh-kubecolor.git "${ZSH_CUSTOM}/plugins/zsh-kubecolor"
fi
