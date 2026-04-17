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
