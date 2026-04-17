#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load all libs
source "$SKILL_DIR/scripts/lib/detect_os.sh"
source "$SKILL_DIR/scripts/lib/registry.sh"
source "$SKILL_DIR/scripts/lib/port_scan.sh"
source "$SKILL_DIR/scripts/lib/env_manager.sh"
source "$SKILL_DIR/scripts/lib/rollback.sh"
source "$SKILL_DIR/scripts/lib/slack_integration.sh"
source "$SKILL_DIR/scripts/lib/kg_writer.sh"

# --- Constants ---
NAME_REGEX='^[a-z][a-z0-9-]{0,29}$'
RESERVED_NAMES="test list create delete kill restart logs update help finalize version main"
LOCK_DIR="${HOME}/.config/opencode-bridges/.creating.lock.d"
ACTIVE_LOCK=""
TMPL_DIR="$SKILL_DIR/templates"

# --- Helpers ---

validate_agent_name() {
	local name="$1"
	[[ -z "$name" ]] && die "Agent name is required (--name)"
	[[ ! "$name" =~ $NAME_REGEX ]] && die "Invalid agent name '$name'. Must match: ^[a-z][a-z0-9-]{0,29}$"
	for reserved in $RESERVED_NAMES; do
		[[ "$name" == "$reserved" ]] && die "Agent name '$name' is reserved. Choose a different name."
	done
	if registry_exists "$name"; then
		die "Agent '$name' already exists in registry. Use a different name or delete it first."
	fi
}

acquire_create_lock() {
	mkdir -p "$LOCK_DIR"
	local agent_lock="$LOCK_DIR/$AGENT_NAME"
	mkdir "$agent_lock" 2>/dev/null || die "Another create is in progress for '$AGENT_NAME'. Lock at: $agent_lock"
	ACTIVE_LOCK="$agent_lock"
	trap 'rmdir "$ACTIVE_LOCK" 2>/dev/null || true; rollback_execute' EXIT INT TERM
}

# Substitute {{KEY}} placeholders in a template file
# Usage: substitute_template src dst KEY1=VAL1 KEY2=VAL2 ...
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

# Find template file (supports optional .literal suffix from chezmoi)
find_template() {
	local base_name="$1"
	local found
	found=$(ls "$TMPL_DIR"/${base_name}* 2>/dev/null | head -1)
	[[ -z "$found" ]] && die "Template not found: $base_name"
	echo "$found"
}

# --- Phase 2: Finalize ---

