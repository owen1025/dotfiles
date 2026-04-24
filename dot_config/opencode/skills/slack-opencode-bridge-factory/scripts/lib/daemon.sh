#!/usr/bin/env bash
# daemon.sh — routes to platform-specific daemon library
# Source this file; it will source the correct OS-specific lib.

DAEMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"

# Detect OS if not already set
if [[ -z "${OS_TYPE:-}" ]]; then
	case "$(uname -s)" in
	Darwin) OS_TYPE="macos" ;;
	Linux) OS_TYPE="linux" ;;
	*) OS_TYPE="unknown" ;;
	esac
fi

case "$OS_TYPE" in
macos) source "$DAEMON_LIB_DIR/daemon_macos.sh" ;;
linux) source "$DAEMON_LIB_DIR/daemon_linux.sh" ;;
*)
	echo "ERROR: Unsupported OS: $OS_TYPE" >&2
	return 1
	;;
esac
