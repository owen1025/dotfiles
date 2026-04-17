---
name: slack-opencode-bridge-factory
description: Create, manage, and delete Slack bot bridges for OpenCode agents. Automates Slack App creation (Phase 1), project scaffolding, launchd daemon setup, and registry management. macOS V1.
triggers:
  - opencode 에이전트 슬랙 봇 만들어줘
  - slack bridge 생성
  - omo-bridge create
  - 봇 브릿지 추가
  - 새 에이전트 브릿지
  - opencode slack bridge
  - 슬랙 브릿지 팩토리
  - bridge factory
  - create slack bot
argument-hint: "<agent-name>"
---

# Slack OpenCode Bridge Factory

End-to-end automation for connecting OpenCode agents to Slack. Each agent gets its own Slack App (Socket Mode) and launchd daemons for auto-restart.

## When to Activate

Activate when the user asks to:
- Create a new Slack bot bridge for an OpenCode agent
- Set up automatic agent → Slack thread responses
- Manage existing agent bridges (list, restart, update, delete)

Do NOT activate for:
- Modifying existing bot scopes → use `slack-bot-permissions` instead
- Direct Slack messaging without OpenCode → use Slack MCP directly

## Prerequisites

1. `jq` installed (`which jq`)
2. `opencode` installed and configured
3. `slack-bot-factory` skill installed (`~/.claude/skills/omc-learned/slack-bot-factory/`)
4. Slack workspace bootstrapped in slack-bot-factory

## Create Flow (2 Phases)

```
Phase 1 (automated):
  omo-bridge create --name <agent> --project <path> --role "<description>"
  → Slack App manifest created
  → Project scaffolded (AGENTS.md, opencode.json, bridge/, venv)
  → Env file + wrapper scripts generated
  → Registry updated (status: pending-tokens)

[BROWSER - 2 manual steps]:
  1. Generate App-Level Token (xapp-...) at api.slack.com
  2. Install to workspace → copy Bot Token (xoxb-...)

Phase 2 (automated):
  omo-bridge finalize <agent> --bot-token xoxb-... --app-token xapp-...
  → Tokens registered to ~/.zshrc.local
  → launchd daemons installed + started
  → Health checks (opencode serve + bridge)
  → Registry updated (status: running)
  → Knowledge Graph credential saved
```

## Commands

### create
```bash
omo-bridge create --name <agent-name> \
  [--project <absolute-path>] \    # required (or interactive prompt)
  [--role "<one-line description>"] \
  [--role-file <path>] \           # pre-written AGENTS.md
  [--model <anthropic/model-id>] \ # default: anthropic/claude-sonnet-4-5
  [--workspace <slug>]             # default: noanswer
```
Starts Phase 1. Ends with browser instructions.

### finalize
```bash
omo-bridge finalize <agent-name> \
  --bot-token xoxb-... \
  --app-token xapp-...
```
Completes Phase 2. Starts daemons and validates health.

### list
```bash
omo-bridge list [--json] [--name <agent>]
```
Shows all registered agents with live running/stopped status.

### restart
```bash
omo-bridge restart <agent-name> [--only opencode|bridge]
```
Restarts daemons. `--only` limits to one service.

### logs
```bash
omo-bridge logs <agent-name> [--tail N] [--follow] [--only opencode|bridge]
```
Tails log files from `~/.local/log/opencode-bridges/<agent>/`.

### update
```bash
omo-bridge update <agent-name> \
  [--model <model-id>] \
  [--role-file <path>] \
  [--rotate-tokens] \      # rotates workspace config token only
  [--port <number>]
```

### delete
```bash
omo-bridge delete <agent-name> [--force] [--purge-project] [--purge-logs]
```
Removes daemons, env vars, registry entry. Preserves Slack App and project by default.

## File Structure

```
~/.claude/skills/slack-opencode-bridge-factory/    ← chezmoi managed
~/.config/opencode/skills/slack-opencode-bridge-factory  ← OMO symlink

~/.config/opencode-bridges/
  registry.json           ← single source of truth for all agents
  {agent}.env             ← per-agent env vars

~/.local/log/opencode-bridges/{agent}/
  opencode.log
  bridge.log

~/.local/bin/
  {agent}-opencode-serve.sh
  {agent}-bridge.sh
```

## Limitations (V1)
- macOS only (launchd). Linux/systemd: V2
- Single workspace per invocation (default: noanswer)
- Browser steps required for token acquisition (Slack API limitation)
- Remote (SSH) installation: V2

## Dependencies
- `slack-bot-factory` skill (`~/.claude/skills/omc-learned/slack-bot-factory/`)
- `jq` (JSON processing)
- `opencode` 1.4+
- `python3` 3.10+ (for bridge venv)
