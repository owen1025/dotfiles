#!/bin/bash
set -e
if ! command -v claude &>/dev/null; then
	npm install -g @anthropic-ai/claude-code
fi
