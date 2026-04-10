#!/bin/bash
set -e
if [ ! -f "$HOME/.zshrc.local" ]; then
    CHEZMOI_SOURCE="$(chezmoi source-path 2>/dev/null || echo "$HOME/.local/share/chezmoi")"
    if [ -f "$CHEZMOI_SOURCE/dot_zshrc.local.example" ]; then
        cp "$CHEZMOI_SOURCE/dot_zshrc.local.example" "$HOME/.zshrc.local"
        echo "Created ~/.zshrc.local from template. Edit it to add your secrets."
    fi
fi
