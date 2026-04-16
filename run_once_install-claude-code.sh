#!/bin/bash
set -e
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true
if ! command -v claude &>/dev/null; then
	npm install -g @anthropic-ai/claude-code
fi
