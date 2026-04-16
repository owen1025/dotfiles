#!/usr/bin/env bash
# Shared helpers for slack-bot-factory scripts.
# Provides: state mgmt, Slack API wrappers, config token rotation, env var naming.

set -euo pipefail

readonly STATE_DIR="${SLACK_BOT_FACTORY_STATE_DIR:-$HOME/.local/state/slack-bot-factory}"
readonly WORKSPACES_DIR="$STATE_DIR/workspaces"
readonly ROTATION_THRESHOLD_SECONDS=36000

if [ -t 2 ]; then
	readonly C_RED=$'\033[31m'
	readonly C_GREEN=$'\033[32m'
	readonly C_YELLOW=$'\033[33m'
	readonly C_BLUE=$'\033[34m'
	readonly C_DIM=$'\033[2m'
	readonly C_RESET=$'\033[0m'
else
	readonly C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_DIM="" C_RESET=""
fi

info() { printf "%s%s%s\n" "$C_BLUE" "→ $*" "$C_RESET" >&2; }
success() { printf "%s%s%s\n" "$C_GREEN" "✓ $*" "$C_RESET" >&2; }
warn() { printf "%s%s%s\n" "$C_YELLOW" "⚠ $*" "$C_RESET" >&2; }
die() {
	printf "%s%s%s\n" "$C_RED" "✗ $*" "$C_RESET" >&2
	exit 1
}
dim() { printf "%s%s%s\n" "$C_DIM" "$*" "$C_RESET" >&2; }

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

check_deps() {
	require_cmd jq
	require_cmd curl
}

ensure_state_dir() {
	mkdir -p "$WORKSPACES_DIR"
	chmod 700 "$STATE_DIR" "$WORKSPACES_DIR"
}

state_file() {
	local workspace="$1"
	printf '%s/%s.json' "$WORKSPACES_DIR" "$workspace"
}

require_state_file() {
	local workspace="$1"
	local file
	file="$(state_file "$workspace")"
	[ -f "$file" ] || die "workspace '$workspace' not bootstrapped. Run: bootstrap-workspace.sh $workspace"
	printf '%s' "$file"
}

# atomic_jq_update <file> <jq-expression>
# Write via temp + rename to prevent partial writes corrupting the state file.
atomic_jq_update() {
	local file="$1"
	local expr="$2"
	local tmp
	tmp="$(mktemp "${file}.XXXXXX")"
	# shellcheck disable=SC2064
	trap "rm -f '$tmp'" EXIT

	if jq "$expr" "$file" >"$tmp"; then
		chmod 600 "$tmp"
		mv "$tmp" "$file"
		trap - EXIT
	else
		rm -f "$tmp"
		trap - EXIT
		die "jq update failed: $expr"
	fi
}

# slack_api <method> <endpoint> <token> [extra curl args...]
slack_api() {
	local method="$1" endpoint="$2" token="$3"
	shift 3

	local response
	response="$(
		curl -sS -X "$method" \
			-H "Authorization: Bearer $token" \
			"$@" \
			"https://slack.com/api/$endpoint"
	)" || die "curl failed calling $endpoint"

	printf '%s' "$response"
}

check_ok() {
	local response="$1"
	local context="${2:-api call}"
	local ok error
	ok="$(printf '%s' "$response" | jq -r '.ok // false')"
	if [ "$ok" != "true" ]; then
		error="$(printf '%s' "$response" | jq -r '.error // "unknown"')"
		dim "Response: $response"
		die "$context failed: $error"
	fi
}

# rotate_if_needed <workspace>
# CRITICAL: tooling.tokens.rotate invalidates the old refresh_token on call.
# If the atomic state update fails mid-rotation, the rotation chain breaks
# and the user must re-bootstrap via browser. Keep the jq expr minimal.
rotate_if_needed() {
	local workspace="$1"
	local file
	file="$(require_state_file "$workspace")"

	local issued_at now age
	issued_at="$(jq -r '.issued_at // 0' "$file")"
	now="$(date +%s)"
	age=$((now - issued_at))

	if [ "$age" -lt "$ROTATION_THRESHOLD_SECONDS" ]; then
		return 0
	fi

	info "Config token is ${age}s old, rotating..."

	local refresh_token
	refresh_token="$(jq -r '.refresh_token' "$file")"
	[ -n "$refresh_token" ] && [ "$refresh_token" != "null" ] ||
		die "refresh_token missing. Re-bootstrap required."

	local response
	response="$(curl -sS -X POST "https://slack.com/api/tooling.tokens.rotate" \
		--data-urlencode "refresh_token=$refresh_token")" ||
		die "rotation curl failed"

	local ok
	ok="$(printf '%s' "$response" | jq -r '.ok // false')"
	if [ "$ok" != "true" ]; then
		local error
		error="$(printf '%s' "$response" | jq -r '.error // "unknown"')"
		dim "Response: $response"
		warn "Rotation failed: $error. Run: bootstrap-workspace.sh $workspace"
		die "cannot proceed without valid config token"
	fi

	local new_token new_refresh
	new_token="$(printf '%s' "$response" | jq -r '.token')"
	new_refresh="$(printf '%s' "$response" | jq -r '.refresh_token')"

	atomic_jq_update "$file" "
    .config_token = \"$new_token\"
    | .refresh_token = \"$new_refresh\"
    | .issued_at = $now
  "

	success "Token rotated"
}

get_config_token() {
	local workspace="$1"
	local file
	file="$(require_state_file "$workspace")"
	rotate_if_needed "$workspace"
	jq -r '.config_token' "$file"
}

# env_var_name <workspace> <bot-name> <type>
# type ∈ {APP_TOKEN, BOT_TOKEN}. Normalizes hyphens→underscores, then uppercases.
env_var_name() {
	local workspace="$1" bot="$2" type="$3"
	local ws bot_upper
	ws="$(printf '%s' "$workspace" | tr '[:lower:]-' '[:upper:]_')"
	bot_upper="$(printf '%s' "$bot" | tr '[:lower:]-' '[:upper:]_')"
	printf 'SLACK_%s_%s_%s' "$ws" "$bot_upper" "$type"
}

read_secret() {
	local prompt="$1"
	local value
	printf '%s' "$prompt" >&2
	IFS= read -rs value
	printf '\n' >&2
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}
