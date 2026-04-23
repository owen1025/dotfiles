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

# sparse_clone_subset DIR URL PATH [PATH...]
# Clones only the requested subdirectories from URL into DIR via git sparse-checkout.
# Use for monorepos / mega-skill-catalogs where we only want a few skills.
sparse_clone_subset() {
	local dir="$1" url="$2"
	shift 2
	local paths=("$@")

	if [ -d "$dir" ]; then
		echo "[skip] $(basename "$dir") already exists"
		return 0
	fi
	echo "[sparse-clone] $url → ${paths[*]}"
	git clone --filter=blob:none --no-checkout --depth=1 "$url" "$dir"
	git -C "$dir" sparse-checkout init --cone
	git -C "$dir" sparse-checkout set "${paths[@]}"
	git -C "$dir" checkout
}

clone_if_missing "$OPENCODE_SKILLS/trailofbits" \
	"https://github.com/trailofbits/skills.git"

clone_if_missing "$OPENCODE_SKILLS/superpowers" \
	"https://github.com/obra/superpowers.git"

clone_if_missing "$OPENCODE_SKILLS/ccpm" \
	"https://github.com/automazeio/ccpm"

# openclaw/skills monorepo (clawskills.sh). Curated subset. See docs/openclaw-skills.md for deps+env vars.
sparse_clone_subset "$OPENCODE_SKILLS/openclaw" \
	"https://github.com/openclaw/skills.git" \
	"skills/steipete/markdown-converter" \
	"skills/steipete/gog" \
	"skills/steipete/1password" \
	"skills/arnarsson/git-essentials" \
	"skills/jk-0001/automation-workflows" \
	"skills/oyi77/data-analyst" \
	"skills/shawnpana/browser-use" \
	"skills/whiteknight07/exa-web-search-free" \
	"skills/udiedrichsen/stock-analysis"

case "$(uname -s)" in
Darwin)
	if [ -d "$OPENCODE_SKILLS/openclaw" ]; then
		echo "[sparse-update] openclaw → +macOS-only skills"
		git -C "$OPENCODE_SKILLS/openclaw" sparse-checkout add \
			"skills/steipete/apple-notes" \
			"skills/steipete/apple-reminders" 2>/dev/null || true
	fi
	;;
esac

# Private repo — requires SSH key (github.com-personal host alias).
# Non-fatal: skip silently on machines without the key.
clone_if_missing "$OPENCODE_SKILLS/poker-tournament-trainer" \
	"git@github.com-personal:owen1025/training.git" 2>/dev/null || true

# Selective skills from ComposioHQ/awesome-claude-skills (monorepo).
# Only pull the 2 skills we use; skip the other ~30 dirs.
sparse_clone_subset "$OPENCODE_SKILLS/composio-skills" \
	"https://github.com/ComposioHQ/awesome-claude-skills.git" \
	"mcp-builder" "skill-creator"

# Selective skills from sickn33/antigravity-awesome-skills (1400+ skills).
# Only pull the specific skills we use; sparse-checkout keeps the dir small.
sparse_clone_subset "$OPENCODE_SKILLS/antigravity-skills" \
	"https://github.com/sickn33/antigravity-awesome-skills.git" \
	"skills/bash-linux" \
	"skills/analyze-project" \
	"skills/autonomous-agent-patterns"

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
