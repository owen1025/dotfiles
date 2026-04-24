#!/usr/bin/env bash
# daemon_macos.sh — launchd daemon management (macOS)
# Source this file; do NOT execute directly.
# IMPORTANT: Never use "local path=" (zsh PATH conflict). Use "local filepath=" or "local lpath=".

# _pid_for_label {label} → prints PID if running, empty otherwise
# Parses `launchctl list <label>` output like:
#     "PID" = 12345;
_pid_for_label() {
	local label="$1"
	local result pid
	result=$(launchctl list "$label" 2>/dev/null) || return 0
	[[ -z "$result" ]] && return 0
	pid=$(echo "$result" | awk -F'= *' '/"PID"/ {gsub(";","",$2); gsub(" ","",$2); print $2; exit}')
	[[ -n "$pid" && "$pid" != "0" ]] && echo "$pid"
}

# _pid_on_port {port} → prints first PID bound to TCP port, empty otherwise
_pid_on_port() {
	local port="$1"
	[[ -z "$port" ]] && return 0
	lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -1
}

# _wait_gone {check-fn} {arg} {timeout-seconds}
# Polls every 200ms until check-fn prints nothing, or timeout expires.
# Returns 0 if gone, 1 if still present at timeout.
_wait_gone() {
	local fn="$1" arg="$2" timeout="$3"
	local max_iters=$((timeout * 5))
	local i
	for ((i = 0; i < max_iters; i++)); do
		[[ -z "$("$fn" "$arg")" ]] && return 0
		sleep 0.2
	done
	return 1
}

# install_daemon {label} {plist_src_path} {symlink_target_path}
# Copies plist to symlink_target_path, then bootstraps
install_daemon() {
	local label="$1"
	local plist_src="$2"
	local plist_link="$3"

	mkdir -p "$(dirname "$plist_link")"
	cp "$plist_src" "$plist_link"
	launchctl bootstrap "gui/$(id -u)" "$plist_link" 2>/dev/null || {
		launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
		launchctl bootstrap "gui/$(id -u)" "$plist_link"
	}
}

# uninstall_daemon {label} {plist_link_path}
uninstall_daemon() {
	local label="$1"
	local plist_link="$2"
	launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
	/bin/rm -f "$plist_link"
}

# start_daemon {label}
start_daemon() {
	local label="$1"
	launchctl kickstart "gui/$(id -u)/$label" 2>/dev/null || true
}

# stop_daemon {label}
stop_daemon() {
	local label="$1"
	launchctl kill TERM "gui/$(id -u)/$label" 2>/dev/null || true
}