cmd_finalize() {
	# Parse: first arg is agent name, then --bot-token, --app-token
	local AGENT_NAME=""
	local BOT_TOKEN=""
	local APP_TOKEN=""

	# Handle both positional and flag forms
	if [[ "${1:-}" != "--"* ]]; then
		AGENT_NAME="$1"
		shift
	fi

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--name)
			AGENT_NAME="$2"
			shift 2
			;;
		--bot-token)
			BOT_TOKEN="$2"
			shift 2
			;;
		--app-token)
			APP_TOKEN="$2"
			shift 2
			;;
		*)
			echo "ERROR: Unknown option: $1" >&2
			exit 1
			;;
		esac
	done

	[[ -z "$AGENT_NAME" ]] && die "Agent name required"
	registry_exists "$AGENT_NAME" || die "Agent '$AGENT_NAME' not found in registry. Run create first."

	# Interactive token input if not provided
	if [[ -z "$BOT_TOKEN" ]]; then
		printf "Bot Token (xoxb-...): "
		read -r BOT_TOKEN
	fi
	if [[ -z "$APP_TOKEN" ]]; then
		printf "App Token (xapp-...): "
		read -r APP_TOKEN
	fi
	[[ -z "$BOT_TOKEN" ]] && die "Bot token required"
	[[ -z "$APP_TOKEN" ]] && die "App token required"

	# Load entry from registry
	local entry
	entry=$(registry_get "$AGENT_NAME")
	local PORT
	PORT=$(echo "$entry" | jq -r '.port')
	local PROJECT_DIR
	PROJECT_DIR=$(echo "$entry" | jq -r '.project_dir')
	local WORKSPACE
	WORKSPACE=$(echo "$entry" | jq -r '.slack.workspace_slug')
	local BOT_TOKEN_ENV
	BOT_TOKEN_ENV=$(echo "$entry" | jq -r '.slack.bot_token_env')
	local APP_TOKEN_ENV
	APP_TOKEN_ENV=$(echo "$entry" | jq -r '.slack.app_token_env')
	local LOG_DIR
	LOG_DIR=$(echo "$entry" | jq -r '.log_dir')
	local OC_LABEL
	OC_LABEL=$(echo "$entry" | jq -r '.daemon.opencode_label')
	local BR_LABEL
	BR_LABEL=$(echo "$entry" | jq -r '.daemon.bridge_label')
	local WRAPPER_OC="$HOME/.local/bin/$AGENT_NAME-opencode-serve.sh"
	local WRAPPER_BR="$HOME/.local/bin/$AGENT_NAME-bridge.sh"

	# Rollback setup for Phase 2
	rollback_register unload_daemon "$OC_LABEL" "$HOME/Library/LaunchAgents/$OC_LABEL.plist"
	rollback_register unload_daemon "$BR_LABEL" "$HOME/Library/LaunchAgents/$BR_LABEL.plist"
	rollback_register unset_env "$BOT_TOKEN_ENV"
	rollback_register unset_env "$APP_TOKEN_ENV"
	rollback_register delete_registry "$AGENT_NAME"

	# 1. Finalize with factory (registers tokens)
	factory_finalize_bot "$WORKSPACE" "$AGENT_NAME" "$APP_TOKEN" "$BOT_TOKEN" ""

	# 2. Register tokens to ~/.zshrc.local
	zshrc_local_set "$BOT_TOKEN_ENV" "$BOT_TOKEN"
	zshrc_local_set "$APP_TOKEN_ENV" "$APP_TOKEN"

	# 3. Get bot_user_id via Slack auth.test
	local BOT_USER_ID
	BOT_USER_ID=$(curl -s -H "Authorization: Bearer $BOT_TOKEN" \
		"https://slack.com/api/auth.test" | jq -r '.user_id // empty')
	[[ -z "$BOT_USER_ID" ]] && {
		echo "WARN: Could not get bot_user_id from auth.test"
		BOT_USER_ID="unknown"
	}

	# 4. Generate launchd plist files from templates
	mkdir -p "$PROJECT_DIR/daemons"
	mkdir -p "$LOG_DIR"
	local OPENCODE_BIN
	OPENCODE_BIN=$(detect_opencode_path)
	local HOME_DIR="$HOME"

	# Find template files (may have .literal suffix)
	local TMPL_OC
	TMPL_OC=$(find_template "launchd_opencode.plist.tmpl")
	local TMPL_BR
	TMPL_BR=$(find_template "launchd_bridge.plist.tmpl")

	local PLIST_OC="$PROJECT_DIR/daemons/$OC_LABEL.plist"
	local PLIST_BR="$PROJECT_DIR/daemons/$BR_LABEL.plist"

	substitute_template "$TMPL_OC" "$PLIST_OC" \
		"AGENT_NAME=$AGENT_NAME" \
		"LAUNCHD_LABEL=$OC_LABEL" \
		"WRAPPER_OPENCODE=$WRAPPER_OC" \
		"HOME_DIR=$HOME_DIR" \
		"LOG_DIR=$LOG_DIR" \
		"PORT=$PORT"

	substitute_template "$TMPL_BR" "$PLIST_BR" \
		"AGENT_NAME=$AGENT_NAME" \
		"LAUNCHD_LABEL=$BR_LABEL" \
		"WRAPPER_BRIDGE=$WRAPPER_BR" \
		"HOME_DIR=$HOME_DIR" \
		"LOG_DIR=$LOG_DIR"

	# 5. Install daemons
	source "$SKILL_DIR/scripts/lib/daemon.sh"
	local LINK_OC="$HOME/Library/LaunchAgents/$OC_LABEL.plist"
	local LINK_BR="$HOME/Library/LaunchAgents/$BR_LABEL.plist"
	install_daemon "$OC_LABEL" "$PLIST_OC" "$LINK_OC"
	install_daemon "$BR_LABEL" "$PLIST_BR" "$LINK_BR"

	# 6. Health checks
	echo "Waiting for opencode serve to start..."
	local health_ok=false
	for i in $(seq 1 10); do
		sleep 3
		if curl -sf "http://localhost:$PORT/global/health" >/dev/null 2>&1; then
			health_ok=true
			break
		fi
		echo "  Attempt $i/10..."
	done
	if ! $health_ok; then
		die "opencode serve health check failed after 30s on port $PORT"
	fi
	echo "opencode serve: OK"

	echo "Waiting for bridge to connect..."
	local bridge_ok=false
	for i in $(seq 1 10); do
		sleep 3
		if grep -q "Bolt app is running" "$LOG_DIR/bridge.log" 2>/dev/null; then
			bridge_ok=true
			break
		fi
		echo "  Attempt $i/10..."
	done
	if ! $bridge_ok; then
		die "Bridge failed to connect within 30s. Check: $LOG_DIR/bridge.log"
	fi
	echo "Bridge: OK"

	# 7. Update registry with final data
	local timestamp
	timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	local new_entry
	new_entry=$(echo "$entry" | jq \
		--arg status "running" \
		--arg bot_user_id "$BOT_USER_ID" \
		--arg ts "$timestamp" \
		'.status = $status | .slack.bot_user_id = $bot_user_id | .updated_at = $ts')
	registry_set "$AGENT_NAME" "$new_entry"

	# 8. Save to Knowledge Graph (output JSON for caller to use)
	local kg_json
	local APP_ID
	APP_ID=$(factory_get_bot_app_id "$WORKSPACE" "$AGENT_NAME" 2>/dev/null || echo "unknown")
	kg_json=$(kg_bot_entity_json "$AGENT_NAME" "$WORKSPACE" "$APP_ID" "$BOT_USER_ID" "$BOT_TOKEN_ENV" "$APP_TOKEN_ENV")
	echo ""
	echo "=== Knowledge Graph Entity (paste this into MCP Memory if needed) ==="
	echo "$kg_json" | jq .
	echo "=================================================================="

	rollback_commit

	echo ""
	echo "Agent '$AGENT_NAME' is ready!"
	echo "  opencode: http://localhost:$PORT"
	echo "  bridge log: $LOG_DIR/bridge.log"
	echo "  Invite bot: /invite @$(echo "${AGENT_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${AGENT_NAME:1}"
}

