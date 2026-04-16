#!/bin/bash
set -e

case "$(uname -s)" in
Darwin)
	eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true
	if ! command -v brew &>/dev/null; then
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		eval "$(/opt/homebrew/bin/brew shellenv)"
	fi
	;;
Linux)
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true
	if ! command -v brew &>/dev/null; then
		NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
	fi
	;;
*)
	echo "ERROR: Unsupported OS: $(uname -s)" >&2
	exit 1
	;;
esac
