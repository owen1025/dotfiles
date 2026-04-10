#!/bin/bash
set -e
if ! command -v opencode &>/dev/null; then
    curl -fsSL https://opencode.sh | bash
fi
