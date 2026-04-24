#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/lib/detect_os.sh"
source "$SKILL_DIR/scripts/lib/registry.sh"
source "$SKILL_DIR/scripts/lib/daemon.sh"
source "$SKILL_DIR/scripts/lib/slack_integration.sh"
source "$SKILL_DIR/scripts/lib/env_manager.sh"

SYNC_BRIDGE=false
REFRESH_PEERS=false
AGENT_NAME=""

if [[ "${1:-}" == "--sync-bridge" ]]; then
	SYNC_BRIDGE=true
	shift
elif [[ "${1:-}" == "--refresh-peers" ]]; then
	REFRESH_PEERS=true
	shift
else
	AGENT_NAME="${1:-}"
	[[ -z "$AGENT_NAME" ]] && {
		echo "Usage: update.sh <agent-name> [--model M] [--role-file P] [--rotate-tokens] [--port N] [--icon <path>] [--sync-bridge] [--refresh-peers]" >&2
		echo "       update.sh --sync-bridge" >&2
		echo "       update.sh --refresh-peers [agent-name]" >&2
		exit 1
	}
	shift
fi

NEW_MODEL=""
ROLE_FILE=""
ROTATE_TOKENS=false
NEW_PORT=""
ICON_PATH=""

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
	--icon)
		ICON_PATH="$2"
		shift 2
		;;
	--sync-bridge)
		SYNC_BRIDGE=true
		shift
		;;
	--refresh-peers)
		REFRESH_PEERS=true
		shift
		;;
	*)
		echo "ERROR: Unknown option: $1" >&2
		exit 1
		;;
	esac
done

registry_init

