#!/bin/bash
set -e

case "$(uname -s)" in
Linux)
	missing=()
	for cmd in curl git file zsh; do
		command -v "$cmd" &>/dev/null || missing+=("$cmd")
	done
	for pkg in build-essential procps ca-certificates zstd; do
		dpkg -s "$pkg" &>/dev/null 2>&1 || missing+=("$pkg")
	done
	if [ ${#missing[@]} -gt 0 ]; then
		echo "ERROR: Missing Ubuntu prerequisites: ${missing[*]}" >&2
		echo "Run: sudo apt-get update && sudo apt-get install -y curl git ca-certificates build-essential procps file zstd zsh" >&2
		echo "Then: sudo -v   # refresh sudo timestamp before chezmoi apply" >&2
		exit 1
	fi
	;;
Darwin)
	# macOS prereqs handled by Xcode CLT (xcode-select --install)
	:
	;;
*)
	echo "ERROR: Unsupported OS: $(uname -s)" >&2
	exit 1
	;;
esac
