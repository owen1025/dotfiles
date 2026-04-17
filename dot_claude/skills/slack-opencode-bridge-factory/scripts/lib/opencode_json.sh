#!/usr/bin/env bash
# opencode_json.sh — merge logic for opencode.json
# Source this file; do NOT execute directly

# merge_opencode_config {target_path} {model}
# Returns 0 on success, 1 on conflict-aborted or invalid JSON
merge_opencode_config() {
	local target="$1"
	local model="$2"

	[[ -z "$target" ]] && {
		echo "ERROR: target path required" >&2
		return 1
	}
	[[ -z "$model" ]] && {
		echo "ERROR: model required" >&2
		return 1
	}

	# Case 1: file doesn't exist — write fresh
	if [[ ! -f "$target" ]]; then
		cat >"$target" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "$model",
  "agent": {
    "build": {
      "mode": "primary",
      "model": "$model",
      "prompt": "{file:./AGENTS.md}"
    }
  }
}
EOF
		return 0
	fi

	# Case 2: invalid JSON (JSONC with comments/trailing commas, or malformed)
	if ! jq '.' "$target" >/dev/null 2>&1; then
		echo "ERROR: $target is not valid JSON (JSONC comments/trailing commas not supported)" >&2
		echo "Manual merge required. Add this to agent.build:" >&2
		echo '  "agent": { "build": { "mode": "primary", "model": "'"$model"'", "prompt": "{file:./AGENTS.md}" } }' >&2
		return 1
	fi

	# Case 3: agent.build already exists — confirm overwrite
	if jq -e '.agent.build' "$target" >/dev/null 2>&1; then
		echo "WARNING: agent.build already exists in $target"
		echo "Current:"
		jq '.agent.build' "$target"
		printf "Overwrite? (yes/no): "
		read -r confirm
		[[ "$confirm" != "yes" ]] && {
			echo "Aborted. File unchanged."
			return 1
		}
	fi

	# Case 4: merge — preserve all other keys, only update agent.build
	local tmp
	tmp=$(mktemp)
	jq --arg m "$model" \
		--arg p "{file:./AGENTS.md}" \
		'.agent = (.agent // {}) | .agent.build = {mode: "primary", model: $m, prompt: $p}' \
		"$target" >"$tmp" && mv "$tmp" "$target"
	return 0
}
