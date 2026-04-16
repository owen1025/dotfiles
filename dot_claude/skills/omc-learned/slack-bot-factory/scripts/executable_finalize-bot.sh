#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

usage() {
	cat >&2 <<EOF
Usage: finalize-bot.sh <workspace> <bot-name> <xapp-or-none> <xoxb> <channels-csv>

Arguments:
  workspace       Workspace slug
  bot-name        Bot slug (must match create-bot.sh)
  xapp-or-none    App-Level Token (xapp-...) or "none" if Socket Mode disabled
  xoxb            Bot User OAuth Token (xoxb-...)
  channels-csv    Channels to auto-invite (e.g., "#dev,#general"), or "" to skip

Example (Socket Mode):
  finalize-bot.sh noanswer secretary xapp-... xoxb-... "#dev,#general"

Example (push-only):
  finalize-bot.sh noanswer notifier none xoxb-... "#alerts"
EOF
	exit 1
}

[ $# -eq 5 ] || usage

WORKSPACE="$1"
BOT_NAME="$2"
APP_TOKEN="$3"
BOT_TOKEN="$4"
CHANNELS_CSV="$5"

check_deps

STATE_FILE="$(require_state_file "$WORKSPACE")"

BOT_ENTRY="$(jq -r --arg name "$BOT_NAME" '.bots[] | select(.name == $name)' "$STATE_FILE")"
if [ -z "$BOT_ENTRY" ]; then
	die "bot '$BOT_NAME' not found in workspace '$WORKSPACE'. Run create-bot.sh first."
fi

SOCKET_MODE="$(printf '%s' "$BOT_ENTRY" | jq -r '.socket_mode')"

if [ "$SOCKET_MODE" = "true" ]; then
	if [ "$APP_TOKEN" = "none" ]; then
		die "bot has socket_mode=true but xapp token is 'none'"
	fi
	if ! [[ "$APP_TOKEN" =~ ^xapp- ]]; then
		die "App-Level Token format invalid. Expected 'xapp-...', got: ${APP_TOKEN:0:10}..."
	fi
else
	if [ "$APP_TOKEN" != "none" ]; then
		warn "bot has socket_mode=false but xapp token provided. Using it anyway."
	fi
fi

if ! [[ "$BOT_TOKEN" =~ ^xoxb- ]]; then
	die "Bot token format invalid. Expected 'xoxb-...', got: ${BOT_TOKEN:0:10}..."
fi

info "Validating bot token..."
AUTH_RESPONSE="$(slack_api POST "auth.test" "$BOT_TOKEN")"
check_ok "$AUTH_RESPONSE" "auth.test"
BOT_USER_ID="$(printf '%s' "$AUTH_RESPONSE" | jq -r '.user_id')"
info "Bot user ID: $BOT_USER_ID"

APP_VAR="$(env_var_name "$WORKSPACE" "$BOT_NAME" "APP_TOKEN")"
BOT_VAR="$(env_var_name "$WORKSPACE" "$BOT_NAME" "BOT_TOKEN")"

ZSHRC_LOCAL="$HOME/.zshrc.local"
if [ ! -f "$ZSHRC_LOCAL" ]; then
	warn "$ZSHRC_LOCAL not found. Creating it."
	touch "$ZSHRC_LOCAL"
	chmod 600 "$ZSHRC_LOCAL"
fi

if grep -q "^export ${BOT_VAR}=" "$ZSHRC_LOCAL" 2>/dev/null; then
	warn "$BOT_VAR already exists in ~/.zshrc.local. Not overwriting."
	warn "Manually edit if token changed."
else
	{
		echo ""
		echo "# $WORKSPACE / $BOT_NAME (added $(date +%Y-%m-%d))"
		if [ "$SOCKET_MODE" = "true" ] && [ "$APP_TOKEN" != "none" ]; then
			echo "export ${APP_VAR}=\"${APP_TOKEN}\""
		fi
		echo "export ${BOT_VAR}=\"${BOT_TOKEN}\""
	} >>"$ZSHRC_LOCAL"
	success "Appended tokens to ~/.zshrc.local"
fi

JOINED=()
FAILED=()

if [ -n "$CHANNELS_CSV" ]; then
	info "Resolving channels..."
	CHANNELS_RESPONSE="$(slack_api GET "conversations.list?limit=1000&types=public_channel,private_channel" "$BOT_TOKEN")"
	check_ok "$CHANNELS_RESPONSE" "conversations.list"

	IFS=',' read -r -a CHANNELS_ARR <<<"$CHANNELS_CSV"
	for raw_ch in "${CHANNELS_ARR[@]}"; do
		ch="${raw_ch#\#}"
		ch="$(printf '%s' "$ch" | tr -d '[:space:]')"
		[ -z "$ch" ] && continue

		CH_INFO="$(printf '%s' "$CHANNELS_RESPONSE" | jq -r --arg name "$ch" \
			'.channels[] | select(.name == $name) | {id: .id, is_private: .is_private, is_member: .is_member}')"

		if [ -z "$CH_INFO" ]; then
			warn "#$ch not found (doesn't exist or bot can't see it)"
			FAILED+=("#$ch")
			continue
		fi

		CH_ID="$(printf '%s' "$CH_INFO" | jq -r '.id')"
		IS_PRIVATE="$(printf '%s' "$CH_INFO" | jq -r '.is_private')"
		IS_MEMBER="$(printf '%s' "$CH_INFO" | jq -r '.is_member')"

		if [ "$IS_MEMBER" = "true" ]; then
			info "#$ch already joined ($CH_ID)"
			JOINED+=("#$ch")
			continue
		fi

		if [ "$IS_PRIVATE" = "true" ]; then
			warn "#$ch is private. Cannot auto-join. Manually: /invite @${BOT_NAME}"
			FAILED+=("#$ch (private)")
			continue
		fi

		JOIN_RESPONSE="$(slack_api POST "conversations.join" "$BOT_TOKEN" \
			--data-urlencode "channel=$CH_ID")"
		JOIN_OK="$(printf '%s' "$JOIN_RESPONSE" | jq -r '.ok // false')"
		if [ "$JOIN_OK" = "true" ]; then
			success "Joined #$ch ($CH_ID)"
			JOINED+=("#$ch")
		else
			JOIN_ERR="$(printf '%s' "$JOIN_RESPONSE" | jq -r '.error // "unknown"')"
			warn "Failed to join #$ch: $JOIN_ERR"
			FAILED+=("#$ch ($JOIN_ERR)")
		fi
	done
fi

JOINED_JSON="$(printf '%s\n' "${JOINED[@]}" | jq -R . | jq -s .)"
FINALIZED_AT="$(date +%s)"

atomic_jq_update "$STATE_FILE" "
  (.bots[] | select(.name == \"$BOT_NAME\")) |= (
    .channels_joined = $JOINED_JSON
    | .finalized_at = $FINALIZED_AT
    | .bot_user_id = \"$BOT_USER_ID\"
  )
"

cat >&2 <<EOF

==========================================================================
${C_GREEN}✅ Done${C_RESET}
==========================================================================

Bot: ${BOT_NAME} in workspace ${WORKSPACE}
Bot user ID: $BOT_USER_ID

Environment variables:
EOF

if [ "$SOCKET_MODE" = "true" ] && [ "$APP_TOKEN" != "none" ]; then
	echo "  \$$APP_VAR" >&2
fi
echo "  \$$BOT_VAR" >&2

if [ ${#JOINED[@]} -gt 0 ]; then
	echo "" >&2
	echo "Joined channels:" >&2
	printf '  %s\n' "${JOINED[@]}" >&2
fi

if [ ${#FAILED[@]} -gt 0 ]; then
	echo "" >&2
	echo "Failed channels (manual /invite needed):" >&2
	printf '  %s\n' "${FAILED[@]}" >&2
fi

cat >&2 <<EOF

Next: source ~/.zshrc.local  (or open new shell)
Bot runtime setup (separate): @slack/bolt, slack-bolt-python, etc.
EOF