# restart_daemon {label} [port]
# Hardened restart that *verifies* the old process actually died and a new one
# took its place. Without this, a stuck opencode child keeps holding the port
# while launchctl reports success, causing config changes to be silently
# ignored. See AGENTS.md / bug history for details.
#
# Phases:
#   1. Snapshot old PID (from launchctl, plus port holder if port supplied)
#   2. Graceful bootout → poll for exit up to 10s
#   3. If still alive: escalate via `launchctl kill KILL` → poll 5s
#   4. If still alive: `kill -9` the snapshotted PIDs as last resort
#   5. If port supplied: ensure port is free before re-bootstrap (kill holder if needed)
#   6. Bootstrap plist (or kickstart fallback); trust launchctl exit code
#   7. Poll for a *new* PID (distinct from old) up to 5s; fail loudly if not
#
# Returns 0 on verified replacement, non-zero with error on stderr otherwise.
restart_daemon() {
	local label="$1"
	local port="${2:-}"
	local plist="$HOME/Library/LaunchAgents/${label}.plist"
	local uid
	uid=$(id -u)

	local old_pid old_port_pid=""
	old_pid=$(_pid_for_label "$label")
	[[ -n "$port" ]] && old_port_pid=$(_pid_on_port "$port")

	# Phase 1: graceful bootout. Ignore bootout exit code here because launchd
	# returns non-zero when the label is already gone (EINVAL / "no such
	# service"), which is fine for us. We verify with _wait_gone instead.
	launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true

	if ! _wait_gone _pid_for_label "$label" 10; then
		echo "WARN: $label did not exit after bootout, escalating to SIGKILL" >&2
		launchctl kill KILL "gui/$uid/$label" >/dev/null 2>&1 || true

		if ! _wait_gone _pid_for_label "$label" 5; then
			# Last resort: kill snapshotted PIDs directly.
			local stubborn_pid
			stubborn_pid=$(_pid_for_label "$label")
			[[ -n "$stubborn_pid" ]] && kill -9 "$stubborn_pid" 2>/dev/null || true
			[[ -n "$old_pid" && "$old_pid" != "$stubborn_pid" ]] && kill -9 "$old_pid" 2>/dev/null || true
			sleep 1
			if [[ -n "$(_pid_for_label "$label")" ]]; then
				echo "ERROR: $label still running after all kill attempts" >&2
				return 1
			fi
		fi
	fi

	# Phase 2: ensure port is free before bootstrap (only if port supplied).
	# opencode children can outlive the parent label briefly — verify the
	# listener socket is actually released so the new instance doesn't
	# EADDRINUSE.
	if [[ -n "$port" ]]; then
		if ! _wait_gone _pid_on_port "$port" 5; then
			local port_holder
			port_holder=$(_pid_on_port "$port")
			if [[ -n "$port_holder" ]]; then
				echo "WARN: port $port still held by PID $port_holder after kill, force-killing" >&2
				kill -9 "$port_holder" 2>/dev/null || true
				sleep 1
				if [[ -n "$(_pid_on_port "$port")" ]]; then
					echo "ERROR: could not free port $port (still held by PID $(_pid_on_port "$port"))" >&2
					return 1
				fi
			fi
		fi
	fi

	# Phase 3: bootstrap. Trust launchctl's exit code. bootstrap prints a
	# diagnostic and returns non-zero on real failure; return 0 on success.
	# We accept "already loaded" (EEXIST) as success — shouldn't happen after
	# a verified bootout, but tolerate the race.
	if [[ -f "$plist" ]]; then
		local bootstrap_err
		bootstrap_err=$(launchctl bootstrap "gui/$uid" "$plist" 2>&1)
		local bootstrap_rc=$?
		if ((bootstrap_rc != 0)); then
			# Exit 37 or message containing "already loaded" is tolerable.
			if [[ "$bootstrap_err" == *"already loaded"* || "$bootstrap_err" == *"service already bootstrapped"* ]]; then
				: # tolerated
			else
				echo "ERROR: bootstrap failed for $label (rc=$bootstrap_rc): $bootstrap_err" >&2
				return 1
			fi
		fi
	else
		if ! launchctl kickstart -k "gui/$uid/$label" >/dev/null 2>&1; then
			echo "ERROR: kickstart failed for $label" >&2
			return 1
		fi
	fi

	# Phase 4: kickstart the bootstrapped service. On macOS, bootstrap may load
	# the job without immediately spawning it even when RunAtLoad is present;
	# kickstart turns the load into an explicit demand start before PID polling.
	if ! launchctl kickstart -k "gui/$uid/$label" >/dev/null 2>&1; then
		echo "ERROR: kickstart failed for $label after bootstrap" >&2
		return 1
	fi

	# Phase 5: verify a distinct new PID is alive.
	local tries=0 new_pid=""
	while ((tries < 25)); do
		new_pid=$(_pid_for_label "$label")
		[[ -n "$new_pid" && "$new_pid" != "$old_pid" ]] && break
		sleep 0.2
		((tries++))
	done
	if [[ -z "$new_pid" ]]; then
		echo "ERROR: $label did not start (no PID after 5s)" >&2
		return 1
	fi
	if [[ -n "$old_pid" && "$new_pid" == "$old_pid" ]]; then
		echo "ERROR: $label did not replace old PID ($old_pid still running)" >&2
		return 1
	fi

	# Phase 6: if port supplied, verify the new PID (or one of its children)
	# actually binds the port within 10s. This catches the case where launchd
	# respawned but opencode itself crash-looped without ever binding.
	if [[ -n "$port" ]]; then
		tries=0
		local port_pid=""
		while ((tries < 50)); do
			port_pid=$(_pid_on_port "$port")
			if [[ -n "$port_pid" && "$port_pid" != "$old_port_pid" ]]; then
				return 0
			fi
			sleep 0.2
			((tries++))
		done
		echo "WARN: $label started (PID $new_pid) but port $port not bound within 10s" >&2
		# Not a hard failure — caller's health check will decide.
	fi

	return 0
}

# status_daemon {label} [port] → prints "running", "stopped", "stuck", or "unknown"
# When [port] is provided, cross-checks launchctl state against lsof. If
# launchctl reports no PID but the port is still held, reports "stuck" so
# callers (and users) see the real situation instead of a false "stopped".
status_daemon() {
	local label="$1"
	local port="${2:-}"
	local pid
	pid=$(_pid_for_label "$label")

	if [[ -n "$pid" ]]; then
		echo "running"
		return
	fi

	# No launchctl PID. If a port was supplied and something still holds it,
	# that's a stuck state (orphan child, or unrelated process squatting).
	if [[ -n "$port" ]]; then
		local port_pid
		port_pid=$(_pid_on_port "$port")
		if [[ -n "$port_pid" ]]; then
			echo "stuck"
			return
		fi
	fi

	echo "stopped"
}
