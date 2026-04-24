#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib/detect_os.sh"
source "$SKILL_DIR/scripts/lib/registry.sh"
source "$SKILL_DIR/scripts/lib/daemon.sh"

AGENT_NAME="${1:-}"
[[ -z "$AGENT_NAME" ]] && {
	echo "Usage: restart.sh <agent-name> [--only opencode|bridge]" >&2
	exit 1
}
shift

ONLY=""
while [[ $# -gt 0 ]]; do
	case "$1" in
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
OC_LABEL=$(echo "$entry" | jq -r '.daemon.opencode_label')
BR_LABEL=$(echo "$entry" | jq -r '.daemon.bridge_label')
PORT=$(echo "$entry" | jq -r '.port')
LOG_DIR=$(echo "$entry" | jq -r '.log_dir')

# Snapshot the PID currently serving the opencode port so we can prove the
# restart actually replaced it. Without this the health check below would
# happily pass against a stale/stuck process (historical bug — see
# daemon_macos.sh restart_daemon header).
OLD_PORT_PID=""
if [[ -z "$ONLY" || "$ONLY" == "opencode" ]]; then
	if command -v lsof >/dev/null 2>&1; then
		OLD_PORT_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -1 || true)
	fi
fi

RESTART_FAILED=0

if [[ -z "$ONLY" || "$ONLY" == "opencode" ]]; then
	echo "Restarting $OC_LABEL..."
	if ! restart_daemon "$OC_LABEL" "$PORT"; then
		echo "ERROR: $OC_LABEL restart failed." >&2
		if [[ -n "$OLD_PORT_PID" ]]; then
			echo "Recovery: kill -9 $OLD_PORT_PID && launchctl kickstart -k gui/\$(id -u)/$OC_LABEL" >&2
		fi
		RESTART_FAILED=1
	fi
fi

if [[ -z "$ONLY" || "$ONLY" == "bridge" ]]; then
	echo "Restarting $BR_LABEL..."
	if ! restart_daemon "$BR_LABEL"; then
		echo "ERROR: $BR_LABEL restart failed." >&2
		RESTART_FAILED=1
	fi
fi

((RESTART_FAILED)) && exit 1

echo "Checking health..."
local_ok=false
for i in $(seq 1 10); do
	sleep 2
	if curl -sf "http://localhost:$PORT/global/health" >/dev/null 2>&1; then
		local_ok=true
		break
	fi
done

if [[ -z "$ONLY" || "$ONLY" == "opencode" ]]; then
	if command -v lsof >/dev/null 2>&1; then
		NEW_PORT_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -1 || true)
		if [[ -n "$OLD_PORT_PID" && -n "$NEW_PORT_PID" && "$OLD_PORT_PID" == "$NEW_PORT_PID" ]]; then
			echo "ERROR: port $PORT still held by old PID $OLD_PORT_PID — restart did not take effect." >&2
			echo "Recovery: kill -9 $OLD_PORT_PID && launchctl kickstart -k gui/\$(id -u)/$OC_LABEL" >&2
			exit 1
		fi
	fi
fi

$local_ok && echo "opencode: OK" || echo "WARN: opencode health check failed"

echo "Status:"
echo "  $OC_LABEL: $(status_daemon "$OC_LABEL" "$PORT")"
echo "  $BR_LABEL: $(status_daemon "$BR_LABEL")"
