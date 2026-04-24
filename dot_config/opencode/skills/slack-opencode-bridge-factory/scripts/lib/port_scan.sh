#!/bin/bash
# port_scan.sh — Find free port in range 4096-4196

die() {
	echo "ERROR: $*" >&2
	exit 1
}

allocate_port() {
	local registry_file="$HOME/.config/opencode-bridges/registry.json"
	local reserved_ports=()

	if [[ -f "$registry_file" ]]; then
		reserved_ports=($(jq -r '.agents[].port' "$registry_file" 2>/dev/null || echo ""))
	fi

	for port in {4096..4196}; do
		local in_registry=0
		for reserved in "${reserved_ports[@]}"; do
			if [[ "$port" == "$reserved" ]]; then
				in_registry=1
				break
			fi
		done

		if [[ $in_registry -eq 1 ]]; then
			continue
		fi

		if ! lsof -i ":$port" -sTCP:LISTEN -t 2>/dev/null | grep -q .; then
			echo "$port"
			return 0
		fi
	done

	die "No free ports available in range 4096-4196"
}
