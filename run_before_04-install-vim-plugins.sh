#!/bin/bash
set -e

if [ ! -d "$HOME/.vim/bundle/Vundle.vim" ]; then
	mkdir -p "$HOME/.vim/bundle"
	git clone https://github.com/VundleVim/Vundle.vim.git "$HOME/.vim/bundle/Vundle.vim"
fi

PLUG_VIM="$HOME/.local/share/nvim/site/autoload/plug.vim"
if [ ! -f "$PLUG_VIM" ]; then
	curl -fLo "$PLUG_VIM" --create-dirs \
		https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi
