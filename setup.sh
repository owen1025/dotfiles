#!/bin/bash

BASEDIR=$(dirname "$0")

# Install a brew
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# Brew update 
brew update

# install mas
brew install mas

# install all client
brew bundle

# chsh: /usr/local/bin/zsh: non-standard shell - OSX error issue
echo $(which zsh) >> /etc/shells

# Install a oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

# Install a antigen
curl -L git.io/antigen > "${HOME}/antigen.zsh"

# To install useful key bindings and fuzzy completion:
$(brew --prefix)/opt/fzf/install

ln "${BASEDIR}/.zshrc" "${HOME}/.zshrc"
ln "${BASEDIR}/.vimrc" "${HOME}/.vimrc"
ln "${BASEDIR}/tmux/.tmux.conf" "${HOME}/.tmux.conf"
ln "${BASEDIR}/tmux/.tmux.conf.local" "${HOME}/.tmux.conf.local"

# Apply the zsh config(Powerlevel9K, Plugin, etc...)
source ~/.zshrc

# Install a vim plugin manager(Vundle, vim-plug, Neobundle)
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
   https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
mkdir ~/.vim/bundle
git clone https://github.com/Shougo/neobundle.vim ~/.vim/bundle/neobundle.vim

# Install a vim plugin
vim +PlugInstall +qall
vim +PluginInstall +qall
vim +NeoBundleInstall +qall
