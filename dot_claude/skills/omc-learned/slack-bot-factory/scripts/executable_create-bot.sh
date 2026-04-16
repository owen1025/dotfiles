#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

usage() {
	cat >&2 <<EOF
Usage: create-bot.sh <workspace> <bot-name> <display-name> <socket-mode> <bot-scopes-csv> <bot-events-csv>

Arguments:
  workspace       Workspace slug (must be bootstrapped first)
  bot-name        Bot slug, lowercase + hyphens (e.g., secretary)
  display-name    UI name (quote if contains spaces, e.g., "Secretary Bot")
  socket-mode     true | false
  bot-scopes-csv  Comma-separated bot scopes (e.g., "chat:write,app_mentions:read")
  bot-events-csv  Comma-separated bot events, or "" if none (e.g., "app_mention")

Example:
  create-bot.sh noanswer secretary "Secretary" true \\
    "app_mentions:read,chat:write,channels:history" "app_mention"
EOF
	exit 1
}

[ $# -eq 6 ] || usage

WORKSPACE="$1"
BOT_NAME="$2"
DISPLAY_NAME="$3"
SOCKET_MODE="$4"
SCOPES_CSV="$5"
EVENTS_CSV="$6"

if ! [[ "$BOT_NAME" =~ ^[a-z0-9-]+$ ]]; then
	die "bot name must be lowercase alphanumeric with hyphens: got '$BOT_NAME'"
fi
if [ "$SOCKET_MODE" != "true" ] && [ "$SOCKET_MODE" != "false" ]; then
	die "socket-mode must be 'true' or 'false': got '$SOCKET_MODE'"
fi

check_deps

STATE_FILE="$(require_state_file "$WORKSPACE")"

EXISTING="$(jq -r --arg name "$BOT_NAME" '.bots[] | select(.name == $name) | .app_id' "$STATE_FILE")"
if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
	die "bot '$BOT_NAME' already exists in workspace '$WORKSPACE' (app_id: $EXISTING)"
fi

IFS=',' read -r -a SCOPES_ARR <<<"$SCOPES_CSV"
SCOPES_JSON="$(printf '%s\n' "${SCOPES_ARR[@]}" | jq -R . | jq -s .)"

if [ -n "$EVENTS_CSV" ]; then
	IFS=',' read -r -a EVENTS_ARR <<<"$EVENTS_CSV"
	EVENTS_JSON="$(printf '%s\n' "${EVENTS_ARR[@]}" | jq -R . | jq -s .)"
else
	EVENTS_JSON='[]'
fi

MANIFEST="$(
	jq -n \
		--arg name "$DISPLAY_NAME" \
		--arg bot_name "$BOT_NAME" \
		--argjson socket_mode "$SOCKET_MODE" \
		--argjson scopes "$SCOPES_JSON" \
		--argjson events "$EVENTS_JSON" \
		'{
    display_information: { name: $name },
    features: {
      bot_user: { display_name: $bot_name, always_online: true }
    },
    oauth_config: {
      scopes: { bot: $scopes }
    },
    settings: {
      event_subscriptions: { bot_events: $events },
      interactivity: { is_enabled: false },
      org_deploy_enabled: false,
      socket_mode_enabled: $socket_mode,
      token_rotation_enabled: false
    }
  }'
)"

info "Creating app '$DISPLAY_NAME' in workspace '$WORKSPACE'..."

CONFIG_TOKEN="$(get_config_token "$WORKSPACE")"

RESPONSE="$(slack_api POST "apps.manifest.create" "$CONFIG_TOKEN" \
	--data-urlencode "manifest=$MANIFEST")"

check_ok "$RESPONSE" "apps.manifest.create"

APP_ID="$(printf '%s' "$RESPONSE" | jq -r '.app_id')"
CREATED_AT="$(date +%s)"

atomic_jq_update "$STATE_FILE" "
  .bots += [{
    name: \"$BOT_NAME\",
    display_name: \"$DISPLAY_NAME\",
    app_id: \"$APP_ID\",
    created_at: $CREATED_AT,
    socket_mode: $SOCKET_MODE,
    scopes: $SCOPES_JSON,
    events: $EVENTS_JSON,
    channels_joined: []
  }]
"

success "App created: $APP_ID"

cat >&2 <<EOF

==========================================================================
브라우저에서 2개 작업 필요:
==========================================================================

EOF

if [ "$SOCKET_MODE" = "true" ]; then
	cat >&2 <<EOF
[1/2] App-Level Token 발급 (Socket Mode)
      → https://api.slack.com/apps/${APP_ID}/general
      → 페이지 아래 "App-Level Tokens" 섹션
      → "Generate Token and Scopes"
      → Token Name: 아무거나 (예: default)
      → Scope 추가: connections:write
      → Generate → ${C_YELLOW}xapp-${C_RESET}... 복사

EOF
fi

cat >&2 <<EOF
[2/2] Workspace 설치
      → https://api.slack.com/apps/${APP_ID}/install-on-team
      → "Allow" 클릭
      → 설치 후 "OAuth & Permissions" 페이지에서
        ${C_YELLOW}Bot User OAuth Token${C_RESET} (xoxb-...) 복사

==========================================================================
준비되면 다음 명령으로 마무리:

  $SCRIPT_DIR/finalize-bot.sh $WORKSPACE $BOT_NAME <xapp-or-none> <xoxb> <channels-csv>

예시:
EOF

if [ "$SOCKET_MODE" = "true" ]; then
	echo "  $SCRIPT_DIR/finalize-bot.sh $WORKSPACE $BOT_NAME xapp-... xoxb-... '#dev,#general'" >&2
else
	echo "  $SCRIPT_DIR/finalize-bot.sh $WORKSPACE $BOT_NAME none xoxb-... '#alerts'" >&2
fi

printf '\nAPP_ID=%s\n' "$APP_ID"
