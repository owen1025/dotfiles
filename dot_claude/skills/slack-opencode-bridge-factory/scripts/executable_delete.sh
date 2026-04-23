#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib/detect_os.sh"
source "$SKILL_DIR/scripts/lib/registry.sh"
source "$SKILL_DIR/scripts/lib/daemon.sh"
source "$SKILL_DIR/scripts/lib/env_manager.sh"
source "$SKILL_DIR/scripts/lib/slack_integration.sh"
source "$SKILL_DIR/scripts/lib/kg_writer.sh"

AGENT_NAME="${1:-}"
[[ -z "$AGENT_NAME" ]] && {
	echo "Usage: delete.sh <agent-name> [--force] [--purge-project] [--purge-logs]" >&2
	exit 1
}
shift

FORCE=false
PURGE_PROJECT=false
PURGE_LOGS=false
while [[ $# -gt 0 ]]; do
	case "$1" in
	--force)
		FORCE=true
		shift
		;;
	--purge-project)
		PURGE_PROJECT=true
		shift
		;;
	--purge-logs)
		PURGE_LOGS=true
		shift
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
BOT_TOKEN_ENV=$(echo "$entry" | jq -r '.slack.bot_token_env')
APP_TOKEN_ENV=$(echo "$entry" | jq -r '.slack.app_token_env')
LOG_DIR=$(echo "$entry" | jq -r '.log_dir')
PROJECT_DIR=$(echo "$entry" | jq -r '.project_dir')
WORKSPACE=$(echo "$entry" | jq -r '.slack.workspace_slug')

# Confirmation
if ! $FORCE; then
	echo "About to delete agent: $AGENT_NAME"
	echo "  Daemons: $OC_LABEL, $BR_LABEL"
	echo "  Env vars: $BOT_TOKEN_ENV, $APP_TOKEN_ENV"
	echo "  Project: $PROJECT_DIR (preserved unless --purge-project)"
	echo "  Slack App: preserved (manual deletion required)"
	printf "Confirm deletion? (yes/no): "
	read -r confirm
	[[ "$confirm" != "yes" ]] && {
		echo "Aborted."
		exit 0
	}
fi

echo "Deleting agent '$AGENT_NAME'..."

# 1. Stop and uninstall daemons
OC_PLIST="$HOME/Library/LaunchAgents/$OC_LABEL.plist"
BR_PLIST="$HOME/Library/LaunchAgents/$BR_LABEL.plist"
uninstall_daemon "$OC_LABEL" "$OC_PLIST" 2>/dev/null || echo "WARN: Could not uninstall $OC_LABEL"
uninstall_daemon "$BR_LABEL" "$BR_PLIST" 2>/dev/null || echo "WARN: Could not uninstall $BR_LABEL"

# 2. Remove wrapper scripts
/bin/rm -f "$HOME/.local/bin/$AGENT_NAME-opencode-serve.sh" || true
/bin/rm -f "$HOME/.local/bin/$AGENT_NAME-bridge.sh" || true

# 3. Remove env file
agent_env_delete "$AGENT_NAME"

# 4. Remove env vars from ~/.zshrc.local
zshrc_local_unset "$BOT_TOKEN_ENV"
zshrc_local_unset "$APP_TOKEN_ENV"

# 5. Remove from factory state
factory_remove_bot_from_state "$WORKSPACE" "$AGENT_NAME" 2>/dev/null || echo "WARN: Could not remove from factory state"

registry_delete "$AGENT_NAME"

SCHEDULE_DB="$HOME/.config/opencode-bridges/$AGENT_NAME-schedules.db"
if [[ -f "$SCHEDULE_DB" ]]; then
	/bin/rm -f "$SCHEDULE_DB" "$SCHEDULE_DB-wal" "$SCHEDULE_DB-shm" || true
	echo "Schedule DB removed: $SCHEDULE_DB"
fi

# 7. Optional: purge project
if $PURGE_PROJECT; then
	echo "Purging project: $PROJECT_DIR"
	if [[ -d "$PROJECT_DIR" ]]; then
		/bin/rm -rf "$PROJECT_DIR/bridge" "$PROJECT_DIR/daemons" "$PROJECT_DIR/opencode.json"
		echo "Project bridge/daemons/opencode.json removed (AGENTS.md preserved)"
	fi
fi

# 8. Optional: purge logs
if $PURGE_LOGS; then
	echo "Purging logs: $LOG_DIR"
	/bin/rm -rf "$LOG_DIR" || true
fi

echo ""
echo "=== KG Deletion JSON (for Memory MCP) ==="
kg_bot_delete_json "$AGENT_NAME"
kg_agent_delete_json "$AGENT_NAME"
echo "========================================="

echo ""
echo "✓ Agent '$AGENT_NAME' deleted."
echo "  Slack App: preserved — delete manually at https://api.slack.com/apps if needed"
