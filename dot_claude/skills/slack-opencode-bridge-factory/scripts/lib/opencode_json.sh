#!/usr/bin/env bash
# opencode_json.sh — merge logic for opencode.json
# Source this file; do NOT execute directly

# merge_opencode_config {target_path} {model} {agent_name} {python_bin} {project_dir} {home_dir}
# Returns 0 on success, 1 on conflict-aborted or invalid JSON
merge_opencode_config() {
	local target="$1"
	local model="$2"
	local agent_name="$3"
	local python_bin="$4"
	local project_dir="$5"
	local home_dir="${6:-$HOME}"

	[[ -z "$target" ]] && {
		echo "ERROR: target path required" >&2
		return 1
	}
	[[ -z "$model" ]] && {
		echo "ERROR: model required" >&2
		return 1
	}
	[[ -z "$agent_name" ]] && {
		echo "ERROR: agent_name required" >&2
		return 1
	}
	[[ -z "$python_bin" ]] && {
		echo "ERROR: python_bin required" >&2
		return 1
	}
	[[ -z "$project_dir" ]] && {
		echo "ERROR: project_dir required" >&2
		return 1
	}

	# Scheduler MCP block (jq arg-injected below)
	local scheduler_mcp
	scheduler_mcp=$(jq -n \
		--arg py "$python_bin" \
		--arg script "$project_dir/bridge/scheduler_mcp.py" \
		--arg agent "$agent_name" \
		--arg bridge_cfg "$home_dir/.config/opencode-bridges" \
		'{
			type: "local",
			command: [$py, $script],
			enabled: true,
			environment: {
				AGENT_NAME: $agent,
				SCHEDULE_TIMEZONE: "Asia/Seoul",
				BRIDGE_CONFIG_DIR: $bridge_cfg
			}
		}')

	# Case 1: file doesn't exist — write fresh
	if [[ ! -f "$target" ]]; then
		jq -n \
			--arg schema "https://opencode.ai/config.json" \
			--arg model "$model" \
			--arg prompt "{file:./AGENTS.md}" \
			--argjson scheduler "$scheduler_mcp" \
			'{
				"$schema": $schema,
				model: $model,
				agent: {
					build: {mode: "primary", model: $model, prompt: $prompt}
				},
				mcp: {scheduler: $scheduler}
			}' >"$target"
		return 0
	fi

	# Case 2: invalid JSON (JSONC with comments/trailing commas, or malformed)
	if ! jq '.' "$target" >/dev/null 2>&1; then
		echo "ERROR: $target is not valid JSON (JSONC comments/trailing commas not supported)" >&2
		echo "Manual merge required. Add this to agent.build and mcp.scheduler:" >&2
		echo '  "agent": { "build": { "mode": "primary", "model": "'"$model"'", "prompt": "{file:./AGENTS.md}" } }' >&2
		echo '  "mcp": { "scheduler": '"$scheduler_mcp"' }' >&2
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

	# Case 4: merge — preserve all other keys, set agent.build + mcp.scheduler
	local tmp
	tmp=$(mktemp)
	jq --arg m "$model" \
		--arg p "{file:./AGENTS.md}" \
		--argjson scheduler "$scheduler_mcp" \
		'
		.agent = (.agent // {})
		| .agent.build = {mode: "primary", model: $m, prompt: $p}
		| .mcp = (.mcp // {})
		| .mcp.scheduler = $scheduler
		' \
		"$target" >"$tmp" && mv "$tmp" "$target"
	return 0
}
