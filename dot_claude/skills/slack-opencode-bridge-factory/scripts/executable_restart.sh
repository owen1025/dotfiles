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

# Restart opencode (unless --only bridge)
if [[ -z "$ONLY" || "$ONLY" == "opencode" ]]; then
	echo "Restarting $OC_LABEL..."
	restart_daemon "$OC_LABEL"
fi

# Restart bridge (unless --only opencode)
if [[ -z "$ONLY" || "$ONLY" == "bridge" ]]; then
	echo "Restarting $BR_LABEL..."
	restart_daemon "$BR_LABEL"
fi

# Health check
echo "Checking health..."
local_ok=false
for i in $(seq 1 10); do
	sleep 2
	if curl -sf "http://localhost:$PORT/global/health" >/dev/null 2>&1; then
		local_ok=true
		break
	fi
done
$local_ok && echo "opencode: OK" || echo "WARN: opencode health check failed"

echo "Status:"
echo "  $OC_LABEL: $(status_daemon "$OC_LABEL")"
echo "  $BR_LABEL: $(status_daemon "$BR_LABEL")"
