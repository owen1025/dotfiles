#!/bin/bash
set -e

if [ ! -d "$HOME/clone/path" ]; then
	mkdir -p "$HOME/clone"
	git clone https://github.com/tmux-plugins/tmux-resurrect "$HOME/clone/path"
fi
