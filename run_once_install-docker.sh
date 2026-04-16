#!/bin/bash
set -e

case "$(uname -s)" in
Linux)
	# Idempotent: skip if docker CLI + compose already installed
	if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
		exit 0
	fi

	# Verify Ubuntu (apt-based)
	if ! command -v apt-get &>/dev/null; then
		echo "ERROR: apt-get not found. This script supports Ubuntu only." >&2
		exit 1
	fi

	# Install prerequisites for apt repo add
	sudo apt-get update
	sudo apt-get install -y ca-certificates curl gnupg

	# Add Docker's official GPG key (idempotent — overwrite OK)
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc

	# Add Docker apt repo (idempotent — same source.list overwrite)
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
		sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

	sudo apt-get update
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	;;
Darwin)
	# macOS uses docker-desktop cask (Brewfile) — no separate install
	:
	;;
*)
	echo "ERROR: Unsupported OS: $(uname -s)" >&2
	exit 1
	;;
esac
