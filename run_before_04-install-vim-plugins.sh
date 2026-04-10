#!/bin/bash
set -e
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true

if [ ! -d "$HOME/.vim/bundle/Vundle.vim" ]; then
	mkdir -p "$HOME/.vim/bundle"
	git clone https://github.com/VundleVim/Vundle.vim.git "$HOME/.vim/bundle/Vundle.vim"
fi

PLUG_VIM="$HOME/.local/share/nvim/site/autoload/plug.vim"
if [ ! -f "$PLUG_VIM" ]; then
	curl -fLo "$PLUG_VIM" --create-dirs \
		https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

if command -v nvim &>/dev/null; then
	nvim --headless +PluginInstall +qall 2>/dev/null || true
	nvim --headless +PlugInstall +qall 2>/dev/null || true
fi

if command -v pip3 &>/dev/null; then
	pip3 install --break-system-packages pynvim 2>/dev/null || pip3 install pynvim 2>/dev/null || true
fi
