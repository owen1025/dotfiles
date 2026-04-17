#!/bin/bash
# rollback.sh — Rollback stack (push/execute/commit)

ROLLBACK_STACK="/tmp/opencode-bridge-rollback-$$.stack"

# Register a rollback action
# Usage: rollback_register {action} {arg1} [{arg2}...]
rollback_register() {
	local action="$1"
	shift

	[[ -z "$action" ]] && {
		echo "ERROR: rollback_register requires action" >&2
		return 1
	}

	# Join args with pipe separator
	local args=$(
		IFS='|'
		echo "$*"
	)
	echo "${action}|${args}" >>"$ROLLBACK_STACK"
}

# Execute rollback stack in reverse order
rollback_execute() {
	[[ ! -f "$ROLLBACK_STACK" ]] && return 0

	local temp_reversed="/tmp/rollback-reversed-$$.tmp"
	awk '{ a[NR]=$0 } END { for(i=NR; i>=1; i--) print a[i] }' "$ROLLBACK_STACK" >"$temp_reversed"

	while IFS= read -r line; do
		[[ -z "$line" ]] && continue

		local action=$(echo "$line" | cut -d'|' -f1)
		local rest=$(echo "$line" | cut -d'|' -f2-)

		case "$action" in
		rm_file)
			local filepath=$(echo "$rest" | cut -d'|' -f1)
			/bin/rm -f "$filepath" || echo "WARN: Failed to remove file: $filepath" >&2
			;;
		rm_dir)
			local filepath=$(echo "$rest" | cut -d'|' -f1)
			if echo "$filepath" | grep -qE '(bridge|daemons)$'; then
				/bin/rm -rf "$filepath" || echo "WARN: Failed to remove dir: $filepath" >&2
			else
				echo "WARN: Skipping rm_dir for non-whitelisted path: $filepath" >&2
			fi
			;;
		unset_env)
			local var_name=$(echo "$rest" | cut -d'|' -f1)
			if [[ -f "${BASH_SOURCE%/*}/env_manager.sh" ]]; then
				source "${BASH_SOURCE%/*}/env_manager.sh"
				zshrc_local_unset "$var_name" || echo "WARN: Failed to unset env var: $var_name" >&2
			fi
			;;
		delete_env_file)
			local agent=$(echo "$rest" | cut -d'|' -f1)
			if [[ -f "${BASH_SOURCE%/*}/env_manager.sh" ]]; then
				source "${BASH_SOURCE%/*}/env_manager.sh"
				agent_env_delete "$agent" || echo "WARN: Failed to delete env file: $agent" >&2
			fi
			;;
		unload_daemon)
			local label=$(echo "$rest" | cut -d'|' -f1)
			local plist_filepath=$(echo "$rest" | cut -d'|' -f2)
			launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
			/bin/rm -f "$plist_filepath" || echo "WARN: Failed to remove plist: $plist_filepath" >&2
			;;
		delete_registry)
			local name=$(echo "$rest" | cut -d'|' -f1)
			if [[ -f "${BASH_SOURCE%/*}/registry.sh" ]]; then
				source "${BASH_SOURCE%/*}/registry.sh"
				registry_delete "$name" || echo "WARN: Failed to delete registry entry: $name" >&2
			fi
			;;
		rm_symlink)
			local filepath=$(echo "$rest" | cut -d'|' -f1)
			/bin/rm -f "$filepath" || echo "WARN: Failed to remove symlink: $filepath" >&2
			;;
		*)
			echo "WARN: Unknown rollback action: $action" >&2
			;;
		esac
	done <"$temp_reversed"

	/bin/rm -f "$temp_reversed"
}

# Commit rollback (remove stack file)
rollback_commit() {
	/bin/rm -f "$ROLLBACK_STACK"
}

# Clear rollback stack (alias for commit)
rollback_clear() {
	rollback_commit
}
