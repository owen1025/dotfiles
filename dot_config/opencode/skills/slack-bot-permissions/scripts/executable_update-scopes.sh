#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../slack-bot-factory/lib/common.sh
source "$SCRIPT_DIR/../../slack-bot-factory/lib/common.sh"

usage() {
	cat >&2 <<EOF
Usage: update-scopes.sh <workspace> <bot-name> <op> <scopes-csv> [events-csv]

Operations:
  add       Add scopes (and events) to the existing set
  remove    Remove scopes (and events) from the existing set
  replace   Replace the entire scope list (and events if provided)

Examples:
  update-scopes.sh noanswer secretary add "files:read,files:write"
  update-scopes.sh noanswer secretary remove "channels:history"
  update-scopes.sh noanswer secretary replace "app_mentions:read,chat:write" "app_mention"

Notes:
  - Slack requires re-installing the app for scope changes to take effect.
  - events-csv only applies if the bot has socket_mode=true.
  - Pass "" for events-csv to leave events unchanged.
EOF
	exit 1
}

[ $# -ge 4 ] && [ $# -le 5 ] || usage

WORKSPACE="$1"
BOT_NAME="$2"
OP="$3"
SCOPES_CSV="$4"
EVENTS_CSV="${5:-}"

case "$OP" in
add | remove | replace) ;;
*) die "invalid op '$OP'. Must be: add, remove, or replace" ;;
esac

check_deps

STATE_FILE="$(require_state_file "$WORKSPACE")"

APP_ID="$(jq -r --arg name "$BOT_NAME" '.bots[] | select(.name == $name) | .app_id' "$STATE_FILE")"
if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
	die "bot '$BOT_NAME' not found in workspace '$WORKSPACE'"
fi

info "Fetching current manifest..."
CONFIG_TOKEN="$(get_config_token "$WORKSPACE")"

EXPORT_RESPONSE="$(slack_api POST "apps.manifest.export" "$CONFIG_TOKEN" \
	--data-urlencode "app_id=$APP_ID")"
check_ok "$EXPORT_RESPONSE" "apps.manifest.export"

MANIFEST="$(printf '%s' "$EXPORT_RESPONSE" | jq '.manifest')"

CURRENT_SCOPES="$(printf '%s' "$MANIFEST" | jq '.oauth_config.scopes.bot // []')"
CURRENT_EVENTS="$(printf '%s' "$MANIFEST" | jq '.settings.event_subscriptions.bot_events // []')"

IFS=',' read -r -a INPUT_SCOPES_ARR <<<"$SCOPES_CSV"
INPUT_SCOPES_JSON="$(printf '%s\n' "${INPUT_SCOPES_ARR[@]}" | jq -R . | jq -s .)"

if [ -n "$EVENTS_CSV" ]; then
	IFS=',' read -r -a INPUT_EVENTS_ARR <<<"$EVENTS_CSV"
	INPUT_EVENTS_JSON="$(printf '%s\n' "${INPUT_EVENTS_ARR[@]}" | jq -R . | jq -s .)"
else
	INPUT_EVENTS_JSON='null'
fi

case "$OP" in
add)
	NEW_SCOPES="$(jq -cn --argjson a "$CURRENT_SCOPES" --argjson b "$INPUT_SCOPES_JSON" \
		'$a + $b | unique')"
	if [ "$INPUT_EVENTS_JSON" != "null" ]; then
		NEW_EVENTS="$(jq -cn --argjson a "$CURRENT_EVENTS" --argjson b "$INPUT_EVENTS_JSON" \
			'$a + $b | unique')"
	else
		NEW_EVENTS="$CURRENT_EVENTS"
	fi
	;;
remove)
	NEW_SCOPES="$(jq -cn --argjson a "$CURRENT_SCOPES" --argjson b "$INPUT_SCOPES_JSON" \
		'$a - $b')"
	if [ "$INPUT_EVENTS_JSON" != "null" ]; then
		NEW_EVENTS="$(jq -cn --argjson a "$CURRENT_EVENTS" --argjson b "$INPUT_EVENTS_JSON" \
			'$a - $b')"
	else
		NEW_EVENTS="$CURRENT_EVENTS"
	fi
	;;
replace)
	NEW_SCOPES="$INPUT_SCOPES_JSON"
	if [ "$INPUT_EVENTS_JSON" != "null" ]; then
		NEW_EVENTS="$INPUT_EVENTS_JSON"
	else
		NEW_EVENTS="$CURRENT_EVENTS"
	fi
	;;
esac

cat >&2 <<EOF

Current scopes: $(printf '%s' "$CURRENT_SCOPES" | jq -c .)
New scopes:     $(printf '%s' "$NEW_SCOPES" | jq -c .)

Current events: $(printf '%s' "$CURRENT_EVENTS" | jq -c .)
New events:     $(printf '%s' "$NEW_EVENTS" | jq -c .)

EOF

printf "Apply these changes? [y/N] " >&2
read -r answer
[[ "$answer" =~ ^[Yy]$ ]] || die "aborted"

NEW_MANIFEST="$(printf '%s' "$MANIFEST" | jq \
	--argjson scopes "$NEW_SCOPES" \
	--argjson events "$NEW_EVENTS" \
	'.oauth_config.scopes.bot = $scopes
   | .settings.event_subscriptions.bot_events = $events')"

info "Calling apps.manifest.update..."
UPDATE_RESPONSE="$(slack_api POST "apps.manifest.update" "$CONFIG_TOKEN" \
	--data-urlencode "app_id=$APP_ID" \
	--data-urlencode "manifest=$NEW_MANIFEST")"
check_ok "$UPDATE_RESPONSE" "apps.manifest.update"

NOW="$(date +%s)"
atomic_jq_update "$STATE_FILE" "
  (.bots[] | select(.name == \"$BOT_NAME\")) |= (
    .scopes = $NEW_SCOPES
    | .events = $NEW_EVENTS
    | .last_synced_at = $NOW
    | .last_updated_at = $NOW
  )
"

success "Manifest updated"

cat >&2 <<EOF

${C_YELLOW}⚠️  Re-install required${C_RESET} — scope changes only take effect after re-installation:

   → https://api.slack.com/apps/${APP_ID}/install-on-team
   → Click "Re-install to Workspace"
   → Review new permissions → Allow

In most cases the Bot Token stays the same. If the bot stops working after
re-install, check OAuth & Permissions page for a new xoxb- and update
~/.zshrc.local manually.
EOF
