#!/usr/bin/env bash
# agents_md.sh — AGENTS.md manipulation helpers
# Source this file

MARKER_START="<!-- BRIDGE_PEERS_START -->"
MARKER_END="<!-- BRIDGE_PEERS_END -->"

# inject_peers_marker {agents_md_path}
# Appends BRIDGE_PEERS marker section if not present.
# Section content: Memory MCP reference guidance (not hardcoded agent list).
inject_peers_marker() {
	local agents_md="$1"
	[[ -z "$agents_md" ]] && {
		echo "ERROR: agents_md path required" >&2
		return 1
	}

	if [[ ! -f "$agents_md" ]]; then
		echo "ERROR: $agents_md not found" >&2
		return 1
	fi

	if grep -qF "$MARKER_START" "$agents_md"; then
		return 0
	fi

	cat >>"$agents_md" <<EOF


${MARKER_START}
## Agent Collaboration

이 에이전트는 Slack 봇으로 연결되어 있으며 다른 에이전트와 협업할 수 있습니다.

**협업 가능한 에이전트 확인**: Memory MCP에서 \`Agent:\` 엔티티를 검색하세요.
**협업 방법**: Slack에서 해당 에이전트를 @멘션하여 요청합니다.
**원칙**:
- 요청 시 결과 형식과 마감 명시
- 완료 후 요청자에게 통보
- 불필요한 반복 대화 금지
${MARKER_END}
EOF
}
