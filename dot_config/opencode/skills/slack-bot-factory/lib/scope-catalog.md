# Slack Bot Scopes Catalog

Reference for agents building Slack bots. Use this to map user intent → scopes.

## Scope → Capability Map

### Messages / Channels

| Scope | What it allows |
|---|---|
| `chat:write` | Send messages as the bot to channels the bot is in |
| `chat:write.public` | Send to public channels WITHOUT being a member |
| `chat:write.customize` | Customize username/avatar per message |
| `channels:history` | Read message history in public channels the bot is in |
| `channels:read` | List public channels, get channel info |
| `channels:join` | Join public channels programmatically |
| `groups:history` | Read message history in private channels |
| `groups:read` | List private channels the bot is in |
| `groups:write` | Manage private channels (create, archive) |
| `mpim:history`, `mpim:read`, `mpim:write` | Group DMs |
| `im:history`, `im:read`, `im:write` | Direct messages with users |

### Mentions & Reactions

| Scope | What it allows |
|---|---|
| `app_mentions:read` | Receive `app_mention` events when bot is @mentioned |
| `reactions:read` | Read emoji reactions |
| `reactions:write` | Add/remove emoji reactions |

### Users

| Scope | What it allows |
|---|---|
| `users:read` | List workspace members, basic profile |
| `users:read.email` | Include email in user info |
| `users.profile:read` | Detailed profile fields (status, custom fields) |

### Files

| Scope | What it allows |
|---|---|
| `files:read` | Read file contents |
| `files:write` | Upload files |

### Commands & Interactivity

| Scope | What it allows |
|---|---|
| `commands` | Register slash commands |
| `workflow.steps:execute` | Execute workflow steps (legacy Workflow Builder) |

### Admin (rare)

| Scope | What it allows |
|---|---|
| `admin` | Admin operations (requires paid plan + admin user) |
| `team:read` | Read workspace info |

---

## Bot Events (Socket Mode subscriptions)

Most common events bots subscribe to:

| Event | Fires when | Required scope |
|---|---|---|
| `app_mention` | Bot is @mentioned | `app_mentions:read` |
| `message.channels` | New message in any channel bot is in | `channels:history` |
| `message.groups` | New message in private channel | `groups:history` |
| `message.im` | New DM to bot | `im:history` |
| `message.mpim` | New group DM message | `mpim:history` |
| `reaction_added`, `reaction_removed` | Emoji reaction | `reactions:read` |
| `team_join` | New user joins workspace | `users:read` |
| `channel_created` | New channel created | `channels:read` |
| `file_shared` | File shared in channel | `files:read` |

---

## Recipes

### "Secretary" style (mention-based chatbot)
```
bot_scopes: app_mentions:read, chat:write, channels:history, channels:read, users:read
bot_events: app_mention
socket_mode: true
```

### "Notifier" (one-way push only)
```
bot_scopes: chat:write, chat:write.public
bot_events: (none)
socket_mode: false
```

### "Channel Monitor" (read + occasional write)
```
bot_scopes: channels:history, channels:read, chat:write
bot_events: message.channels
socket_mode: true
```

### "DM Assistant" (personal bot via DM)
```
bot_scopes: im:history, im:read, im:write, chat:write, users:read
bot_events: message.im
socket_mode: true
```

### "Full-featured assistant"
```
bot_scopes: app_mentions:read, chat:write, chat:write.public,
            channels:history, channels:read,
            im:history, im:read, im:write,
            reactions:read, reactions:write,
            users:read, files:read
bot_events: app_mention, message.im, reaction_added
socket_mode: true
```

---

## Intent → Scope Mapping (for agent NLU)

User says... | Scopes to add
---|---
"멘션에 응답" / "mention에 답변" | `app_mentions:read` + `chat:write`
"채널 메시지 읽기" / "monitor channel" | `channels:history` + `channels:read`
"채널에 메시지 보내기" | `chat:write`
"초대 없이 공개 채널에 보내기" | `chat:write` + `chat:write.public`
"DM으로 대화" | `im:history` + `im:read` + `im:write` + `chat:write`
"이모지 반응" | `reactions:read` + `reactions:write`
"사용자 정보 조회" | `users:read`
"파일 업로드" | `files:write`
"파일 읽기/다운로드" | `files:read`
"슬래시 커맨드 (/mycommand)" | `commands`

---

## Gotchas

- **`chat:write.public`** lets the bot write to public channels WITHOUT being invited. Convenient but spammy-risk. Only add if really needed.
- **`channels:history` vs `groups:history`**: Public vs private channels are DIFFERENT scope namespaces. If bot needs to read both, add both.
- **`app_mention` event requires `app_mentions:read` scope**. Slack doesn't auto-add scope when you subscribe to events. Missing = event never fires.
- **Socket Mode requires `connections:write` on the App-Level Token** (NOT on bot token). This is a separate thing set via UI when generating xapp- token.
- **User tokens (`xoxp-`) vs Bot tokens (`xoxb-`)** — this skill only handles bot tokens. User tokens act as the installing user, rarely needed.
