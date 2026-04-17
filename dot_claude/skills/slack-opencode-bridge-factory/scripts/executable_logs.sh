#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib/registry.sh"

AGENT_NAME="${1:-}"
[[ -z "$AGENT_NAME" ]] && {
	echo "Usage: logs.sh <agent-name> [--tail N] [--follow] [--only opencode|bridge]" >&2
	exit 1
}
shift

TAIL_N=50
FOLLOW=false
ONLY=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--tail)
		TAIL_N="$2"
		shift 2
		;;
	-f | --follow)
		FOLLOW=true
		shift
		;;
	--only)
		ONLY="$2"
		shift 2
		;;
	*)
		echo "ERROR: Unknown option: $1" >&2
		exit 1
		;;
	esac
done

registry_init
registry_exists "$AGENT_NAME" || {
	echo "ERROR: Agent '$AGENT_NAME' not found" >&2
	exit 1
}

entry=$(registry_get "$AGENT_NAME")
LOG_DIR=$(echo "$entry" | jq -r '.log_dir')

OC_LOG="$LOG_DIR/opencode.log"
BR_LOG="$LOG_DIR/bridge.log"

show_log() {
	local logname="$1"
	local logfile="$2"
	if [[ ! -f "$logfile" ]]; then
		echo "[$logname] No log file found: $logfile"
		return
	fi
	echo "=== $logname ==="
	if $FOLLOW; then
		tail -f -n "$TAIL_N" "$logfile"
	else
		tail -n "$TAIL_N" "$logfile"
	fi
}

if [[ -z "$ONLY" || "$ONLY" == "opencode" ]]; then
	show_log "opencode" "$OC_LOG"
fi
if [[ -z "$ONLY" || "$ONLY" == "bridge" ]]; then
	show_log "bridge" "$BR_LOG"
fi
