#!/bin/bash
set -e

case "$(uname -s)" in
Linux)
	BREW_MOSH_SERVER="/home/linuxbrew/.linuxbrew/bin/mosh-server"
	SYMLINK_PATH="/usr/local/bin/mosh-server"

	# Skip if already accessible in default PATH
	if command -v mosh-server &>/dev/null; then
		exit 0
	fi

	if [ ! -x "$BREW_MOSH_SERVER" ]; then
		echo "WARN: Linuxbrew mosh-server not found at $BREW_MOSH_SERVER. Skipping symlink." >&2
		exit 0
	fi

	sudo ln -sf "$BREW_MOSH_SERVER" "$SYMLINK_PATH"
	;;
Darwin)
	# macOS: mosh-server is in Homebrew PATH by default
	:
	;;
*)
	echo "ERROR: Unsupported OS: $(uname -s)" >&2
	exit 1
	;;
esac
