#!/usr/bin/env bash
# Wrapper around slack-bot-factory scripts.
# Source this file; do NOT execute directly.

FACTORY_DIR="${HOME}/.claude/skills/omc-learned/slack-bot-factory"
FACTORY_COMMON="${FACTORY_DIR}/lib/common.sh"
FACTORY_CREATE="${FACTORY_DIR}/scripts/create-bot.sh"
FACTORY_FINALIZE="${FACTORY_DIR}/scripts/finalize-bot.sh"

ensure_factory_installed() {
	test -f "$FACTORY_COMMON" || die "slack-bot-factory skill not found at $FACTORY_DIR. Install it first."
	test -f "$FACTORY_CREATE" || die "create-bot.sh missing from slack-bot-factory"
	test -f "$FACTORY_FINALIZE" || die "finalize-bot.sh missing from slack-bot-factory"
}

die_if_factory_missing() {
	ensure_factory_installed
}

# generate_manifest <name> <display_name>
# Outputs Slack App manifest JSON to stdout.
generate_manifest() {
	local name="$1"
	local display_name="$2"

	jq -n \
		--arg display_name "$display_name" \
		--arg description "OpenCode ${display_name} agent bridge" \
		'{
      display_information: {
        name: $display_name,
        description: $description
      },
      features: {
        bot_user: {
          display_name: $display_name,
          always_online: false
        }
      },
      oauth_config: {
        scopes: {
          bot: [
            "app_mentions:read",
            "chat:write",
            "channels:history",
            "channels:read"
          ]
        }
      },
      settings: {
        event_subscriptions: {
          bot_events: [
            "app_mention",
            "message.channels"
          ]
        },
        socket_mode_enabled: true,
        token_rotation_enabled: true
      }
    }'
}

# factory_create_bot <workspace> <agent_name> <display_name>
factory_create_bot() {
	local workspace="$1"
	local agent_name="$2"
	local display_name="$3"

	ensure_factory_installed
	bash "$FACTORY_CREATE" "$workspace" "$agent_name" "$display_name" \
		"true" \
		"app_mentions:read,chat:write,channels:history,channels:read" \
		"app_mention,message.channels"
}

# factory_finalize_bot <workspace> <agent_name> <app_token> <bot_token> <channels_csv>
# channels_csv can be "" to skip invite.
factory_finalize_bot() {
	local workspace="$1"
	local agent_name="$2"
	local app_token="$3"
	local bot_token="$4"
	local channels_csv="$5"

	ensure_factory_installed
	bash "$FACTORY_FINALIZE" "$workspace" "$agent_name" "$app_token" "$bot_token" "$channels_csv"
}

# factory_bot_exists <workspace> <agent_name>
# Returns exit 0 if bot entry exists, exit 1 otherwise.
factory_bot_exists() {
	local workspace="$1"
	local agent_name="$2"
	local state_file="${HOME}/.local/state/slack-bot-factory/workspaces/${workspace}.json"

	[ -f "$state_file" ] || return 1
	jq -e --arg n "$agent_name" '.bots[] | select(.name == $n)' "$state_file" >/dev/null 2>&1
}

# factory_get_bot_app_id <workspace> <agent_name>
# Prints app_id of bot entry from factory state.
factory_get_bot_app_id() {
	local workspace="$1"
	local agent_name="$2"
	local state_file="${HOME}/.local/state/slack-bot-factory/workspaces/${workspace}.json"

	[ -f "$state_file" ] || {
		echo ""
		return 1
	}
	jq -r --arg n "$agent_name" '.bots[] | select(.name == $n) | .app_id' "$state_file"
}

# factory_remove_bot_from_state <workspace> <agent_name>
# Removes bot entry from factory state JSON.
factory_remove_bot_from_state() {
	local workspace="$1"
	local agent_name="$2"
	local state_file="${HOME}/.local/state/slack-bot-factory/workspaces/${workspace}.json"

	[ -f "$state_file" ] || return 1
	local tmp
	tmp="$(mktemp "${state_file}.XXXXXX")"
	if jq --arg n "$agent_name" 'del(.bots[] | select(.name == $n))' "$state_file" >"$tmp"; then
		mv "$tmp" "$state_file"
	else
		rm -f "$tmp"
		return 1
	fi
}

# derive_env_var_name <workspace> <agent_name> <suffix>
# Returns uppercase: SLACK_{WORKSPACE}_{AGENT}_{SUFFIX}
# Converts hyphens to underscores, then uppercase.
derive_env_var_name() {
	local workspace="$1"
	local agent_name="$2"
	local suffix="$3"

	local ws agent sfx
	ws="$(printf '%s' "$workspace" | tr '[:lower:]-' '[:upper:]_')"
	agent="$(printf '%s' "$agent_name" | tr '[:lower:]-' '[:upper:]_')"
	sfx="$(printf '%s' "$suffix" | tr '[:lower:]-' '[:upper:]_')"
	printf 'SLACK_%s_%s_%s' "$ws" "$agent" "$sfx"
}
