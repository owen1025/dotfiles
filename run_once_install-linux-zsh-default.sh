#!/bin/bash
set -e

case "$(uname -s)" in
Linux)
	BREW_ZSH="/home/linuxbrew/.linuxbrew/bin/zsh"
	if [ ! -x "$BREW_ZSH" ]; then
		echo "ERROR: Linuxbrew zsh not found at $BREW_ZSH. Ensure Brewfile applied first." >&2
		exit 1
	fi

	# Add to /etc/shells if missing (idempotent)
	if ! grep -Fxq "$BREW_ZSH" /etc/shells; then
		echo "$BREW_ZSH" | sudo tee -a /etc/shells >/dev/null
	fi

	# Change shell if not already BREW_ZSH
	# Try chsh first (works with password auth), fall back to sudo usermod
	# (usermod works in passwordless-sudo / automation environments)
	current_shell="$(getent passwd "$USER" | cut -d: -f7)"
	if [ "$current_shell" != "$BREW_ZSH" ]; then
		chsh -s "$BREW_ZSH" 2>/dev/null || sudo usermod -s "$BREW_ZSH" "$USER"
	fi
	;;
Darwin)
	# macOS uses existing /bin/zsh by default; no auto-chsh
	:
	;;
*)
	echo "ERROR: Unsupported OS: $(uname -s)" >&2
	exit 1
	;;
esac
