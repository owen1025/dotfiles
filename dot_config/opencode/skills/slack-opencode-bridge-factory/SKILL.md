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
3. `slack-bot-factory` skill installed (`~/.config/opencode/skills/slack-bot-factory/`)
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

> **중요**: `omo-bridge`는 이 문서에서 사용하는 **별칭**일 뿐, 실제 CLI가 아닙니다.
> 실제 실행은 항상 다음 경로로:
> ```
> bash ~/.config/opencode/skills/slack-opencode-bridge-factory/scripts/main.sh <subcommand> [options]
> ```
> 예: `omo-bridge restart secretary` → `bash ~/.config/opencode/skills/slack-opencode-bridge-factory/scripts/main.sh restart secretary`

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
  [--port <number>] \
  [--icon <image-path>]    # bot profile image (png/jpg/gif)
```

### delete
```bash
omo-bridge delete <agent-name> [--force] [--purge-project] [--purge-logs]
```
Removes daemons, env vars, registry entry. Preserves Slack App and project by default.

## File Structure

```
~/.config/opencode/skills/slack-opencode-bridge-factory/    ← chezmoi managed

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

## Scheduled Tasks

Each agent can register recurring/one-shot prompts via the built-in `scheduler` MCP:

- User says "매일 오후 5시 캘린더 정리해줘" in Slack
- Agent parses the natural-language request, asks where to deliver results (DM vs channel)
- Agent calls `schedule_register` MCP tool → stored in `~/.config/opencode-bridges/<agent>-schedules.db`
- Bridge polls DB every 30s; APScheduler (tz=Asia/Seoul) fires the job at the right time
- On fire: bridge creates a fresh OpenCode session, sends the stored prompt, posts the response to the chosen Slack target

**MCP tools available to the agent:**
- `schedule_register` — create recurring (cron) / interval / one-shot (date) schedule
- `schedule_list` — list all schedules for this agent
- `schedule_delete` — permanently remove
- `schedule_pause` / `schedule_resume` — disable/re-enable

**Persistence**: SQLite with WAL mode, per-agent isolation. Survives bridge restarts. MCP server (in OpenCode process) writes, bridge process reads — no lock contention.

**Timezone**: Fixed Asia/Seoul by default. Override with `SCHEDULE_TIMEZONE` env var on the bridge daemon.

**Bootstrap requirement for existing agents**: Bots created before scheduler support need `update <agent> --resync-bridge` (or manual: reinstall deps + add `mcp.scheduler` block to `opencode.json`). New `create` invocations include the scheduler automatically.

## Limitations (V1)
- macOS only (launchd). Linux/systemd: V2
- Single workspace per invocation (default: noanswer)
- Browser steps required for token acquisition (Slack API limitation)
- Remote (SSH) installation: V2
- Scheduler latency up to 30s (DB polling interval). Minute-granularity triggers are reliable; second-granularity is not.

**Profile image**:
- Requires `users:write` scope (added by default in v4+)
- Existing bots created before v4 must reinstall app to grant new scope

**Progress indicator**:
- Uses `reactions:write` scope — bot adds ⏳ reaction on trigger message while processing, removes when done
- Bots created before this feature must reinstall app to grant `reactions:write`
- Chosen over text "처리 중..." message to avoid cross-bot confusion in multi-agent threads

## Dependencies
- `slack-bot-factory` skill (`~/.config/opencode/skills/slack-bot-factory/`)
- `jq` (JSON processing)
- `opencode` 1.4+
- `python3` 3.10+ (for bridge venv)
