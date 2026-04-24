#!/bin/bash
# env_manager.sh — Safe ~/.zshrc.local editing + per-agent .env files

ZSHRC_LOCAL="${HOME}/.zshrc.local"
ZSHRC_LOCK_DIR="${HOME}/.config/opencode-bridges/.env.lock"
AGENT_ENV_DIR="${HOME}/.config/opencode-bridges"

# Advisory lock for ~/.zshrc.local editing
acquire_env_lock() {
	mkdir "$ZSHRC_LOCK_DIR" 2>/dev/null || {
		echo "ERROR: env lock held" >&2
		return 1
	}
	trap 'rmdir "$ZSHRC_LOCK_DIR" 2>/dev/null' EXIT INT TERM
}

release_env_lock() {
	rmdir "$ZSHRC_LOCK_DIR" 2>/dev/null || true
}

# Set variable in ~/.zshrc.local (create if missing)
zshrc_local_set() {
	local var_name="$1"
	local value="$2"

	[[ -z "$var_name" || -z "$value" ]] && {
		echo "ERROR: zshrc_local_set requires VAR_NAME and value" >&2
		return 1
	}

	acquire_env_lock || return 1

	# Create file if missing
	touch "$ZSHRC_LOCAL"

	# Use temp file for atomicity
	local temp_file="${ZSHRC_LOCAL}.tmp.$$"

	# Check if var already exists and replace, else append
	if grep -q "^export ${var_name}=" "$ZSHRC_LOCAL"; then
		sed "s/^export ${var_name}=.*/export ${var_name}=\"${value}\"/" "$ZSHRC_LOCAL" >"$temp_file"
	else
		cat "$ZSHRC_LOCAL" >"$temp_file"
		echo "export ${var_name}=\"${value}\"" >>"$temp_file"
	fi

	mv "$temp_file" "$ZSHRC_LOCAL"
	release_env_lock
}

# Remove variable from ~/.zshrc.local
zshrc_local_unset() {
	local var_name="$1"

	[[ -z "$var_name" ]] && {
		echo "ERROR: zshrc_local_unset requires VAR_NAME" >&2
		return 1
	}
	[[ ! -f "$ZSHRC_LOCAL" ]] && return 0

	acquire_env_lock || return 1

	local temp_file="${ZSHRC_LOCAL}.tmp.$$"
	grep -v "^export ${var_name}=" "$ZSHRC_LOCAL" >"$temp_file"
	mv "$temp_file" "$ZSHRC_LOCAL"

	release_env_lock
}

# Check if variable exists in ~/.zshrc.local
zshrc_local_has() {
	local var_name="$1"

	[[ -z "$var_name" ]] && {
		echo "ERROR: zshrc_local_has requires VAR_NAME" >&2
		return 1
	}
	[[ ! -f "$ZSHRC_LOCAL" ]] && return 1

	grep -q "^export ${var_name}=" "$ZSHRC_LOCAL"
}

# Write agent-specific .env file
# Usage: agent_env_write {agent} {key1} {val1} [{key2} {val2} ...]
agent_env_write() {
	local agent="$1"
	shift

	[[ -z "$agent" ]] && {
		echo "ERROR: agent_env_write requires agent name" >&2
		return 1
	}
	[[ $# -lt 2 || $((($# % 2))) -ne 0 ]] && {
		echo "ERROR: agent_env_write requires key-value pairs" >&2
		return 1
	}

	mkdir -p "$AGENT_ENV_DIR"

	local env_file="${AGENT_ENV_DIR}/${agent}.env"
	>"$env_file" # Truncate file

	while [[ $# -ge 2 ]]; do
		local key="$1"
		local val="$2"
		echo "export ${key}=${val}" >>"$env_file"
		shift 2
	done

	chmod 600 "$env_file"
}

# Upsert a single key in agent env file (preserves other keys)
# Usage: agent_env_set {agent} {key} {value}
agent_env_set() {
	local agent="$1"
	local key="$2"
	local val="$3"

	[[ -z "$agent" || -z "$key" ]] && {
		echo "ERROR: agent_env_set requires agent and key" >&2
		return 1
	}

	local env_file="${AGENT_ENV_DIR}/${agent}.env"
	[[ ! -f "$env_file" ]] && {
		echo "ERROR: env file not found: $env_file" >&2
		return 1
	}

	if grep -q "^export ${key}=" "$env_file"; then
		local tmp
		tmp=$(mktemp)
		awk -v k="$key" -v v="$val" '
			$0 ~ "^export " k "=" { print "export " k "=\"" v "\""; next }
			{ print }
		' "$env_file" >"$tmp" && mv "$tmp" "$env_file"
	else
		echo "export ${key}=\"${val}\"" >>"$env_file"
	fi
	chmod 600 "$env_file"
}

# Delete agent-specific .env file
agent_env_delete() {
	local agent="$1"

	[[ -z "$agent" ]] && {
		echo "ERROR: agent_env_delete requires agent name" >&2
		return 1
	}

	local env_file="${AGENT_ENV_DIR}/${agent}.env"
	rm -f "$env_file"
}
