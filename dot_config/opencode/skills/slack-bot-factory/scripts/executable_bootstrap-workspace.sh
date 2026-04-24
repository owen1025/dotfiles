#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

WORKSPACE="${1:-}"
if [ -z "$WORKSPACE" ]; then
	die "Usage: bootstrap-workspace.sh <workspace-slug>"
fi

if ! [[ "$WORKSPACE" =~ ^[a-z0-9-]+$ ]]; then
	die "workspace slug must be lowercase alphanumeric with hyphens: got '$WORKSPACE'"
fi

check_deps
ensure_state_dir

STATE_FILE="$(state_file "$WORKSPACE")"

if [ -f "$STATE_FILE" ]; then
	warn "Workspace '$WORKSPACE' already bootstrapped at:"
	dim "  $STATE_FILE"
	printf "Overwrite? [y/N] " >&2
	read -r answer
	[[ "$answer" =~ ^[Yy]$ ]] || die "aborted"
fi

cat >&2 <<EOF

==========================================================================
Bootstrap workspace: ${C_GREEN}${WORKSPACE}${C_RESET}
==========================================================================

1. 브라우저에서 https://api.slack.com/apps 열기
2. 우측 상단 프로필 드롭다운 → "Your App Configuration Tokens"
3. Workspace 드롭다운에서 '${WORKSPACE}' 선택 → "Generate Token"
4. 두 개의 토큰이 표시됩니다. 아래에 붙여넣으세요:

EOF

ACCESS_TOKEN="$(read_secret "Access Token (xoxe.xoxp-...): ")"
REFRESH_TOKEN="$(read_secret "Refresh Token (xoxe-...): ")"

if ! [[ "$ACCESS_TOKEN" =~ ^xoxe\.xoxp- ]]; then
	die "Access token format invalid. Expected 'xoxe.xoxp-...'"
fi
if ! [[ "$REFRESH_TOKEN" =~ ^xoxe- ]]; then
	die "Refresh token format invalid. Expected 'xoxe-...'"
fi

info "Validating token with Slack API..."
RESPONSE="$(curl -sS "https://slack.com/api/auth.test" \
	-H "Authorization: Bearer $ACCESS_TOKEN")"
OK="$(printf '%s' "$RESPONSE" | jq -r '.ok // false')"
if [ "$OK" != "true" ]; then
	ERROR="$(printf '%s' "$RESPONSE" | jq -r '.error // "unknown"')"
	die "Token validation failed: $ERROR"
fi

TEAM_NAME="$(printf '%s' "$RESPONSE" | jq -r '.team // "unknown"')"
TEAM_ID="$(printf '%s' "$RESPONSE" | jq -r '.team_id // "unknown"')"
USER_NAME="$(printf '%s' "$RESPONSE" | jq -r '.user // "unknown"')"

info "Team: $TEAM_NAME ($TEAM_ID), User: $USER_NAME"

NOW="$(date +%s)"
TMP="$(mktemp "${STATE_FILE}.XXXXXX")"
# shellcheck disable=SC2064
trap "rm -f '$TMP'" EXIT

jq -n \
	--arg ws "$WORKSPACE" \
	--arg team "$TEAM_NAME" \
	--arg team_id "$TEAM_ID" \
	--arg access "$ACCESS_TOKEN" \
	--arg refresh "$REFRESH_TOKEN" \
	--argjson issued "$NOW" \
	'{
    workspace: $ws,
    team_name: $team,
    team_id: $team_id,
    config_token: $access,
    refresh_token: $refresh,
    issued_at: $issued,
    bots: []
  }' >"$TMP"

chmod 600 "$TMP"
mv "$TMP" "$STATE_FILE"
trap - EXIT

success "Workspace '$WORKSPACE' bootstrapped"
dim "  State: $STATE_FILE"
dim "  Team: $TEAM_NAME"
dim "  Config token valid for ~12h (auto-rotated on next use)"
