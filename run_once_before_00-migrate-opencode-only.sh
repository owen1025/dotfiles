#!/bin/bash
set -euo pipefail

# One-time migration cleanup for OpenCode-only dotfiles.
# Keep ~/.anthropic and unrelated ~/.claude history/cache; remove only legacy managed config and shared-skill copies.

OPENCODE_SKILLS="${HOME}/.config/opencode/skills"

# Remove legacy OpenCode skill symlink that used to point into ~/.claude/skills.
if [[ -L "${OPENCODE_SKILLS}/slack-opencode-bridge-factory" ]]; then
  /bin/rm -f "${OPENCODE_SKILLS}/slack-opencode-bridge-factory"
fi

# Remove Claude Code managed config files previously deployed by chezmoi.
/bin/rm -f "${HOME}/.claude/.mcp.json" || true
/bin/rm -f "${HOME}/.claude/settings.json" || true
/bin/rm -f "${HOME}/.claude/.omc-config.json" || true

# Remove Claude Code skill symlinks/copies. OpenCode is now the only managed skill target.
/bin/rm -rf "${HOME}/.claude/skills" || true

# Remove project-scope skills that no longer belong in global dotfiles.
/bin/rm -rf "${OPENCODE_SKILLS}/english-conversation-trainer" || true
/bin/rm -rf "${OPENCODE_SKILLS}/vpn-manager" || true


# Remove any skills.sh registrations that may have recreated Claude Code skill symlinks.
if command -v npx >/dev/null 2>&1; then
  npx -y skills remove -g --agent claude-code --skill '*' -y >/dev/null 2>&1 || true
fi

# Remove OMC globals if npm is available. Non-fatal for machines without npm.
if command -v npm >/dev/null 2>&1; then
  npm uninstall -g oh-my-claude-sisyphus clawdbot >/dev/null 2>&1 || true
fi

echo "OpenCode-only migration cleanup complete."
