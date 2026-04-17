#!/usr/bin/env bash
# daemon_linux.sh — systemd --user daemon management (Linux)
# Source this file; do NOT execute directly.
# IMPORTANT: Never use "local path=" (zsh PATH conflict). Use "local filepath=" or "local lpath=".

# Helper: ensure systemd env vars are set (required for SSH sessions)
_ensure_systemd_env() {
	if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
		export XDG_RUNTIME_DIR="/run/user/$(id -u)"
	fi
	if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
		export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
	fi
}

# Helper: enable user session lingering (try without sudo, instruct if fail)
_ensure_linger() {
	local user="${USER:-$(whoami)}"
	if loginctl show-user "$user" 2>/dev/null | grep -q "Linger=yes"; then
		return 0
	fi
	if loginctl enable-linger "$user" 2>/dev/null; then
		echo "Enabled linger for $user"
		return 0
	fi
	echo "WARN: Could not enable linger automatically. Run: sudo loginctl enable-linger $user" >&2
	echo "Without linger, services will stop when all SSH sessions close." >&2
	return 1
}

# install_daemon {label} {service_src} {target_path}
install_daemon() {
	_ensure_systemd_env
	local label="$1"
	local service_src="$2"
	local target="$3"

	mkdir -p "$(dirname "$target")"
	/bin/cp "$service_src" "$target"

	systemctl --user daemon-reload
	systemctl --user enable --now "$label"
}

# uninstall_daemon {label} {target_path}
uninstall_daemon() {
	_ensure_systemd_env
	local label="$1"
	local target="$2"

	systemctl --user stop "$label" 2>/dev/null || true
	systemctl --user disable "$label" 2>/dev/null || true
	/bin/rm -f "$target"
	systemctl --user daemon-reload
}

# start_daemon {label}
start_daemon() {
	_ensure_systemd_env
	systemctl --user start "$1"
}

# stop_daemon {label}
stop_daemon() {
	_ensure_systemd_env
	systemctl --user stop "$1" 2>/dev/null || true
}

# restart_daemon {label}
restart_daemon() {
	_ensure_systemd_env
	systemctl --user restart "$1"
}

# status_daemon {label} → prints "running", "stopped", or "unknown"
status_daemon() {
	_ensure_systemd_env
	local label="$1"
	local state
	state=$(systemctl --user is-active "$label" 2>/dev/null || echo "unknown")
	case "$state" in
	active) echo "running" ;;
	inactive | failed | deactivating) echo "stopped" ;;
	*) echo "unknown" ;;
	esac
}
