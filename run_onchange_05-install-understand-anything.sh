#!/bin/bash
set -euo pipefail

eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true

UA_REPO_URL="${UA_REPO_URL:-https://github.com/Egonex-AI/Understand-Anything.git}"
UA_REPO_DIR="${UA_DIR:-${HOME}/.understand-anything/repo}"
UA_PLUGIN_DIR="${UA_REPO_DIR}/understand-anything-plugin"
UA_SKILLS_DIR="${UA_PLUGIN_DIR}/skills"
UA_PLUGIN_LINK="${HOME}/.understand-anything-plugin"

clone_or_update_understand_anything() {
	if [ -d "$UA_REPO_DIR/.git" ]; then
		echo "[update] Understand-Anything checkout: $UA_REPO_DIR"
		if ! git -C "$UA_REPO_DIR" pull --ff-only; then
			echo "WARN: Could not fast-forward Understand-Anything; keeping existing checkout" >&2
		fi
		return 0
	fi

	echo "[clone] $UA_REPO_URL -> $UA_REPO_DIR"
	mkdir -p "$(dirname "$UA_REPO_DIR")"
	git clone "$UA_REPO_URL" "$UA_REPO_DIR"
}

link_path() {
	local source="$1" target="$2"
	mkdir -p "$(dirname "$target")"

	if [ -L "$target" ]; then
		rm -f "$target"
	elif [ -e "$target" ]; then
		echo "WARN: $target exists and is not a symlink; leaving it unchanged" >&2
		return 0
	fi

	ln -s "$source" "$target"
	echo "[link] $target -> $source"
}

link_per_skill() {
	local target_root="$1"
	local skill_dir name

	[ -d "$UA_SKILLS_DIR" ] || {
		echo "ERROR: Understand-Anything skills directory missing: $UA_SKILLS_DIR" >&2
		exit 1
	}

	mkdir -p "$target_root"
	for skill_dir in "$UA_SKILLS_DIR"/*; do
		[ -d "$skill_dir" ] || continue
		name="$(basename "$skill_dir")"
		link_path "$skill_dir" "$target_root/$name"
	done
}

link_hermes_folder() {
	local target_root="$1"
	mkdir -p "$target_root"
	link_path "$UA_SKILLS_DIR" "$target_root/understand-anything"
}

link_hermes_profiles() {
	local profiles_root="${HOME}/.hermes/profiles"
	local profile_dir profile_name

	link_hermes_folder "${HOME}/.hermes/skills"

	[ -d "$profiles_root" ] || return 0
	for profile_dir in "$profiles_root"/*; do
		[ -d "$profile_dir" ] || continue
		profile_name="$(basename "$profile_dir")"
		case "$profile_name" in
			.*|_*) continue ;;
		esac
		[ -f "$profile_dir/config.yaml" ] || continue
		link_hermes_folder "$profile_dir/skills"
	done
}

clone_or_update_understand_anything
link_path "$UA_PLUGIN_DIR" "$UA_PLUGIN_LINK"

# Upstream's OpenCode installer targets ~/.agents/skills. This dotfiles setup
# also keeps OpenCode-managed skills under ~/.config/opencode/skills, so link
# both roots to make the skill visible to OpenCode and OhMyOpenCode sessions.
link_per_skill "${HOME}/.agents/skills"
link_per_skill "${HOME}/.config/opencode/skills"

# Hermes treats each profile as an independent HERMES_HOME. The upstream
# installer links only ~/.hermes/skills, so mirror the folder link into every
# existing profile's skills directory as well.
link_hermes_profiles

echo "[done] Understand-Anything linked for OpenCode and Hermes profiles"
