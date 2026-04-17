#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib/detect_os.sh"
source "$SKILL_DIR/scripts/lib/registry.sh"
source "$SKILL_DIR/scripts/lib/env_manager.sh"
source "$SKILL_DIR/scripts/lib/opencode_json.sh"
source "$SKILL_DIR/scripts/lib/slack_integration.sh"
source "$SKILL_DIR/scripts/lib/daemon.sh"

AGENT_NAME="${1:-}"
[[ -z "$AGENT_NAME" ]] && {
	echo "Usage: migrate.sh <agent-name> [--dry-run]" >&2
	exit 1
}
shift

DRY_RUN=false
while [[ $# -gt 0 ]]; do
	case "$1" in
	--dry-run)
		DRY_RUN=true
		shift
		;;
	*)
		echo "ERROR: Unknown option: $1" >&2
		exit 1
		;;
	esac
done

# Helper
say() {
	if $DRY_RUN; then
		echo "[DRY-RUN] $*"
	else
		echo "$*"
	fi
}

# Utility: run command (or simulate)
run() {
	if $DRY_RUN; then
		echo "[DRY-RUN] $ $*"
	else
		"$@"
	fi
}

# Find template file (supports optional .literal suffix from chezmoi)
find_template() {
	local base_name="$1"
	local found
	found=$(ls "$SKILL_DIR/templates/"${base_name}* 2>/dev/null | head -1)
	[[ -z "$found" ]] && die "Template not found: $base_name"
	echo "$found"
}

