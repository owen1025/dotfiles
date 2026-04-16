#!/bin/bash
set -e
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true
if command -v gh &>/dev/null; then
	gh extension install remcostoeten/gh-select 2>/dev/null || true
fi
