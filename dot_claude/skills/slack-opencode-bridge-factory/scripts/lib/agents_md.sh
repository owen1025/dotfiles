#!/usr/bin/env bash
# agents_md.sh — AGENTS.md manipulation helpers
# Source this file

MARKER_START="<!-- BRIDGE_PEERS_START -->"
MARKER_END="<!-- BRIDGE_PEERS_END -->"

INFO_START="<!-- BRIDGE_INFO_START -->"
INFO_END="<!-- BRIDGE_INFO_END -->"

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

# inject_bridge_info {agents_md_path} {agent_name} {port} {opencode_label} {bridge_label} {log_dir}
# BRIDGE_INFO section is replaced on every call (values may change via update/migrate).
inject_bridge_info() {
	local agents_md="$1"
	local agent_name="$2"
	local port="$3"
	local oc_label="$4"
	local br_label="$5"
	local log_dir="$6"

	[[ -z "$agents_md" || -z "$agent_name" ]] && {
		echo "ERROR: agents_md and agent_name required" >&2
		return 1
	}
	[[ ! -f "$agents_md" ]] && {
		echo "ERROR: $agents_md not found" >&2
		return 1
	}

	local new_section
	new_section=$(
		cat <<EOF
${INFO_START}
## Slack Bridge

이 프로젝트는 \`slack-opencode-bridge-factory\` 스킬로 생성된 Slack 봇 브릿지가 연결되어 있습니다.

**Bridge 정보**:
- 에이전트 이름: \`${agent_name}\`
- OpenCode 포트: \`${port}\`
- 데몬 label: \`${oc_label}\`, \`${br_label}\`
- 로그 경로: \`${log_dir}/\`

**관리 명령 호출 방법**:

\`omo-bridge\`는 문서용 별칭입니다. 실제 실행은 main.sh를 직접 호출하세요:

\`\`\`
bash ~/.claude/skills/slack-opencode-bridge-factory/scripts/main.sh <subcommand> [options]
\`\`\`

자주 쓰는 커맨드 (이 에이전트 기준):
- 상태 확인: \`bash ~/.claude/skills/slack-opencode-bridge-factory/scripts/main.sh list --name ${agent_name}\`
- 재시작: \`bash ~/.claude/skills/slack-opencode-bridge-factory/scripts/main.sh restart ${agent_name}\`
- 로그 확인: \`bash ~/.claude/skills/slack-opencode-bridge-factory/scripts/main.sh logs ${agent_name} --tail 30\`
- 모델/프롬프트 업데이트: \`bash ~/.claude/skills/slack-opencode-bridge-factory/scripts/main.sh update ${agent_name} --model ... --role-file ...\`
- 아이콘 변경: \`bash ~/.claude/skills/slack-opencode-bridge-factory/scripts/main.sh update ${agent_name} --icon <path>\`

**프로젝트별 커스터마이징**:
- \`opencode.json\` — 모델, 도구 권한, MCP 등 에이전트 런타임 설정
- \`AGENTS.md\` — 에이전트 역할, 운영 원칙 (이 파일). 위 마커 섹션 외부는 자유롭게 작성
- \`bridge/bridge.py\` — Slack ↔ OpenCode 브릿지 로직 (스킬 템플릿에서 파생). 커스터마이징 시 main.sh의 \`update --sync-bridge\`로 덮어쓰이지 않도록 주의
${INFO_END}
EOF
	)

	if grep -qF "$INFO_START" "$agents_md"; then
		local tmp new_file
		tmp=$(mktemp)
		new_file=$(mktemp)
		printf '%s\n' "$new_section" >"$new_file"
		awk -v start="$INFO_START" -v end="$INFO_END" -v new_file="$new_file" '
			BEGIN { skip=0 }
			index($0, start) && !skip {
				while ((getline line < new_file) > 0) print line
				close(new_file)
				skip=1
				next
			}
			skip && index($0, end) { skip=0; next }
			!skip { print }
		' "$agents_md" >"$tmp" && mv "$tmp" "$agents_md"
		/bin/rm -f "$new_file"
		return 0
	fi

	printf '\n\n%s\n' "$new_section" >>"$agents_md"
}
