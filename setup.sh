#!/bin/bash

BASEDIR=$(dirname "$0")

# Install a brew
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# Brew update
brew update

# install all client
brew bundle

# Install a oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

# Install antigen
curl -L git.io/antigen >"${HOME}/antigen.zsh"

# To install useful key bindings and fuzzy completion:
/opt/homebrew/opt/fzf/install --no-bash --no-zsh --no-fish --key-bindings --completion

ln -sf "${BASEDIR}/.zshrc" "${HOME}/.zshrc"
ln -sf "${BASEDIR}/.vimrc" "${HOME}/.vimrc"
ln -sf "${BASEDIR}/tmux/.tmux.conf" "${HOME}/.tmux.conf"
ln -sf "${BASEDIR}/tmux/.tmux.conf.local" "${HOME}/.tmux.conf.local"

# set up kubectx completion
mkdir -p ~/.oh-my-zsh/completions
chmod -R 755 ~/.oh-my-zsh/completions
ln -s /opt/kubectx/completion/kubectx.zsh ~/.oh-my-zsh/completions/_kubectx.zsh
ln -s /opt/kubectx/completion/kubens.zsh ~/.oh-my-zsh/completions/_kubens.zsh

# set up Coc-config
ln -sf "${BASEDIR}/coc-settings.json" ~/.config/nvim/coc-settings.json

# ──────────────────────────────────────────────
# OpenCode config (MCP servers, agents, themes)
# ──────────────────────────────────────────────
OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
mkdir -p "${OPENCODE_CONFIG_DIR}/themes" "${OPENCODE_CONFIG_DIR}/command" "${OPENCODE_CONFIG_DIR}/mcp-servers" "${OPENCODE_CONFIG_DIR}/plugins"

# Core config files
ln -sf "${BASEDIR}/opencode/opencode.json" "${OPENCODE_CONFIG_DIR}/opencode.json"
ln -sf "${BASEDIR}/opencode/oh-my-opencode.json" "${OPENCODE_CONFIG_DIR}/oh-my-opencode.json"
ln -sf "${BASEDIR}/opencode/tui.json" "${OPENCODE_CONFIG_DIR}/tui.json"

# Custom theme
ln -sf "${BASEDIR}/opencode/themes/owen.json" "${OPENCODE_CONFIG_DIR}/themes/owen.json"

# Custom commands
ln -sf "${BASEDIR}/opencode/command/plannotator-annotate.md" "${OPENCODE_CONFIG_DIR}/command/plannotator-annotate.md"
ln -sf "${BASEDIR}/opencode/command/plannotator-review.md" "${OPENCODE_CONFIG_DIR}/command/plannotator-review.md"

# Plugin config
ln -sf "${BASEDIR}/opencode/opencode-ntfy.json" "${OPENCODE_CONFIG_DIR}/opencode-ntfy.json"

# Plugins
ln -sf "${BASEDIR}/opencode/plugins/superpowers.js" "${OPENCODE_CONFIG_DIR}/plugins/superpowers.js"

# Install MCP server dependencies
(cd "${OPENCODE_CONFIG_DIR}/mcp-servers" && npm install 2>/dev/null)

echo "✓ OpenCode config linked"

# ──────────────────────────────────────────────
# Ghostty terminal config
# ──────────────────────────────────────────────
GHOSTTY_CONFIG_DIR="${HOME}/Library/Application Support/com.mitchellh.ghostty"
mkdir -p "${GHOSTTY_CONFIG_DIR}"
ln -sf "${BASEDIR}/ghostty/config" "${GHOSTTY_CONFIG_DIR}/config"
echo "✓ Ghostty config linked"

# Apply the zsh config(Powerlevel9K, Plugin, etc...)
source ~/.zshrc

# install tmux plugins
git clone https://github.com/tmux-plugins/tmux-resurrect ~/clone/path

# install zsh-kubecolor
git clone https://github.com/devopstales/zsh-kubecolor.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-kubecolor

# Install a vim plugin manager(Vundle, vim-plug, Neobundle)
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
	https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
mkdir ~/.vim/bundle
git clone https://github.com/Shougo/neobundle.vim ~/.vim/bundle/neobundle.vim

# Install a vim plugin
# vim +PlugInstall +qall
# vim +PluginInstall +qall
# vim +NeoBundleInstall +qall
