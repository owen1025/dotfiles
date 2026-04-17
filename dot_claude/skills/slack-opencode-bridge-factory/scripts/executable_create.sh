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
	if [[ -f "$PROJECT_DIR/opencode.json" ]]; then
		echo "WARNING: $PROJECT_DIR/opencode.json already exists."
		printf "Overwrite? (yes/no): "
		read -r confirm
		[[ "$confirm" != "yes" ]] && die "Aborted."
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

	factory_create_bot "$WORKSPACE" "$AGENT_NAME" "$DISPLAY_NAME" || die "Slack App creation failed"
	# On rollback: remove bot from factory state (Slack App preserved; user can delete manually)
	rollback_register delete_registry "$AGENT_NAME"

	# 8. Project scaffolding
	local model_to_use="${MODEL:-anthropic/claude-sonnet-4-5}"

	# opencode.json
	local tmpl_opencode
	tmpl_opencode=$(find_template "opencode.json.tmpl")
	substitute_template "$tmpl_opencode" "$PROJECT_DIR/opencode.json" \
		"MODEL=$model_to_use"
	rollback_register rm_file "$PROJECT_DIR/opencode.json"

	# AGENTS.md
	if [[ -n "$ROLE_FILE" ]]; then
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
cmd_create "$@"
