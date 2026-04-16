#!/bin/bash
set -e

case "$(uname -s)" in
Linux)
	if command -v ngrok &>/dev/null; then
		exit 0
	fi

	if ! command -v apt-get &>/dev/null; then
		echo "ERROR: apt-get not found. This script supports Ubuntu only." >&2
		exit 1
	fi

	# Install prereq
	sudo apt-get update
	sudo apt-get install -y curl

	# Add ngrok apt repo
	curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc |
		sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
	echo "deb https://ngrok-agent.s3.amazonaws.com buster main" |
		sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null

	sudo apt-get update
	sudo apt-get install -y ngrok
	;;
Darwin)
	# macOS uses ngrok cask (Brewfile) — no separate install
	:
	;;
*)
	echo "ERROR: Unsupported OS: $(uname -s)" >&2
	exit 1
	;;
esac
