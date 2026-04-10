#!/bin/bash
set -e

if [ ! -f "$HOME/antigen.zsh" ]; then
	curl -L https://raw.githubusercontent.com/zsh-users/antigen/master/bin/antigen.zsh >"$HOME/antigen.zsh"
fi
