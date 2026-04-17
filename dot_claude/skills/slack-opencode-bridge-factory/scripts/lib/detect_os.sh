#!/bin/bash
# detect_os.sh — OS detection and opencode binary path resolution

# Detect OS type
OS_TYPE=""
case "$(uname -s)" in
Darwin)
	OS_TYPE="macos"
	;;
Linux)
	OS_TYPE="linux"
	;;
*)
	OS_TYPE="unknown"
	;;
esac

export OS_TYPE

# Error handler
die() {
	echo "ERROR: $*" >&2
	exit 1
}

# Detect opencode binary path
detect_opencode_path() {
	local opencode_path
	opencode_path=$(command -v opencode 2>/dev/null) || die "opencode binary not found in PATH"
	echo "$opencode_path"
}

# Ensure required dependencies are installed
ensure_deps() {
	local missing=()

	for dep in jq curl lsof; do
		if ! command -v "$dep" &>/dev/null; then
			missing+=("$dep")
		fi
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		die "Missing required dependencies: ${missing[*]}. Please install them and try again."
	fi
}
