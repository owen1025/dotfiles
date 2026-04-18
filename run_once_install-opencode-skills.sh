#!/bin/bash
set -e
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true

OPENCODE_SKILLS="${HOME}/.config/opencode/skills"
mkdir -p "$OPENCODE_SKILLS"

# ---------------------------------------------------------------------------
# 1. Git clone skills (idempotent — skip if dir exists)
# ---------------------------------------------------------------------------
clone_if_missing() {
	local dir="$1" url="$2"
	if [ -d "$dir" ]; then
		echo "[skip] $(basename "$dir") already exists"
		return 0
	fi
	echo "[clone] $url"
	git clone "$url" "$dir"
}

clone_if_missing "$OPENCODE_SKILLS/trailofbits" \
	"https://github.com/trailofbits/skills.git"

clone_if_missing "$OPENCODE_SKILLS/superpowers" \
	"https://github.com/obra/superpowers.git"

clone_if_missing "$OPENCODE_SKILLS/ccpm" \
	"https://github.com/automazeio/ccpm"

# Private repo — requires SSH key (github.com-personal host alias).
# Non-fatal: skip silently on machines without the key.
clone_if_missing "$OPENCODE_SKILLS/poker-tournament-trainer" \
	"git@github.com-personal:owen1025/training.git" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. npx skills add (idempotent — skips already-installed skills)
#    Requires: node/npm (installed via brew bundle)
# ---------------------------------------------------------------------------
if command -v npx &>/dev/null; then
	# PM Skills — 65 product management skills (phuryn/pm-skills)
	npx -y skills add phuryn/pm-skills -g -y 2>/dev/null || true

	# Claude Code Tools — aichat, tmux-cli, workflow (pchalasani/claude-code-tools)
	npx -y skills add pchalasani/claude-code-tools -g -y 2>/dev/null || true

	# Vercel agent skills — react, composition patterns, web design, react native
	npx -y skills add vercel-labs/agent-skills -g -y 2>/dev/null || true

	# Vercel skills — find-skills
	npx -y skills add vercel-labs/skills -g -y 2>/dev/null || true
else
	echo "WARN: npx not found. Skipping npx-managed skills." >&2
fi

# ---------------------------------------------------------------------------
# 3. Notes
# ---------------------------------------------------------------------------
# - dev-browser: installed automatically by oh-my-openagent plugin. No action needed.
# - english-conversation-trainer, vpn-manager: chezmoi-managed custom skills
#   (synced as dot_config/opencode/skills/*/SKILL.md).
# - progress.md files inside skill dirs are machine-specific and NOT synced.
