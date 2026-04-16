#!/bin/bash
set -e
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true

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

# pynvim — prefer Linuxbrew/Homebrew python3 pip3 first
if command -v brew &>/dev/null; then
	BREW_PIP3="$(brew --prefix)/bin/pip3"
	if [ -x "$BREW_PIP3" ]; then
		"$BREW_PIP3" install pynvim 2>/dev/null || true
	fi
fi
# Fallback to system pip3 with PEP 668 bypass
if command -v pip3 &>/dev/null; then
	pip3 install --break-system-packages pynvim 2>/dev/null || pip3 install pynvim 2>/dev/null || true
fi
