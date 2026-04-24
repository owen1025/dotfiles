#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib/detect_os.sh"
source "$SKILL_DIR/scripts/lib/registry.sh"
source "$SKILL_DIR/scripts/lib/daemon.sh"

# Parse args
JSON_OUTPUT=false
FILTER_NAME=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--json)
		JSON_OUTPUT=true
		shift
		;;
	--name)
		FILTER_NAME="$2"
		shift 2
		;;
	*)
		echo "ERROR: Unknown option: $1" >&2
		exit 1
		;;
	esac
done

registry_init

# Get agent names
NAMES=()
while IFS= read -r line; do
	[[ -n "$line" ]] && NAMES+=("$line")
done < <(registry_list)

if [[ -n "$FILTER_NAME" ]]; then
	if ! registry_exists "$FILTER_NAME"; then
		echo "ERROR: Agent '$FILTER_NAME' not found" >&2
		exit 1
	fi
	NAMES=("$FILTER_NAME")
fi

if [[ ${#NAMES[@]} -eq 0 ]]; then
	echo "No agents registered. Use: omo-bridge create --name <agent>"
	exit 0
fi

if $JSON_OUTPUT; then
	# Output full registry as JSON with live status injected
	jq '.agents' "$HOME/.config/opencode-bridges/registry.json" 2>/dev/null || echo '{}'
	exit 0
fi

# Table output
printf "%-20s %-6s %-35s %-8s %-10s\n" "NAME" "PORT" "MODEL" "STATUS" "WORKSPACE"
printf "%-20s %-6s %-35s %-8s %-10s\n" "----" "----" "-----" "------" "---------"

for name in "${NAMES[@]}"; do
	entry=$(registry_get "$name")
	port=$(echo "$entry" | jq -r '.port // "?"')
	model=$(echo "$entry" | jq -r '.model // "?"' | sed 's/anthropic\///')
	workspace=$(echo "$entry" | jq -r '.slack.workspace_slug // "?"')
	oc_label=$(echo "$entry" | jq -r '.daemon.opencode_label // ""')
	br_label=$(echo "$entry" | jq -r '.daemon.bridge_label // ""')

	# Live status check
	oc_status=$(status_daemon "$oc_label" 2>/dev/null || echo "unknown")
	br_status=$(status_daemon "$br_label" 2>/dev/null || echo "unknown")

	if [[ "$oc_status" == "running" && "$br_status" == "running" ]]; then
		live_status="running"
	elif [[ "$oc_status" == "stopped" || "$br_status" == "stopped" ]]; then
		live_status="stopped"
	else
		# Check registry status as fallback
		live_status=$(echo "$entry" | jq -r '.status // "unknown"')
	fi

	printf "%-20s %-6s %-35s %-8s %-10s\n" "$name" "$port" "$model" "$live_status" "$workspace"
done