# --- Phase 1: Create ---

cmd_create() {
	# 1. Parse args
	local AGENT_NAME=""
	local PROJECT_DIR=""
	local ROLE=""
	local ROLE_FILE=""
	local MODEL=""
	local WORKSPACE="noanswer"
	local PORT=""
	local HOST="local"

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--name)
			AGENT_NAME="$2"
			shift 2
			;;
		--project)
			PROJECT_DIR="$2"
			shift 2
			;;
		--role)
			ROLE="$2"
			shift 2
			;;
		--role-file)
			ROLE_FILE="$2"
			shift 2
			;;
		--model)
			MODEL="$2"
			shift 2
			;;
		--workspace)
			WORKSPACE="$2"
			shift 2
			;;
		--port)
			PORT="$2"
			shift 2
			;;
		--host)
			HOST="$2"
			shift 2
			;;
		*) die "Unknown option: $1" ;;
		esac
	done

	# 2. Name validation
	validate_agent_name "$AGENT_NAME"

	# 3. Acquire lock
	acquire_create_lock

	# 4. Interview: project dir
	if [[ -z "$PROJECT_DIR" ]]; then
		echo ""
		echo "Where is the project directory for agent '$AGENT_NAME'?"
		echo "This is where AGENTS.md, opencode.json, and bridge/ will be created."
		printf "Project path: "
		read -r PROJECT_DIR
	fi
	PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
	[[ -z "$PROJECT_DIR" ]] && die "Project directory is required"

	# 5. Validate project dir
	if [[ ! -d "$PROJECT_DIR" ]]; then
		echo "Creating directory: $PROJECT_DIR"
		mkdir -p "$PROJECT_DIR"
	fi
	if [[ -f "$PROJECT_DIR/AGENTS.md" ]]; then
		ROLE_FILE="__KEEP_EXISTING__"
	fi

	# 6. Port allocation
	if [[ -z "$PORT" ]]; then
		PORT=$(
			set +u
			allocate_port
		) || die "No available ports in range 4096-4196"
	fi
	echo "Using port: $PORT"

	# 7. Slack App creation (factory)
	local DISPLAY_NAME
	DISPLAY_NAME="$(echo "${AGENT_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${AGENT_NAME:1}"

	if [[ "${SKIP_FACTORY:-false}" != "true" ]]; then
		factory_create_bot "$WORKSPACE" "$AGENT_NAME" "$DISPLAY_NAME" || die "Slack App creation failed"
	else
		echo "SKIP_FACTORY: Skipping Slack App creation (test mode)"
	fi
	# On rollback: remove bot from factory state (Slack App preserved; user can delete manually)
	rollback_register delete_registry "$AGENT_NAME"

	# 8. Project scaffolding
	if [[ -z "$MODEL" ]]; then
		echo ""
		echo "Which model should this agent use?"
		echo "  Examples: anthropic/claude-sonnet-4-5, anthropic/claude-opus-4-5"
		printf "Model [anthropic/claude-sonnet-4-5]: "
		read -r MODEL
	fi
	local model_to_use="${MODEL:-anthropic/claude-sonnet-4-5}"

	# opencode.json (merge if exists, create if not)
	source "$SKILL_DIR/scripts/lib/opencode_json.sh"
	if [[ -f "$PROJECT_DIR/opencode.json" ]]; then
		/bin/cp "$PROJECT_DIR/opencode.json" "$PROJECT_DIR/opencode.json.pre-bridge.bak"
		rollback_register rm_file "$PROJECT_DIR/opencode.json.pre-bridge.bak"
	else
		rollback_register rm_file "$PROJECT_DIR/opencode.json"
	fi
	merge_opencode_config "$PROJECT_DIR/opencode.json" "$model_to_use" || die "opencode.json merge failed"

	# AGENTS.md
	if [[ "$ROLE_FILE" == "__KEEP_EXISTING__" ]]; then
		echo "Keeping existing AGENTS.md"
	elif [[ -n "$ROLE_FILE" ]]; then
		[[ -f "$ROLE_FILE" ]] || die "Role file not found: $ROLE_FILE"
		/bin/cp "$ROLE_FILE" "$PROJECT_DIR/AGENTS.md"
	elif [[ -n "$ROLE" ]]; then
		local tmpl_agents
		tmpl_agents=$(find_template "AGENTS.md.tmpl")
		substitute_template "$tmpl_agents" "$PROJECT_DIR/AGENTS.md" \
			"AGENT_NAME_CAPITALIZED=$DISPLAY_NAME" \
			"ROLE=$ROLE"
	else
		echo "What is this agent's role? (one sentence)"
		printf "Role: "
		read -r ROLE
		[[ -z "$ROLE" ]] && ROLE="General assistant agent"
		local tmpl_agents
		tmpl_agents=$(find_template "AGENTS.md.tmpl")
		substitute_template "$tmpl_agents" "$PROJECT_DIR/AGENTS.md" \
			"AGENT_NAME_CAPITALIZED=$DISPLAY_NAME" \
			"ROLE=$ROLE"
	fi
	rollback_register rm_file "$PROJECT_DIR/AGENTS.md"

	# bridge/ directory
	mkdir -p "$PROJECT_DIR/bridge"
	/bin/cp "$TMPL_DIR/bridge/bridge.py" "$PROJECT_DIR/bridge/bridge.py"
	/bin/cp "$TMPL_DIR/bridge/session_store.py" "$PROJECT_DIR/bridge/session_store.py"
	/bin/cp "$TMPL_DIR/bridge/requirements.txt" "$PROJECT_DIR/bridge/requirements.txt"
	rollback_register rm_dir "$PROJECT_DIR/bridge"

	# Python venv
	local opencode_bin
	opencode_bin=$(detect_opencode_path)
	local python_candidate
	python_candidate="$(dirname "$opencode_bin")/python3"
	if [[ -x "$python_candidate" ]]; then
		"$python_candidate" -m venv "$PROJECT_DIR/bridge/.venv" 2>/dev/null ||
			python3 -m venv "$PROJECT_DIR/bridge/.venv" || die "Failed to create Python venv"
	else
		python3 -m venv "$PROJECT_DIR/bridge/.venv" || die "Failed to create Python venv"
	fi
	"$PROJECT_DIR/bridge/.venv/bin/pip" install -q -r "$PROJECT_DIR/bridge/requirements.txt" ||
		die "Failed to install Python dependencies"

	# 9. Env file + wrappers
	local bot_token_env app_token_env log_dir python_bin
	bot_token_env=$(derive_env_var_name "$WORKSPACE" "$AGENT_NAME" "BOT_TOKEN")
	app_token_env=$(derive_env_var_name "$WORKSPACE" "$AGENT_NAME" "APP_TOKEN")
	log_dir="$HOME/.local/log/opencode-bridges/$AGENT_NAME"
	python_bin="$PROJECT_DIR/bridge/.venv/bin/python"

	# env file
	agent_env_write "$AGENT_NAME" \
		SLACK_BOT_TOKEN "\${$bot_token_env}" \
		SLACK_APP_TOKEN "\${$app_token_env}" \
		SLACK_OWNER_ID "${SLACK_OWNER_ID:-U0ASB6S6SP4}" \
		OPENCODE_URL "http://localhost:$PORT" \
		OPENCODE_PORT "$PORT" \
		OPENCODE_AGENT "build" \
		AGENT_NAME "$AGENT_NAME" \
		BRIDGE_LOG_DIR "$log_dir" \
		BRIDGE_LOG_PATH "$log_dir/bridge.log"
	rollback_register delete_env_file "$AGENT_NAME"

	# wrapper scripts
	mkdir -p "$HOME/.local/bin"
	local env_file="$HOME/.config/opencode-bridges/$AGENT_NAME.env"
	local wrapper_oc="$HOME/.local/bin/$AGENT_NAME-opencode-serve.sh"
	local wrapper_br="$HOME/.local/bin/$AGENT_NAME-bridge.sh"

	local tmpl_wrap_oc tmpl_wrap_br
	tmpl_wrap_oc=$(find_template "wrapper_opencode.sh.tmpl")
	tmpl_wrap_br=$(find_template "wrapper_bridge.sh.tmpl")

	substitute_template "$tmpl_wrap_oc" "$wrapper_oc" \
		"AGENT_NAME=$AGENT_NAME" \
		"ENV_FILE=$env_file" \
		"LOG_DIR=$log_dir" \
		"PROJECT_DIR=$PROJECT_DIR" \
		"OPENCODE_BIN=$opencode_bin" \
		"PORT=$PORT"
	chmod +x "$wrapper_oc"
	rollback_register rm_file "$wrapper_oc"

	substitute_template "$tmpl_wrap_br" "$wrapper_br" \
		"AGENT_NAME=$AGENT_NAME" \
		"ENV_FILE=$env_file" \
		"LOG_DIR=$log_dir" \
		"PROJECT_DIR=$PROJECT_DIR" \
		"PYTHON_BIN=$python_bin"
	chmod +x "$wrapper_br"
	rollback_register rm_file "$wrapper_br"

	# 10. Registry update (pending-tokens)
	local timestamp
	timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	registry_set "$AGENT_NAME" "$(jq -n \
		--arg name "$AGENT_NAME" \
		--arg project "$PROJECT_DIR" \
		--arg port "$PORT" \
		--arg model "$model_to_use" \
		--arg ws "$WORKSPACE" \
		--arg bot_env "$bot_token_env" \
		--arg app_env "$app_token_env" \
		--arg log_dir "$log_dir" \
		--arg oc_label "com.owen.$AGENT_NAME-opencode" \
		--arg br_label "com.owen.$AGENT_NAME-bridge" \
		--arg ts "$timestamp" \
		'{
      name: $name, project_dir: $project, port: ($port | tonumber),
      model: $model, host: "local", os: "macos", status: "pending-tokens",
      slack: {workspace_slug: $ws, bot_token_env: $bot_env, app_token_env: $app_env},
      daemon: {opencode_label: $oc_label, bridge_label: $br_label},
      log_dir: $log_dir, created_at: $ts, updated_at: $ts
    }')"

	# 11. Print Phase 2 instructions
	echo ""
	echo "╔═══════════════════════════════════════════════════════════════╗"
	echo "║  Phase 1 Complete! Manual steps required before Phase 2.    ║"
	echo "╚═══════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Agent '$AGENT_NAME' Slack App created. Complete these browser steps:"
	echo ""
	echo "1. App-Level Token:"
	echo "   → https://api.slack.com/apps"
	echo "   → Select '$DISPLAY_NAME' → Settings → Basic Information"
	echo "   → Scroll to 'App-Level Tokens' → Generate Token and Scopes"
	echo "   → Name: anything, Scope: connections:write"
	echo "   → Copy the xapp-... token"
	echo ""
	echo "2. Install to Workspace + Bot Token:"
	echo "   → OAuth & Permissions → Install to Workspace"
	echo "   → Copy the Bot User OAuth Token (xoxb-...)"
	echo ""
	echo "3. Invite bot to channel:"
	echo "   → In Slack: /invite @$DISPLAY_NAME"
	echo ""
	echo "Then run:"
	echo "  omo-bridge finalize $AGENT_NAME \\"
	echo "    --bot-token xoxb-... \\"
	echo "    --app-token xapp-..."
	echo ""

	# Phase 1 succeeded — clear rollback stack
	rollback_commit

	# Release lock (lock dir stays, individual agent lock removed by trap)
}

# --- Main ---
case "${1:-}" in
finalize)
	shift
	cmd_finalize "$@"
	;;
*) cmd_create "$@" ;;
esac
