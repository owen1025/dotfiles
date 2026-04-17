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
restart_daemon() {
	local label="$1"
	launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null || true
}

# status_daemon {label} → prints "running", "stopped", or "unknown"
status_daemon() {
	local label="$1"
	local result
	result=$(launchctl list "$label" 2>/dev/null)
	if [[ $? -eq 0 ]]; then
		# Check if PID is set (non-dash in first column)
		local pid
		pid=$(echo "$result" | awk 'NR==2{print $1}' 2>/dev/null || launchctl list | grep "$label" | awk '{print $1}')
		if [[ "$pid" != "-" && -n "$pid" ]]; then
			echo "running"
		else
			echo "stopped"
		fi
	else
		echo "stopped"
	fi
}
