export TERM="xterm-256color"

# Path to your oh-my-zsh installation.
export ZSH="${HOME}/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
  fasd
  aws
  kubectl
  kube-ps1
)

source $ZSH/oh-my-zsh.sh

source ~/antigen.zsh

antigen use oh-my-zsh

# Bundles from the default repo (robbyrussell's oh-my-zsh).
antigen bundle git
antigen bundle gitfast
antigen bundle command-not-found

# Syntax highlighting bundle.
antigen bundle zsh-users/zsh-syntax-highlighting

antigen bundle zsh-users/zsh-autosuggestions

# Load the theme.
antigen theme romkatv/powerlevel10k

# zsh-nvm
antigen bundle lukechilds/zsh-nvm

# Tell Antigen that you're done.
antigen apply

# `Frozing' tty, so after any command terminal settings will be restored
ttyctl -f

# Custom common alias
alias la="ls -al"

# Custom brew alias
alias bi="brew install"
alias bri="brew reinstall"

# Custom docker alias
alias dkrmC='docker rm $(docker ps -qaf status=exited)'
alias dkrmI='docker rmi $(docker images -qf dangling=true)'
alias dkps="docker ps -a"
alias dki="docker images"
alias dkb="docker build -t"
alias dkp="docker pull"
alias dkr="docker run"
alias dkri="docker run -it --entrypoint /bin/bash"
alias dkrd="docker run -d"
alias dkrmc="docker rm"
alias dkrmi="docker rmi"
alias dkec="docker exec -it --entrypoint /bin/bash"
alias dkp="docker push"

# Custom git alias
alias gi="git init"
alias gc="git clone"
alias gs="git status"
alias gcc="git commit -m"
alias ga="git add --all"
alias gp="git push"
alias gct="git checkout"
alias gm="git merge"

# Custom tmux alias
alias tmux="tmux -2 -u"
alias tx="tmux -2 -u"
alias txls="tmux list-sessions"
alias txa="tmux -2 -u attach -t"

# Custom tmuxinator alias
alias txr="tmuxinator"
alias txrl="tmuxinator list"
alias txrn="tmuxinator new"
alias txrs="tmuxinator start"
alias txrd="tmuxinator delete"

# Custom vim alias
alias v="nvim"
alias vim="nvim"

# Custom terraform alias
alias ti="terraform init"
alias tp="terraform plan"
alias ta="terraform apply"
alias tc="terraform console"
alias td="terraform destroy"

# Custom ansible alias
alias ap="ansible-playbook"

# Custom kubectl alias
alias ka="kubectl apply -f"
alias kgp="kubectl get pods"
alias kgd="kubectl get deployment"
alias kgl="kubectl logs"
alias kgn="kubectl get nodes"
alias kec="kubectl exec -it"

alias kx="kubectx"
alias ke="kubens"

# Custom lazygit aliazs
alias lg="lazygit"

# get my external ip
alias gei="curl -s http://whatismijnip.nl |cut -d \" \" -f 5"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Custom ENV
# Setup to python path
export PATH="/Users/$(whoami)/Library/Python/2.7/bin:$PATH"
export EDITOR="nvim"
export TMUXINATOR_CONFIG="$HOME/.tmuxinator"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
source ~/.p10k.zsh
