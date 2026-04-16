#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../slack-bot-factory/lib/common.sh
source "$SCRIPT_DIR/../../slack-bot-factory/lib/common.sh"

usage() {
	echo "Usage: list-scopes.sh <workspace> <bot-name>" >&2
	exit 1
}

[ $# -eq 2 ] || usage

WORKSPACE="$1"
BOT_NAME="$2"

check_deps

STATE_FILE="$(require_state_file "$WORKSPACE")"

APP_ID="$(jq -r --arg name "$BOT_NAME" '.bots[] | select(.name == $name) | .app_id' "$STATE_FILE")"
if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
	die "bot '$BOT_NAME' not found in workspace '$WORKSPACE'"
fi

info "Fetching current manifest for app $APP_ID..."

CONFIG_TOKEN="$(get_config_token "$WORKSPACE")"

RESPONSE="$(slack_api POST "apps.manifest.export" "$CONFIG_TOKEN" \
	--data-urlencode "app_id=$APP_ID")"
check_ok "$RESPONSE" "apps.manifest.export"

MANIFEST="$(printf '%s' "$RESPONSE" | jq -r '.manifest')"

cat <<EOF

App ID:       $APP_ID
Bot:          $BOT_NAME ($WORKSPACE)
Display name: $(printf '%s' "$MANIFEST" | jq -r '.display_information.name')
Socket Mode:  $(printf '%s' "$MANIFEST" | jq -r '.settings.socket_mode_enabled')

Bot scopes:
$(printf '%s' "$MANIFEST" | jq -r '.oauth_config.scopes.bot[]?' | sed 's/^/  - /')

Bot events (if Socket Mode):
$(printf '%s' "$MANIFEST" | jq -r '.settings.event_subscriptions.bot_events[]? // "  (none)"' | sed 's/^/  - /')

EOF

NOW="$(date +%s)"
STATE_SCOPES="$(printf '%s' "$MANIFEST" | jq '.oauth_config.scopes.bot // []')"
STATE_EVENTS="$(printf '%s' "$MANIFEST" | jq '.settings.event_subscriptions.bot_events // []')"

atomic_jq_update "$STATE_FILE" "
  (.bots[] | select(.name == \"$BOT_NAME\")) |= (
    .scopes = $STATE_SCOPES
    | .events = $STATE_EVENTS
    | .last_synced_at = $NOW
  )
"

dim "(state file synced with Slack)"
