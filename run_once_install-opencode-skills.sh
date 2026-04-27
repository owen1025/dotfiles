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
# Discovery-pipeline sources (scanned by mcp-skill-discovery polling daemon)
# These awesome-lists are cloned for markdown parsing + skill reference.
# See AGENTS.md "Discovery Pipeline Sources" section.
# ---------------------------------------------------------------------------

# anthropics/skills — Official Anthropic Claude Skills (PDF/DOCX/PPTX/XLSX/etc.)
clone_if_missing "$OPENCODE_SKILLS/anthropic-official" \
	"https://github.com/anthropics/skills.git"

# VoltAgent/awesome-agent-skills — 1000+ curated official skills (Stripe, Cloudflare, Sentry, Figma, etc.). No-slop policy.
clone_if_missing "$OPENCODE_SKILLS/voltagent-awesome" \
	"https://github.com/VoltAgent/awesome-agent-skills.git"

# hesreallyhim/awesome-claude-code — 40K+ stars, skills + hooks + slash-commands + orchestrators
clone_if_missing "$OPENCODE_SKILLS/awesome-claude-code" \
	"https://github.com/hesreallyhim/awesome-claude-code.git"

# travisvn/awesome-claude-skills — 11K+ stars, practical skills directory
clone_if_missing "$OPENCODE_SKILLS/awesome-claude-skills" \
	"https://github.com/travisvn/awesome-claude-skills.git"

# skills.sh — queried at runtime via `npx skills find <query>`. No clone needed.
# The add-skill CLI (already ensured via `npx` presence check above) resolves
# packages from GitHub/GitLab/npm when discovery pipeline proposes installs.

# ---------------------------------------------------------------------------
# 2. npx skills add (idempotent — skips already-installed skills)
#    Requires: node/npm (installed via brew bundle)
# ---------------------------------------------------------------------------
if command -v npx &>/dev/null; then
	# PM Skills — 65 product management skills (phuryn/pm-skills)
	npx -y skills add phuryn/pm-skills -g --agent opencode -y 2>/dev/null || true

	# skills.sh tool bundle — aichat, tmux-cli, workflow (pchalasani/claude-code-tools)
	npx -y skills add pchalasani/claude-code-tools -g --agent opencode -y 2>/dev/null || true

	# Vercel agent skills — react, composition patterns, web design, react native
	npx -y skills add vercel-labs/agent-skills -g --agent opencode -y 2>/dev/null || true

	# Vercel skills — find-skills
	npx -y skills add vercel-labs/skills -g --agent opencode -y 2>/dev/null || true
else
	echo "WARN: npx not found. Skipping npx-managed skills." >&2
fi

# ---------------------------------------------------------------------------
# 3. Flatten deeply-nested skills (depth ≥4 → 1-level symlinks)
#    OpenCode's Skill MCP tool only registers paths at depth ≤3 from the
#    skills root. Deeper SKILL.md files (e.g., trailofbits's 5-level
#    `plugins/{plugin}/skills/{skill}/SKILL.md` and openclaw's 4-level
#    `skills/{maintainer}/{skill}/SKILL.md`) appear in the system prompt's
#    available_skills list but cannot be invoked via Skill(name=...).
#    This step creates basename symlinks at depth 1 to make them callable.
#    Tracked via .flatten-manifest.txt for idempotent cleanup on rerun.
# ---------------------------------------------------------------------------
remove_tracked_symlinks() {
	local manifest="$1" skills_root="$2"
	[ -f "$manifest" ] || return 0
	while IFS= read -r name; do
		[ -z "$name" ] && continue
		[ -L "$skills_root/$name" ] && rm "$skills_root/$name"
	done <"$manifest"
	: >"$manifest"
}

flatten_deep_skills() {
	local skills_root="$OPENCODE_SKILLS"
	local manifest="$skills_root/.flatten-manifest.txt"

	remove_tracked_symlinks "$manifest" "$skills_root"

	# `find` without -L does NOT follow symlinks; this prevents infinite
	# recursion through the depth-1 symlinks we are about to create.
	find "$skills_root" -type f -name "SKILL.md" 2>/dev/null | while IFS= read -r skill_md; do
		local skill_dir rel depth name target
		skill_dir="${skill_md%/SKILL.md}"
		rel="${skill_dir#"$skills_root/"}"
		depth=$(echo "$rel" | tr '/' '\n' | wc -l | tr -d ' ')
		[ "$depth" -lt 4 ] && continue

		name=$(basename "$skill_dir")
		target="$skills_root/$name"

		if [ -e "$target" ] && [ ! -L "$target" ]; then
			echo "[flatten skip] $name → conflict with existing dir/file" >&2
			continue
		fi

		ln -sfn "$rel" "$target"
		echo "$name" >>"$manifest"
	done

	if [ -f "$manifest" ]; then
		local count
		count=$(wc -l <"$manifest" | tr -d ' ')
		echo "[flatten] $count deep skills symlinked at depth 1"
	fi
}

flatten_deep_skills

# ---------------------------------------------------------------------------
# 4. Notes
# ---------------------------------------------------------------------------
# - dev-browser: installed automatically by oh-my-openagent plugin. No action needed.
# - progress.md files inside skill dirs are machine-specific and NOT synced.
# - .flatten-manifest.txt is per-machine state, NOT synced via chezmoi.