refresh_peers() {
	local -a targets=()
	if [[ -n "$AGENT_NAME" ]]; then
		registry_exists "$AGENT_NAME" || {
			echo "ERROR: Agent '$AGENT_NAME' not found" >&2
			return 1
		}
		targets=("$AGENT_NAME")
	else
		while IFS= read -r line; do
			[[ -n "$line" ]] && targets+=("$line")
		done < <(registry_list)
	fi

	[[ ${#targets[@]} -eq 0 ]] && {
		echo "No agents registered"
		return 0
	}

	for agent in "${targets[@]}"; do
		entry=$(registry_get "$agent")
		my_bot=$(echo "$entry" | jq -r '.slack.bot_user_id // empty')
		br_label=$(echo "$entry" | jq -r '.daemon.bridge_label')

		if [[ -z "$my_bot" ]]; then
			echo "SKIP: $agent (no bot_user_id — pending-tokens?)"
			continue
		fi

		local -a peers=()
		while IFS= read -r peer; do
			[[ -n "$peer" && "$peer" != "$my_bot" ]] && peers+=("$peer")
		done < <(registry_get_all_bot_user_ids)

		local peers_csv
		peers_csv=$(
			IFS=,
			echo "${peers[*]:-}"
		)

		echo "Agent '$agent' (bot: $my_bot) — peers: ${peers_csv:-(none)}"

		agent_env_set "$agent" "ALLOWED_PEER_BOT_USERS" "$peers_csv"

		restart_daemon "$br_label" 2>/dev/null || echo "WARN: restart failed for $br_label"
	done

	echo ""
	echo "Refreshed peers for ${#targets[@]} agent(s)"
}

if [[ "$REFRESH_PEERS" == "true" ]]; then
	refresh_peers
	exit $?
fi

sync_bridge_all() {
	local -a targets=()
	if [[ -n "$AGENT_NAME" ]]; then
		registry_exists "$AGENT_NAME" || {
			echo "ERROR: Agent '$AGENT_NAME' not found" >&2
			return 1
		}
		targets=("$AGENT_NAME")
	else
		while IFS= read -r line; do
			[[ -n "$line" ]] && targets+=("$line")
		done < <(registry_list)
	fi

	[[ ${#targets[@]} -eq 0 ]] && {
		echo "No agents to sync"
		return 0
	}

	echo "=== Pre-flight: validating ${#targets[@]} agents ==="
	local -a valid_agents=()
	local -a invalid_agents=()
	for agent in "${targets[@]}"; do
		entry=$(registry_get "$agent")
		proj=$(echo "$entry" | jq -r '.project_dir')
		if [[ ! -d "$proj/bridge" ]] || [[ ! -d "$proj/bridge/.venv" ]]; then
			echo "SKIP: $agent — invalid project structure at $proj"
			invalid_agents+=("$agent")
			continue
		fi
		valid_agents+=("$agent")
	done

	[[ ${#valid_agents[@]} -eq 0 ]] && {
		echo "No valid agents to sync"
		return 1
	}

	echo "=== Updating bridge code (${#valid_agents[@]} agents) ==="
	local -a updated_agents=()
	local -a failed_agents=()
	TMPL_BRIDGE="$SKILL_DIR/templates/bridge"
	source "$SKILL_DIR/scripts/lib/opencode_json.sh"
	local bridge_files=(bridge.py session_store.py schedule_store.py scheduler_runtime.py scheduler_mcp.py requirements.txt)
	for agent in "${valid_agents[@]}"; do
		entry=$(registry_get "$agent")
		proj=$(echo "$entry" | jq -r '.project_dir')
		model=$(echo "$entry" | jq -r '.model')

		/bin/cp "$proj/bridge/bridge.py" "$proj/bridge/bridge.py.bak.$(date +%s)" 2>/dev/null || true

		local copy_ok=true
		for f in "${bridge_files[@]}"; do
			if ! /bin/cp "$TMPL_BRIDGE/$f" "$proj/bridge/$f.new" 2>/dev/null; then
				copy_ok=false
				break
			fi
		done

		if $copy_ok; then
			for f in "${bridge_files[@]}"; do
				mv "$proj/bridge/$f.new" "$proj/bridge/$f"
			done

			if "$proj/bridge/.venv/bin/pip" install -q -r "$proj/bridge/requirements.txt" 2>/dev/null; then
				python_bin="$proj/bridge/.venv/bin/python"
				if merge_opencode_config "$proj/opencode.json" "$model" \
					"$agent" "$python_bin" "$proj" "$HOME" 2>/dev/null; then
					echo "UPDATED: $agent"
					updated_agents+=("$agent")
				else
					echo "WARN: $agent — opencode.json merge failed (bridge updated, scheduler MCP not registered)"
					updated_agents+=("$agent")
				fi
			else
				echo "FAIL: $agent — pip install failed"
				failed_agents+=("$agent")
			fi
		else
			echo "FAIL: $agent — file copy failed"
			failed_agents+=("$agent")
			for f in "${bridge_files[@]}"; do
				/bin/rm -f "$proj/bridge/$f.new" 2>/dev/null || true
			done
		fi
	done

	[[ ${#updated_agents[@]} -eq 0 ]] && {
		echo "No agents successfully updated."
		return 1
	}

	echo "=== Simultaneous restart (${#updated_agents[@]} agents) ==="
	for agent in "${updated_agents[@]}"; do
		entry=$(registry_get "$agent")
		oc_label=$(echo "$entry" | jq -r '.daemon.opencode_label')
		br_label=$(echo "$entry" | jq -r '.daemon.bridge_label')
		(
			restart_daemon "$oc_label" 2>/dev/null
			restart_daemon "$br_label" 2>/dev/null
		) &
	done
	wait

	echo "=== Health check ==="
	local -a healthy=()
	local -a unhealthy=()
	for agent in "${updated_agents[@]}"; do
		entry=$(registry_get "$agent")
		port=$(echo "$entry" | jq -r '.port')
		local ok=false
		for i in $(seq 1 10); do
			sleep 2
			if curl -sf "http://localhost:$port/global/health" >/dev/null 2>&1; then
				ok=true
				break
			fi
		done
		if $ok; then
			healthy+=("$agent")
			echo "HEALTHY: $agent"
		else
			unhealthy+=("$agent")
			echo "UNHEALTHY: $agent (port $port not responding)"
		fi
	done

	echo ""
	echo "=== Sync Summary ==="
	echo "Updated: ${#updated_agents[@]} | Healthy: ${#healthy[@]} | Unhealthy: ${#unhealthy[@]} | Failed update: ${#failed_agents[@]} | Skipped: ${#invalid_agents[@]}"
	[[ ${#unhealthy[@]} -gt 0 || ${#failed_agents[@]} -gt 0 ]] && return 1
	return 0
}

if $SYNC_BRIDGE; then
	sync_bridge_all
	exit $?
fi

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
	FACTORY_COMMON="${HOME}/.config/opencode/skills/slack-bot-factory/lib/common.sh"
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

# -- icon update --
if [[ -n "$ICON_PATH" ]]; then
	[[ -f "$ICON_PATH" ]] || die "Icon file not found: $ICON_PATH"

	case "$ICON_PATH" in
	*.png | *.jpg | *.jpeg | *.gif) ;;
	*) die "Icon must be png, jpg, or gif: $ICON_PATH" ;;
	esac

	bot_token_env=$(echo "$entry" | jq -r '.slack.bot_token_env')
	bot_token=$(bash -c "source ~/.zshrc.local 2>/dev/null; echo \"\${${bot_token_env}:-}\"")
	[[ -z "$bot_token" ]] && die "Bot token env var $bot_token_env is empty"

	echo "Uploading icon: $ICON_PATH"
	response=$(curl -s -F "image=@$ICON_PATH" \
		-H "Authorization: Bearer $bot_token" \
		https://slack.com/api/users.setPhoto)

	if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
		echo "✓ Icon uploaded successfully"
	else
		error=$(echo "$response" | jq -r '.error // "unknown"')
		die "Icon upload failed: $error"
	fi
	# Icon update requires no daemon restart — profile is instant
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
