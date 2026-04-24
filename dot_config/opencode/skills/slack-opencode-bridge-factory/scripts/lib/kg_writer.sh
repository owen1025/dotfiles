#!/bin/bash
# kg_writer.sh — Output Knowledge Graph entity JSON (caller does MCP call)

# Generate JSON for creating a Slack bot entity in Knowledge Graph
# Usage: kg_bot_entity_json {agent} {workspace} {app_id} {bot_user_id} {bot_token_env} {app_token_env}
kg_bot_entity_json() {
	local agent="$1"
	local workspace="$2"
	local app_id="$3"
	local bot_user_id="$4"
	local bot_token_env="$5"
	local app_token_env="$6"

	[[ -z "$agent" || -z "$workspace" || -z "$app_id" || -z "$bot_user_id" || -z "$bot_token_env" || -z "$app_token_env" ]] && {
		echo "ERROR: kg_bot_entity_json requires all 6 arguments" >&2
		return 1
	}

	local created_date=$(date -u +%Y-%m-%d)

	cat <<EOF
{
  "entities": [{
    "name": "1P:Slack-${agent}-Bot",
    "entityType": "credential",
    "observations": [
      "Slack Bot for ${agent} OpenCode bridge",
      "Bot Token env var: ${bot_token_env}",
      "App Token env var: ${app_token_env}",
      "App ID: ${app_id}",
      "Bot User ID: ${bot_user_id}",
      "Workspace: ${workspace}",
      "Created: ${created_date}"
    ]
  }]
}
EOF
}

# Generate JSON for deleting a Slack bot entity from Knowledge Graph
# Usage: kg_bot_delete_json {agent}
kg_bot_delete_json() {
	local agent="$1"

	[[ -z "$agent" ]] && {
		echo "ERROR: kg_bot_delete_json requires agent name" >&2
		return 1
	}

	cat <<EOF
{
  "entityNames": ["1P:Slack-${agent}-Bot"]
}
EOF
}

# Generate JSON for creating an Agent entity in Knowledge Graph
# Usage: kg_agent_entity_json {agent} {role} {bot_user_id} {project_dir} {model} {workspace}
kg_agent_entity_json() {
	local agent="$1"
	local role="$2"
	local bot_user_id="$3"
	local project_dir="$4"
	local model="$5"
	local workspace="$6"

	[[ -z "$agent" || -z "$role" || -z "$bot_user_id" || -z "$project_dir" || -z "$model" || -z "$workspace" ]] && {
		echo "ERROR: kg_agent_entity_json requires all 6 arguments" >&2
		return 1
	}

	local capitalized
	capitalized="$(echo "${agent:0:1}" | tr '[:lower:]' '[:upper:]')${agent:1}"
	local mention="@${capitalized}"
	local entity_name="Agent:${capitalized}"

	jq -n \
		--arg name "$entity_name" \
		--arg mention "$mention" \
		--arg buid "$bot_user_id" \
		--arg role "$role" \
		--arg proj "$project_dir" \
		--arg model "$model" \
		--arg ws "$workspace" \
		'{entities: [{
			name: $name,
			entityType: "agent",
			observations: [
				("Slack Bot — " + $mention + "로 멘션하여 소환"),
				("Bot User ID: " + $buid),
				("역할: " + $role),
				("프로젝트: " + $proj),
				("모델: " + $model),
				("워크스페이스: " + $ws)
			]
		}]}'
}

# Generate JSON for deleting an Agent entity from Knowledge Graph
# Usage: kg_agent_delete_json {agent}
kg_agent_delete_json() {
	local agent="$1"

	[[ -z "$agent" ]] && {
		echo "ERROR: kg_agent_delete_json requires agent name" >&2
		return 1
	}

	local capitalized
	capitalized="$(echo "${agent:0:1}" | tr '[:lower:]' '[:upper:]')${agent:1}"
	jq -n --arg name "Agent:${capitalized}" '{entityNames: [$name]}'
}
