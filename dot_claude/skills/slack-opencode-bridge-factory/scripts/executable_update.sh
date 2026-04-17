#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib/detect_os.sh"
source "$SKILL_DIR/scripts/lib/registry.sh"
source "$SKILL_DIR/scripts/lib/daemon.sh"
source "$SKILL_DIR/scripts/lib/slack_integration.sh"

AGENT_NAME="${1:-}"
[[ -z "$AGENT_NAME" ]] && {
	echo "Usage: update.sh <agent-name> [--model M] [--role-file P] [--rotate-tokens] [--port N]" >&2
	exit 1
}
shift

NEW_MODEL=""
ROLE_FILE=""
ROTATE_TOKENS=false
NEW_PORT=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--model)
		NEW_MODEL="$2"
		shift 2
		;;
	--role-file)
		ROLE_FILE="$2"
		shift 2
		;;
	--rotate-tokens)
		ROTATE_TOKENS=true
		shift
		;;
	--port)
		NEW_PORT="$2"
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
PROJECT_DIR=$(echo "$entry" | jq -r '.project_dir')
WORKSPACE=$(echo "$entry" | jq -r '.slack.workspace_slug')
OC_LABEL=$(echo "$entry" | jq -r '.daemon.opencode_label')
BR_LABEL=$(echo "$entry" | jq -r '.daemon.bridge_label')
CURRENT_PORT=$(echo "$entry" | jq -r '.port')

needs_restart=false

# -- model update --
if [[ -n "$NEW_MODEL" ]]; then
	echo "Updating model to: $NEW_MODEL"
	cp "$PROJECT_DIR/opencode.json" "$PROJECT_DIR/opencode.json.bak" 2>/dev/null || true

	tmp=$(mktemp)
	jq --arg m "$NEW_MODEL" '.model = $m | .agent.build.model = $m' "$PROJECT_DIR/opencode.json" >"$tmp" &&
		mv "$tmp" "$PROJECT_DIR/opencode.json"

	new_entry=$(echo "$entry" | jq --arg m "$NEW_MODEL" '.model = $m')
	registry_set "$AGENT_NAME" "$new_entry"
	entry="$new_entry"

	needs_restart=true
	echo "Model updated: $NEW_MODEL"
fi

# -- role-file update --
if [[ -n "$ROLE_FILE" ]]; then
	[[ -f "$ROLE_FILE" ]] || {
		echo "ERROR: Role file not found: $ROLE_FILE" >&2
		exit 1
	}
	echo "Updating AGENTS.md from: $ROLE_FILE"
	cp "$ROLE_FILE" "$PROJECT_DIR/AGENTS.md"
	needs_restart=true
	echo "AGENTS.md updated"
fi

# -- token rotation --
if $ROTATE_TOKENS; then
	echo "Rotating workspace config token for: $WORKSPACE"
	FACTORY_COMMON="${HOME}/.claude/skills/omc-learned/slack-bot-factory/lib/common.sh"
	if [[ ! -f "$FACTORY_COMMON" ]]; then
		echo "ERROR: slack-bot-factory not found at $FACTORY_COMMON" >&2
		exit 1
	fi
	source "$FACTORY_COMMON"
	ensure_workspace_bootstrapped "$WORKSPACE"
	echo "Config token rotation complete."
	echo "NOTE: Bot token (xoxb-) and App token (xapp-) must be rotated manually via Slack UI."
fi

# -- port update --
if [[ -n "$NEW_PORT" ]]; then
	echo "Updating port from $CURRENT_PORT to $NEW_PORT"
	if lsof -i :"$NEW_PORT" -sTCP:LISTEN -t 2>/dev/null | grep -q .; then
		echo "ERROR: Port $NEW_PORT is already in use" >&2
		exit 1
	fi

	new_entry=$(echo "$entry" | jq --argjson p "$NEW_PORT" '.port = $p')
	registry_set "$AGENT_NAME" "$new_entry"
	entry="$new_entry"

	env_file="$HOME/.config/opencode-bridges/$AGENT_NAME.env"
	if [[ -f "$env_file" ]]; then
		sed -i.bak "s/OPENCODE_PORT=.*/OPENCODE_PORT=\"$NEW_PORT\"/" "$env_file"
		sed -i.bak "s|OPENCODE_URL=.*|OPENCODE_URL=\"http://localhost:$NEW_PORT\"|" "$env_file"
		/bin/rm -f "$env_file.bak"
	fi

	needs_restart=true
	echo "Port updated: $NEW_PORT"
fi

if $needs_restart; then
	echo "Restarting daemons..."
	restart_daemon "$OC_LABEL" 2>/dev/null || echo "WARN: Could not restart $OC_LABEL"
	restart_daemon "$BR_LABEL" 2>/dev/null || echo "WARN: Could not restart $BR_LABEL"
	echo "Daemons restarted."
fi

ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
entry=$(registry_get "$AGENT_NAME")
registry_set "$AGENT_NAME" "$(echo "$entry" | jq --arg ts "$ts" '.updated_at = $ts')"

echo "Agent '$AGENT_NAME' updated."
