#!/bin/bash
# run_once_setup-omo-skills-symlinks.sh
# Creates symlinks from ~/.claude/skills/ (chezmoi-managed) to ~/.config/opencode/skills/ (OMO)
# for skills that need to be accessible from both OMC and OMO.

set -euo pipefail

SKILLS_SRC="$HOME/.claude/skills"
SKILLS_DST="$HOME/.config/opencode/skills"

# Add skills here that need OMC + OMO sharing
SHARED_SKILLS=(
	"slack-opencode-bridge-factory"
)

mkdir -p "$SKILLS_DST"

for skill in "${SHARED_SKILLS[@]}"; do
	src="$SKILLS_SRC/$skill"
	dst="$SKILLS_DST/$skill"

	# Skip if source not installed
	if [[ ! -d "$src" ]]; then
		echo "SKIP: $src not found (skill not installed yet)"
		continue
	fi

	# Already a symlink pointing to the right place → no-op
	if [[ -L "$dst" ]]; then
		current_target=$(readlink "$dst")
		if [[ "$current_target" == "$src" ]]; then
			echo "OK: $dst → $src (already correct)"
			continue
		fi
		# Wrong target → replace
		ln -sfn "$src" "$dst"
		echo "FIXED: $dst → $src (was → $current_target)"
		continue
	fi

	# Regular file or directory at target → DO NOT overwrite
	if [[ -e "$dst" ]]; then
		echo "WARN: $dst exists as a regular file/directory — NOT overwriting. Remove manually if needed."
		continue
	fi

	# Create new symlink
	ln -sfn "$src" "$dst"
	echo "LINKED: $dst → $src"
done

echo "OMO skill symlinks setup complete."