# Substitute {{KEY}} placeholders in a template file
substitute_template() {
	local src="$1"
	local dst="$2"
	shift 2

	local content
	content=$(/bin/cat "$src")
	while [[ $# -gt 0 ]]; do
		local key="${1%%=*}"
		local val="${1#*=}"
		content="${content//\{\{$key\}\}/$val}"
		shift
	done
	printf '%s\n' "$content" >"$dst"
}

# ===== Pre-flight =====
AGENT_UPPER=$(echo "$AGENT_NAME" | tr '[:lower:]-' '[:upper:]_')

# Find live launchd labels (they may differ from V1 convention)
OLD_OC_LABEL=""
OLD_BR_LABEL=""
while IFS= read -r label; do
	if echo "$label" | grep -qE "(opencode[-_]${AGENT_NAME}|${AGENT_NAME}[-_]opencode)"; then
		OLD_OC_LABEL="$label"
	fi
	if echo "$label" | grep -qE "(${AGENT_NAME}[-_]bridge)"; then
		OLD_BR_LABEL="$label"
	fi
done < <(launchctl list 2>/dev/null | awk '{print $3}' | grep -v "^-$" | grep -i "$AGENT_NAME" || true)

say "Detected live labels:"
say "  opencode: ${OLD_OC_LABEL:-(not running)}"
say "  bridge:   ${OLD_BR_LABEL:-(not running)}"

# Legacy env var pattern: SLACK_OWEN_{AGENT}_{BOT,APP}_TOKEN
OLD_BOT_VAR="SLACK_OWEN_${AGENT_UPPER}_BOT_TOKEN"
OLD_APP_VAR="SLACK_OWEN_${AGENT_UPPER}_APP_TOKEN"

grep -q "^export ${OLD_BOT_VAR}=" ~/.zshrc.local || die "Legacy env var $OLD_BOT_VAR not found"
grep -q "^export ${OLD_APP_VAR}=" ~/.zshrc.local || die "Legacy env var $OLD_APP_VAR not found"

# Read values (sourcing in subshell)
OLD_BOT_TOKEN=$(bash -c "source ~/.zshrc.local 2>/dev/null; echo \"\${${OLD_BOT_VAR}:-}\"")
OLD_APP_TOKEN=$(bash -c "source ~/.zshrc.local 2>/dev/null; echo \"\${${OLD_APP_VAR}:-}\"")
[[ -z "$OLD_BOT_TOKEN" ]] && die "Could not read $OLD_BOT_VAR value"
[[ -z "$OLD_APP_TOKEN" ]] && die "Could not read $OLD_APP_VAR value"

WORKSPACE="noanswer"
WORKSPACE_UPPER=$(echo "$WORKSPACE" | tr '[:lower:]-' '[:upper:]_')
NEW_BOT_VAR="SLACK_${WORKSPACE_UPPER}_${AGENT_UPPER}_BOT_TOKEN"
NEW_APP_VAR="SLACK_${WORKSPACE_UPPER}_${AGENT_UPPER}_APP_TOKEN"

# Project paths
PROJECT_DIR="/Users/owen/Desktop/owen/${AGENT_NAME}" # V2 is Secretary-specific; generalize if needed
[[ -d "$PROJECT_DIR/bridge" ]] || die "Project dir not found: $PROJECT_DIR/bridge"

SESSIONS_DB="$PROJECT_DIR/bridge/sessions.db"

# sessions.db row count (preserve check)
DB_ROWS_BEFORE=0
if [[ -f "$SESSIONS_DB" ]]; then
	DB_ROWS_BEFORE=$(sqlite3 "$SESSIONS_DB" "SELECT COUNT(*) FROM thread_sessions;" 2>/dev/null || echo 0)
fi
say "Sessions DB rows: $DB_ROWS_BEFORE"

# Port (from live launchd or default)
PORT=4096

# Get bot_user_id via auth.test
BOT_USER_ID=$(curl -s -H "Authorization: Bearer $OLD_BOT_TOKEN" https://slack.com/api/auth.test | jq -r '.user_id // empty')
[[ -z "$BOT_USER_ID" ]] && die "Could not get bot_user_id from auth.test"
say "Bot User ID: $BOT_USER_ID"

APP_ID=$(curl -s -H "Authorization: Bearer $OLD_BOT_TOKEN" https://slack.com/api/auth.test | jq -r '.app_id // "unknown"')

# Standard labels for V2
NEW_OC_LABEL="com.owen.${AGENT_NAME}-opencode"
NEW_BR_LABEL="com.owen.${AGENT_NAME}-bridge"
LOG_DIR="$HOME/.local/log/opencode-bridges/${AGENT_NAME}"
ENV_FILE="$HOME/.config/opencode-bridges/${AGENT_NAME}.env"
WRAPPER_OC="$HOME/.local/bin/${AGENT_NAME}-opencode-serve.sh"
WRAPPER_BR="$HOME/.local/bin/${AGENT_NAME}-bridge.sh"
OPENCODE_BIN=$(detect_opencode_path)

MIGRATE_FAILED=false

# ===== Migration Steps =====

# Step 1: Stop old daemons
say ""
say "Step 1: Stop legacy daemons"
if [[ -n "$OLD_OC_LABEL" ]]; then
	run launchctl bootout "gui/$(id -u)/$OLD_OC_LABEL" 2>/dev/null || true
fi
if [[ -n "$OLD_BR_LABEL" ]]; then
	run launchctl bootout "gui/$(id -u)/$OLD_BR_LABEL" 2>/dev/null || true
fi

# Step 2: Add new env vars (KEEP old vars — add-first-remove-last)
say ""
say "Step 2: Add new env vars (keeping old)"
if ! $DRY_RUN; then
	zshrc_local_set "$NEW_BOT_VAR" "$OLD_BOT_TOKEN"
	zshrc_local_set "$NEW_APP_VAR" "$OLD_APP_TOKEN"
fi
say "  Added: $NEW_BOT_VAR, $NEW_APP_VAR"

# Step 3: Factory state INSERT
say ""
say "Step 3: Insert into factory state"
FACTORY_STATE_DIR="$HOME/.local/state/slack-bot-factory/workspaces"
FACTORY_STATE_FILE="$FACTORY_STATE_DIR/${WORKSPACE}.json"
if ! $DRY_RUN; then
	mkdir -p "$FACTORY_STATE_DIR"
	if [[ ! -f "$FACTORY_STATE_FILE" ]]; then
		echo "{\"workspace\":\"${WORKSPACE}\",\"bots\":[]}" >"$FACTORY_STATE_FILE"
	fi
	if ! jq -e --arg n "$AGENT_NAME" '.bots[] | select(.name == $n)' "$FACTORY_STATE_FILE" >/dev/null 2>&1; then
		tmp=$(mktemp)
		jq --arg n "$AGENT_NAME" --arg app_id "$APP_ID" \
			'.bots += [{name:$n, app_id:$app_id, socket_mode:true}]' \
			"$FACTORY_STATE_FILE" >"$tmp" && mv "$tmp" "$FACTORY_STATE_FILE"
	fi
fi

# Step 4: Rebuild registry entry
say ""
say "Step 4: Rebuild registry entry"
registry_init
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if ! $DRY_RUN; then
	registry_set "$AGENT_NAME" "$(jq -n \
		--arg name "$AGENT_NAME" --arg pd "$PROJECT_DIR" --arg port "$PORT" \
		--arg model "anthropic/claude-sonnet-4-5" --arg ws "$WORKSPACE" \
		--arg bev "$NEW_BOT_VAR" --arg aev "$NEW_APP_VAR" --arg buid "$BOT_USER_ID" \
		--arg oclbl "$NEW_OC_LABEL" --arg brlbl "$NEW_BR_LABEL" \
		--arg logdir "$LOG_DIR" --arg ts "$TS" \
		'{name:$name, project_dir:$pd, port:($port|tonumber), model:$model, host:"local", os:"macos", status:"migrating",
		  slack:{workspace_slug:$ws, bot_token_env:$bev, app_token_env:$aev, bot_user_id:$buid},
		  daemon:{opencode_label:$oclbl, bridge_label:$brlbl},
		  log_dir:$logdir, created_at:$ts, updated_at:$ts}')"
fi

# Step 5: Copy template bridge.py
say ""
say "Step 5: Install new bridge.py template"
if ! $DRY_RUN; then
	/bin/cp "$SKILL_DIR/templates/bridge/bridge.py" "$PROJECT_DIR/bridge/bridge.py"
	/bin/cp "$SKILL_DIR/templates/bridge/session_store.py" "$PROJECT_DIR/bridge/session_store.py"
	/bin/cp "$SKILL_DIR/templates/bridge/requirements.txt" "$PROJECT_DIR/bridge/requirements.txt"
	# Legacy secretary_bridge.py stays as backup
fi

# Step 6: opencode.json (merge, Secretary currently has none)
say ""
say "Step 6: Generate opencode.json"
if ! $DRY_RUN; then
	merge_opencode_config "$PROJECT_DIR/opencode.json" "anthropic/claude-sonnet-4-5" || die "opencode.json generation failed"
fi

# Step 7: Create new wrappers
say ""
say "Step 7: Generate new wrapper scripts"
if ! $DRY_RUN; then
	mkdir -p "$HOME/.local/bin" "$LOG_DIR" "$HOME/.config/opencode-bridges"

	# env file
	agent_env_write "$AGENT_NAME" \
		SLACK_BOT_TOKEN "\${$NEW_BOT_VAR}" \
		SLACK_APP_TOKEN "\${$NEW_APP_VAR}" \
		SLACK_OWNER_ID "${SLACK_OWNER_ID:-U0ASB6S6SP4}" \
		OPENCODE_URL "http://localhost:$PORT" \
		OPENCODE_PORT "$PORT" \
		OPENCODE_AGENT "build" \
		AGENT_NAME "$AGENT_NAME" \
		BRIDGE_LOG_DIR "$LOG_DIR" \
		BRIDGE_LOG_PATH "$LOG_DIR/bridge.log"

	# wrapper scripts from templates
	TMPL_WRAP_OC=$(find_template "wrapper_opencode.sh.tmpl")
	TMPL_WRAP_BR=$(find_template "wrapper_bridge.sh.tmpl")
	PYTHON_BIN="$PROJECT_DIR/bridge/.venv/bin/python"

	substitute_template "$TMPL_WRAP_OC" "$WRAPPER_OC" \
		"AGENT_NAME=$AGENT_NAME" \
		"ENV_FILE=$ENV_FILE" \
		"LOG_DIR=$LOG_DIR" \
		"PROJECT_DIR=$PROJECT_DIR" \
		"OPENCODE_BIN=$OPENCODE_BIN" \
		"PORT=$PORT"
	chmod +x "$WRAPPER_OC"

	substitute_template "$TMPL_WRAP_BR" "$WRAPPER_BR" \
		"AGENT_NAME=$AGENT_NAME" \
		"ENV_FILE=$ENV_FILE" \
		"LOG_DIR=$LOG_DIR" \
		"PROJECT_DIR=$PROJECT_DIR" \
		"PYTHON_BIN=$PYTHON_BIN"
	chmod +x "$WRAPPER_BR"
fi

# Step 8: Create new plists + install daemons
say ""
say "Step 8: Install new launchd daemons"
if ! $DRY_RUN; then
	mkdir -p "$PROJECT_DIR/daemons"
	TMPL_PL_OC=$(find_template "launchd_opencode.plist.tmpl")
	TMPL_PL_BR=$(find_template "launchd_bridge.plist.tmpl")

	PLIST_OC="$PROJECT_DIR/daemons/$NEW_OC_LABEL.plist"
	PLIST_BR="$PROJECT_DIR/daemons/$NEW_BR_LABEL.plist"
	HOME_DIR="$HOME"

	substitute_template "$TMPL_PL_OC" "$PLIST_OC" \
		"AGENT_NAME=$AGENT_NAME" \
		"LAUNCHD_LABEL=$NEW_OC_LABEL" \
		"WRAPPER_OPENCODE=$WRAPPER_OC" \
		"HOME_DIR=$HOME_DIR" \
		"LOG_DIR=$LOG_DIR" \
		"PORT=$PORT"

	substitute_template "$TMPL_PL_BR" "$PLIST_BR" \
		"AGENT_NAME=$AGENT_NAME" \
		"LAUNCHD_LABEL=$NEW_BR_LABEL" \
		"WRAPPER_BRIDGE=$WRAPPER_BR" \
		"HOME_DIR=$HOME_DIR" \
		"LOG_DIR=$LOG_DIR"

	install_daemon "$NEW_OC_LABEL" "$PLIST_OC" "$HOME/Library/LaunchAgents/$NEW_OC_LABEL.plist"
	install_daemon "$NEW_BR_LABEL" "$PLIST_BR" "$HOME/Library/LaunchAgents/$NEW_BR_LABEL.plist"
fi

# Step 9: Health check
say ""
say "Step 9: Health check"
if ! $DRY_RUN; then
	HEALTH_OK=false
	for i in $(seq 1 10); do
		sleep 3
		if curl -sf "http://localhost:$PORT/global/health" >/dev/null 2>&1; then
			HEALTH_OK=true
			break
		fi
	done
	$HEALTH_OK || {
		echo "ERROR: health check failed — rolling back" >&2
		MIGRATE_FAILED=true
	}

	BRIDGE_OK=false
	for i in $(seq 1 10); do
		sleep 3
		if grep -q "Bolt app is running" "$LOG_DIR/bridge.log" 2>/dev/null; then
			BRIDGE_OK=true
			break
		fi
	done
	$BRIDGE_OK || {
		echo "ERROR: bridge connect failed — rolling back" >&2
		MIGRATE_FAILED=true
	}
fi

# Step 10: Cleanup or rollback
if ! $DRY_RUN; then
	if [[ "$MIGRATE_FAILED" == "true" ]]; then
		echo "ROLLBACK: Removing new artifacts, reinstalling legacy daemons"
		uninstall_daemon "$NEW_OC_LABEL" "$HOME/Library/LaunchAgents/$NEW_OC_LABEL.plist" 2>/dev/null || true
		uninstall_daemon "$NEW_BR_LABEL" "$HOME/Library/LaunchAgents/$NEW_BR_LABEL.plist" 2>/dev/null || true
		/bin/rm -f "$WRAPPER_OC" "$WRAPPER_BR"
		agent_env_delete "$AGENT_NAME"
		registry_delete "$AGENT_NAME"
		# Reinstall legacy
		[[ -f "$HOME/Library/LaunchAgents/$OLD_OC_LABEL.plist" ]] && launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$OLD_OC_LABEL.plist"
		[[ -f "$HOME/Library/LaunchAgents/$OLD_BR_LABEL.plist" ]] && launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$OLD_BR_LABEL.plist"
		exit 1
	fi

	echo ""
	echo "Step 10: Remove legacy artifacts"
	zshrc_local_unset "$OLD_BOT_VAR"
	zshrc_local_unset "$OLD_APP_VAR"
	/bin/rm -f "$HOME/.local/bin/${AGENT_NAME}-opencode-serve.sh.old" 2>/dev/null
	# Delete old plists if they are different names
	if [[ -n "$OLD_OC_LABEL" && "$OLD_OC_LABEL" != "$NEW_OC_LABEL" ]]; then
		/bin/rm -f "$HOME/Library/LaunchAgents/$OLD_OC_LABEL.plist"
	fi
	if [[ -n "$OLD_BR_LABEL" && "$OLD_BR_LABEL" != "$NEW_BR_LABEL" ]]; then
		/bin/rm -f "$HOME/Library/LaunchAgents/$OLD_BR_LABEL.plist"
	fi

	# Update registry status
	entry=$(registry_get "$AGENT_NAME")
	registry_set "$AGENT_NAME" "$(echo "$entry" | jq '.status = "running"')"
fi

# Step 11: Verify sessions.db preserved
DB_ROWS_AFTER=0
if [[ -f "$SESSIONS_DB" ]]; then
	DB_ROWS_AFTER=$(sqlite3 "$SESSIONS_DB" "SELECT COUNT(*) FROM thread_sessions;" 2>/dev/null || echo 0)
fi
say ""
say "Sessions DB rows: before=$DB_ROWS_BEFORE, after=$DB_ROWS_AFTER"

say ""
say "Migration complete for '$AGENT_NAME'"
