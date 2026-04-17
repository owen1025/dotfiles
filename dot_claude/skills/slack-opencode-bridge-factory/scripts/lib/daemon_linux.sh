#!/usr/bin/env bash
# daemon_linux.sh — systemd daemon management (Linux) — V2 STUB
# Source this file; do NOT execute directly.

_linux_daemon_stub() {
	echo "ERROR: Linux systemd daemon support is not implemented in V1. Coming in V2." >&2
	return 1
}

install_daemon() { _linux_daemon_stub; }
uninstall_daemon() { _linux_daemon_stub; }
start_daemon() { _linux_daemon_stub; }
stop_daemon() { _linux_daemon_stub; }
restart_daemon() { _linux_daemon_stub; }
status_daemon() { _linux_daemon_stub; }
