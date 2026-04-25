---
name: slack-bot-factory
description: Create new Slack bots via Manifest API with automated token management, env var registration, and channel invitation. Handles multi-workspace multi-bot setup.
triggers:
  - slack bot
  - slack 봇
  - 슬랙 봇
  - slack app
  - 슬랙 앱
  - create slack
  - 봇 만들
  - secretary
  - notifier
argument-hint: "<workspace> <bot-name>"
---

# Slack Bot Factory

End-to-end Slack bot creation skill. Automates everything that CAN be automated (Manifest API, env var setup, channel invite) and guides the user through the 3 unavoidable browser steps.

## When to Activate

Activate when the user asks to:
- Create a new Slack bot/app in an existing workspace
- Set up a Slack integration with specific scopes
- Add a bot to a channel with automated token management

Do NOT activate for:
- Modifying existing bot permissions → use `slack-bot-permissions` skill instead
- Debugging a running bot's code → that's separate
- Setting up the central `slack` MCP for opencode itself (uses `@zencoderai/slack-mcp-server` with a single Bot token — see `~/.zshrc.local`)

## Prerequisites

Check these BEFORE starting:
1. `jq` installed (`which jq`)
2. `curl` installed (nearly always yes on macOS)
3. `~/.zshrc.local` exists (user's secret env vars)
4. State directory: `~/.local/state/slack-bot-factory/workspaces/` (script creates if missing)

If missing jq: tell user `brew install jq` and stop.

## Workflow

### Step 0: Identify Workspace

Ask the user which Slack workspace:
- User may say "noanswer" or "noanswer.slack.com" — normalize to lowercase slug (`noanswer`)
- Check `~/.local/state/slack-bot-factory/workspaces/<slug>.json` exists
- If NOT exists → go to "Workspace Bootstrap" below
- If exists → go to Step 1

### Workspace Bootstrap (one-time per workspace)

Tell user exactly this:
```
이 workspace는 처음 사용합니다. 1회 셋업이 필요해요 (5분).

1. https://api.slack.com/apps 접속
2. 우측 상단 프로필 → "Your App Configuration Tokens" 클릭
3. Workspace 드롭다운에서 해당 workspace 선택 → "Generate Token"
4. 두 토큰이 나옵니다. 아래 셸에서 실행:

   ~/.config/opencode/skills/slack-bot-factory/scripts/bootstrap-workspace.sh <slug>

5. 프롬프트에 두 토큰 붙여넣기
```

After user confirms bootstrap complete, verify the state file exists, then proceed to Step 1.

### Step 1: Gather Bot Requirements

Ask in this order:
1. **Bot name** (slug, lowercase, hyphens) — e.g., `secretary`, `notifier-dev`
2. **Display name** (shown in Slack UI) — default to title-cased bot name
3. **Functionality** — show the scope catalog below and let user pick
4. **Socket Mode needed?** — YES if bot responds to events (mentions, messages). NO if it only pushes.
5. **Channel to invite to** — e.g., `#dev`. Can be multiple.

### Step 2: Select Scopes

Show this menu to the user (or infer from their description):

**Common Scope Combinations:**

| Use Case | Bot Scopes | Bot Events (if Socket Mode) |
|---|---|---|
| Mention-based assistant | `app_mentions:read`, `chat:write`, `channels:history`, `channels:read` | `app_mention` |
| Channel monitor (read-only) | `channels:history`, `channels:read`, `chat:write` | `message.channels` |
| DM assistant | `im:history`, `im:read`, `im:write`, `chat:write` | `message.im` |
| Notification pusher (one-way) | `chat:write`, `chat:write.public` | (none, no socket mode) |
| Full-featured bot | All of the above | `app_mention`, `message.channels` |

**If user describes a custom combo**, map their words to scopes:
- "멘션 받기" / "mention" → `app_mentions:read`
- "메시지 보내기" / "write" → `chat:write`
- "메시지 읽기" / "read channel" → `channels:history`
- "채널 목록" → `channels:read`
- "파일 업로드" → `files:write`
- "파일 읽기" → `files:read`
- "DM 주고받기" → `im:history`, `im:read`, `im:write`
- "이모지 반응" → `reactions:read`, `reactions:write`

Confirm the final scope list with the user BEFORE proceeding.

### Step 3: Create the App

Run (absolute path):
```bash
~/.config/opencode/skills/slack-bot-factory/scripts/create-bot.sh \
  <workspace> <bot-name> <display-name> <socket-mode:true|false> \
  <bot-scopes-csv> <bot-events-csv>
```

Example:
```bash
~/.config/opencode/skills/slack-bot-factory/scripts/create-bot.sh \
  noanswer secretary "Secretary" true \
  "app_mentions:read,chat:write,channels:history,channels:read" \
  "app_mention"
```

The script:
- Lazy-rotates config token if > 10h old
- Generates manifest JSON dynamically
- Calls `apps.manifest.create`
- Prints the new `app_id`
- Appends bot entry to workspace state file

If script fails with "invalid_auth" → config token may be expired even after rotation. Tell user to re-run `bootstrap-workspace.sh`.

### Step 4: Guide User Through Browser Steps

After `create-bot.sh` succeeds and prints `APP_ID=A0123ABCDEF`, tell the user:

```
✓ App 생성됨: A0123ABCDEF

브라우저에서 2개 작업 필요 (3분):

[1/2] App-Level Token 발급 (Socket Mode 용)  # Socket Mode=true인 경우만
     → https://api.slack.com/apps/A0123ABCDEF/general
     → 페이지 아래 "App-Level Tokens" 섹션
     → "Generate Token and Scopes"
     → Token Name: 아무거나 (예: default)
     → Scope: connections:write 선택
     → Generate → xapp- 으로 시작하는 토큰 복사

[2/2] Workspace 설치
     → https://api.slack.com/apps/A0123ABCDEF/install-on-team
     → "Allow" 클릭
     → 설치 후 OAuth & Permissions 페이지에서
       "Bot User OAuth Token" (xoxb-...) 복사

준비되면 토큰 값을 알려주세요:
  - xapp-... (Socket Mode=true인 경우만)
  - xoxb-...
```

If Socket Mode=false, skip step [1/2].

### Step 5: Finalize

Once user provides the tokens, run:
```bash
~/.config/opencode/skills/slack-bot-factory/scripts/finalize-bot.sh \
  <workspace> <bot-name> <xapp-token-or-"none"> <xoxb-token> <channel-csv>
```

Example (Socket Mode):
```bash
~/.config/opencode/skills/slack-bot-factory/scripts/finalize-bot.sh \
  noanswer secretary "xapp-1-ABC..." "xoxb-XYZ..." "#dev,#general"
```

Example (no Socket Mode):
```bash
~/.config/opencode/skills/slack-bot-factory/scripts/finalize-bot.sh \
  noanswer notifier none "xoxb-XYZ..." "#alerts"
```

The script:
- Appends env vars to `~/.zshrc.local`:
  - `SLACK_<WS>_<BOT>_APP_TOKEN` (if socket mode)
  - `SLACK_<WS>_<BOT>_BOT_TOKEN`
- Resolves channel names to IDs via `conversations.list`
- Calls `conversations.join` for each channel (works for public channels)
- For private channels: tells user to `/invite @<bot-name>` manually
- Updates state file with token metadata (NOT the token values — those stay only in zshrc.local)

### Step 6: Report & Next Steps

After finalize succeeds, tell the user:
```
✅ 완료

환경변수 (새 shell 열거나 `source ~/.zshrc.local`):
  $SLACK_NOANSWER_SECRETARY_APP_TOKEN
  $SLACK_NOANSWER_SECRETARY_BOT_TOKEN

초대된 채널: #dev, #general

봇 프로세스는 별도 관리:
  - @slack/bolt (Node): https://slack.dev/bolt-js
  - slack-bolt (Python): https://slack.dev/bolt-python

권한 수정이 필요하면 slack-bot-permissions skill 사용
```

## Error Recovery

### `create-bot.sh` returns `invalid_auth`
→ Config token expired AND refresh failed. User must re-bootstrap:
```
bootstrap-workspace.sh <workspace>
```

### `create-bot.sh` returns `invalid_manifest`
→ Slack rejected the manifest. Print the error detail from response. Usually one of:
- Invalid scope name (typo)
- Duplicate app name in workspace
- Missing required field

### `finalize-bot.sh` can't find channel
→ Channel might be private, or bot wasn't installed. Check:
1. Did user complete "Install to Workspace" step?
2. Is the channel name correct (no typo)?
3. For private channels: user must `/invite @<bot>` manually.

### Token rotation failure mid-operation
→ State file might be inconsistent. Run:
```bash
cat ~/.local/state/slack-bot-factory/workspaces/<ws>.json
```
Check if `config_token` and `refresh_token` are valid-looking. If broken, re-bootstrap.

## Key Constraints

- **Never commit tokens to git.** Tokens live ONLY in `~/.zshrc.local` (not chezmoi managed) and state file at `~/.local/state/` (chmod 600).
- **Refresh token rotates every time** `tooling.tokens.rotate` is called. Scripts handle this atomically but if a rotation is interrupted, the old refresh_token may be invalidated.
- **Socket Mode is mandatory** for bots that receive events. WebSocket connection from bot process → Slack. No public HTTP endpoint needed.
- **App-Level Tokens cannot be generated via API.** This is the only truly manual step besides install.

## Environment Variable Naming Convention

`SLACK_{WORKSPACE}_{BOT}_{TYPE}` where:
- WORKSPACE: uppercase workspace slug (e.g., `NOANSWER`, `ACME`)
- BOT: uppercase bot name, underscores replace hyphens (e.g., `SECRETARY`, `NOTIFIER_DEV`)
- TYPE: `APP_TOKEN` (xapp-) or `BOT_TOKEN` (xoxb-)

Examples:
- `SLACK_NOANSWER_SECRETARY_BOT_TOKEN`
- `SLACK_NOANSWER_SECRETARY_APP_TOKEN`
- `SLACK_ACME_NOTIFIER_DEV_BOT_TOKEN`

## State File Schema

`~/.local/state/slack-bot-factory/workspaces/<workspace>.json`:
```json
{
  "workspace": "noanswer",
  "config_token": "xoxe.xoxp-...",
  "refresh_token": "xoxe-...",
  "issued_at": 1713184800,
  "bots": [
    {
      "name": "secretary",
      "app_id": "A0123ABCDEF",
      "created_at": 1713184900,
      "socket_mode": true,
      "scopes": ["app_mentions:read", "chat:write", "channels:history", "channels:read"],
      "channels_joined": ["#dev"]
    }
  ]
}
```
