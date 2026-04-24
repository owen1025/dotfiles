---
name: slack-bot-permissions
description: View and modify permissions (scopes, events) of existing Slack bots created by slack-bot-factory. Handles the required re-install notification.
triggers:
  - slack 권한
  - slack bot permission
  - 봇 권한
  - scope 추가
  - scope 제거
  - update slack bot
  - modify bot
argument-hint: "<workspace> <bot-name> [add|remove|list] [scope]"
---

# Slack Bot Permissions

Modify scopes and events on existing bots created by `slack-bot-factory`. Uses `apps.manifest.update` to patch the manifest, then guides the user through the mandatory re-install.

## When to Activate

Activate when the user asks to:
- Check current scopes of a bot
- Add a new scope to an existing bot
- Remove a scope from an existing bot
- Change event subscriptions

Do NOT activate for:
- Creating a new bot → use `slack-bot-factory` skill
- Changing tokens (rotate xapp/xoxb) → manual UI operation
- Changing bot display name → use `apps.manifest.update` directly (not implemented here)

## Prerequisites

Same as slack-bot-factory:
- `jq`, `curl` installed
- Workspace state at `~/.local/state/slack-bot-factory/workspaces/<ws>.json`
- slack-bot-factory skill deployed (this skill sources its `lib/common.sh`)

## Workflow

### Step 1: Identify Target

Ask (or parse from user input):
- Workspace slug
- Bot name

Verify:
- Workspace state file exists
- Bot entry exists in `state.bots[]`

### Step 2: Choose Operation

**List current scopes**:
```bash
~/.config/opencode/skills/slack-bot-permissions/scripts/list-scopes.sh <workspace> <bot-name>
```

Fetches fresh manifest from Slack (via `apps.manifest.export`) and displays:
- Current bot scopes
- Current bot events
- Socket mode status

**Add/remove scopes**:
```bash
~/.config/opencode/skills/slack-bot-permissions/scripts/update-scopes.sh \
  <workspace> <bot-name> <op> <scopes-csv> [events-csv]
```

Where `<op>` ∈ {`add`, `remove`, `replace`}.

Examples:
```bash
# Add files:read, files:write
update-scopes.sh noanswer secretary add "files:read,files:write"

# Remove channels:history
update-scopes.sh noanswer secretary remove "channels:history"

# Replace entire scope list + events
update-scopes.sh noanswer secretary replace \
  "app_mentions:read,chat:write" "app_mention"
```

### Step 3: Confirm the diff with user

Before running `update-scopes.sh`, show user:
```
Current scopes: [a, b, c]
New scopes:     [a, b, c, d]  (+d)

Proceed? [y/N]
```

### Step 4: Execute + Notify

After `update-scopes.sh` succeeds, tell user:

```
⚠️  Slack requires re-installation for scope changes to take effect.

   → https://api.slack.com/apps/<APP_ID>/install-on-team
   → Click "Re-install to Workspace"
   → Review new permissions → Allow

After re-install, bot token stays the same (no zshrc.local update needed).
```

**Important**: After scope change, the Bot Token (`xoxb-`) might be INVALIDATED by Slack if they chose to rotate. In most cases it stays. If bot stops working after re-install, user may need to copy the new Bot Token from OAuth & Permissions page and update `~/.zshrc.local` manually.

## Common Scenarios

### "Add files:read and files:write to Secretary"

1. `list-scopes.sh noanswer secretary` → shows `[app_mentions:read, chat:write, channels:history]`
2. Show diff: `+files:read, +files:write`
3. User confirms
4. `update-scopes.sh noanswer secretary add "files:read,files:write"`
5. Direct user to re-install URL

### "What scopes does Notifier have right now?"

Just run `list-scopes.sh noanswer notifier` and display output.

### "Remove channels:history, it's too broad"

1. `list-scopes.sh` first to confirm it's currently there
2. `update-scopes.sh noanswer secretary remove "channels:history"`
3. Re-install notification

## Error Recovery

### `apps.manifest.export` returns `invalid_auth`
→ Config token expired. Same fix as slack-bot-factory: re-bootstrap if rotation fails.

### `apps.manifest.update` returns `invalid_manifest`
→ Scope name typo OR trying to add a scope that requires special approval (e.g., `admin.*`). Print the error detail.

### Scope change doesn't take effect
→ User forgot to re-install. Scopes are declared in manifest but only granted after OAuth re-install.

### Bot token invalidated after re-install
Rare but possible. User needs to:
1. Go to OAuth & Permissions page
2. Copy new Bot Token (`xoxb-...`)
3. Edit `~/.zshrc.local` directly to replace the old token value
4. `source ~/.zshrc.local`

## State File Updates

After successful `apps.manifest.update`, the local state file's `bots[].scopes` and `bots[].events` are updated to match. This keeps the local state in sync with Slack's source of truth.
