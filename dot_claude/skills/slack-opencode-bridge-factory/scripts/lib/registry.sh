#!/usr/bin/env bash
# registry.sh — CRUD for ~/.config/opencode-bridges/registry.json
# Source this file; do NOT execute directly

REGISTRY_FILE="${HOME}/.config/opencode-bridges/registry.json"

die() {
	echo "ERROR: $*" >&2
	exit 1
}

registry_init() {
	mkdir -p "$(dirname "$REGISTRY_FILE")"
	if [[ ! -f "$REGISTRY_FILE" ]]; then
		echo '{"version":1,"agents":{}}' >"$REGISTRY_FILE"
	fi
}

registry_exists() {
	local name="$1"
	[[ -z "$name" ]] && die "registry_exists: name required"
	registry_init
	jq -e --arg n "$name" '.agents[$n] != null' "$REGISTRY_FILE" >/dev/null 2>&1
}

registry_get() {
	local name="$1"
	[[ -z "$name" ]] && die "registry_get: name required"
	registry_init
	jq -r --arg n "$name" '.agents[$n] // empty' "$REGISTRY_FILE"
}

registry_set() {
	local name="$1"
	local json="$2"
	[[ -z "$name" ]] && die "registry_set: name required"
	[[ -z "$json" ]] && die "registry_set: json required"
	registry_init
	local tmp
	tmp=$(mktemp)
	jq --arg n "$name" --argjson val "$json" '.agents[$n] = $val' "$REGISTRY_FILE" >"$tmp" && mv "$tmp" "$REGISTRY_FILE"
}

registry_delete() {
	local name="$1"
	[[ -z "$name" ]] && die "registry_delete: name required"
	registry_init
	local tmp
	tmp=$(mktemp)
	jq --arg n "$name" 'del(.agents[$n])' "$REGISTRY_FILE" >"$tmp" && mv "$tmp" "$REGISTRY_FILE"
}

registry_list() {
	registry_init
	jq -r '.agents | keys[]' "$REGISTRY_FILE" 2>/dev/null || true
}

registry_get_port() {
	local name="$1"
	registry_get "$name" | jq -r '.port // empty'
}

registry_get_field() {
	local name="$1"
	local field="$2"
	registry_get "$name" | jq -r --arg f "$field" '.[$f] // empty'
}

# Get all bot_user_ids from registered agents (skipping those without bot_user_id)
registry_get_all_bot_user_ids() {
	registry_init
	jq -r '.agents | to_entries[] | .value.slack.bot_user_id // empty' "$REGISTRY_FILE"
}
