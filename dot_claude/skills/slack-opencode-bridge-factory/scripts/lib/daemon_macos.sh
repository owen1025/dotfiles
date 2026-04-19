#!/usr/bin/env bash
# daemon_macos.sh — launchd daemon management (macOS)
# Source this file; do NOT execute directly.
# IMPORTANT: Never use "local path=" (zsh PATH conflict). Use "local filepath=" or "local lpath=".

# install_daemon {label} {plist_src_path} {symlink_target_path}
# Copies plist to symlink_target_path, then bootstraps
install_daemon() {
	local label="$1"
	local plist_src="$2"
	local plist_link="$3"

	mkdir -p "$(dirname "$plist_link")"
	cp "$plist_src" "$plist_link"
	launchctl bootstrap "gui/$(id -u)" "$plist_link" 2>/dev/null || {
		launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
		launchctl bootstrap "gui/$(id -u)" "$plist_link"
	}
}

# uninstall_daemon {label} {plist_link_path}
uninstall_daemon() {
	local label="$1"
	local plist_link="$2"
	launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
	/bin/rm -f "$plist_link"
}

# start_daemon {label}
start_daemon() {
	local label="$1"
	launchctl kickstart "gui/$(id -u)/$label" 2>/dev/null || true
}

# stop_daemon {label}
stop_daemon() {
	local label="$1"
	launchctl kill TERM "gui/$(id -u)/$label" 2>/dev/null || true
}

# restart_daemon {label}
# bootout + bootstrap kills child processes too (kickstart -k only kills the parent,
# leaving opencode child holding the port → new instance fails with EADDRINUSE).
restart_daemon() {
	local label="$1"
	local plist="$HOME/Library/LaunchAgents/${label}.plist"
	launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
	sleep 1
	if [[ -f "$plist" ]]; then
		launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
	else
		launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null || true
	fi
}

# status_daemon {label} → prints "running", "stopped", or "unknown"
# launchctl list <label> returns a plist-like dict; parse "PID" = N; line.
status_daemon() {
	local label="$1"
	local result
	result=$(launchctl list "$label" 2>/dev/null)
	if [[ -z "$result" ]]; then
		echo "stopped"
		return
	fi
	local pid
	pid=$(echo "$result" | awk -F'= *' '/"PID"/ {gsub(";","",$2); gsub(" ","",$2); print $2; exit}')
	if [[ -n "$pid" && "$pid" != "0" ]]; then
		echo "running"
	else
		echo "stopped"
	fi
}
