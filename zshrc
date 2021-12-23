export TERM="xterm-256color"

# Path to your oh-my-zsh installation.
export ZSH="${HOME}/.oh-my-zsh"

plugins=(
  fasd
  aws
  kubectl
  sudo
  asdf
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

antigen bundle zsh-users/zsh-completions

# Load the theme.
antigen theme romkatv/powerlevel10k

# Tell Antigen that you're done.
antigen apply

# `Frozing' tty, so after any command terminal settings will be restored
ttyctl -f

# Custom common alias
alias la="exa -al"

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
alias gh="open `git remote -v | grep fetch | awk '{print $2}' | sed 's/git@/http:\/\//' | sed 's/com:/com\//'`| head -n1"

# Custom tmux alias
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

# Custom terraform alias
alias ti="terraform init"
alias tp="terraform plan"
alias ta="terraform apply"
alias tc="terraform console"
alias td="terraform destroy"
alias tsls="terraform state list"
alias tsrm="terraform state rm"
alias tspl="terraform state pull"
alias tsps="terraform state push"
alias tsmv="terraform state mv"
alias tri="terraform import"

# Custom terragrunt alias
alias tg="terragrunt"
alias tgi="terragrunt init"
alias tga="terragrunt apply"
alias tgp="terragrunt plan"
alias tgd="terragrunt destroy"

# Custom ansible alias
alias ap="ansible-playbook"

# Custom kubectl alias
alias ka="kubectl apply"
# alias kd="kubectl delete"
alias kg="kubectl get"
alias kde="kubectl describe"
alias kgl="kubectl logs -f"
alias ket="kubectl exec -it"
alias kpf="kubectl port-forward"

alias kx="kubectx"
alias ke="kubens"

alias krb="kubectl run -i --rm --tty busybox --image=busybox -- sh"
alias krc="kubectl run -i --rm --tty busybox --image=centos:latest -- bash"

alias krh="kubectl rollout history"
alias krr="kubectl rollout restart"
alias kru="kubectl rollout undo"

alias ktd="kubectl tree deployment"
alias kts="kubectl tree service"

alias kcc="kubectl config current-context"

# helm alias
alias h="helm"
alias hla="helm list -A"

# Custom lazygit aliazs
alias lg="lazygit"

# get my external ip
alias gei="curl -s http://whatismijnip.nl |cut -d \" \" -f 5"

# get zombie processes
alias gzp="ps axo stat,ppid,pid,comm | grep -w defunct"
# kill zombie processes
alias kzp="kill $(ps -A -ostat,ppid | awk '/[zZ]/ && !a[$2]++ {print $2}')"

# fzf setup
alias f="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Custom ENV
export EDITOR="nvim"
export TMUXINATOR_CONFIG="$HOME/.tmuxinator"

# Set iCloud path
export ICLOUD=~/Library/Mobile\ Documents/com~apple~CloudDocs

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
source ~/.p10k.zsh

# fuck
eval $(thefuck --alias)

# stern completion
alias s="stern -A"
source <(stern --completion=zsh)

# krew environment
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# awsp alias
# https://github.com/johnnyopao/awsp
alias awsp="source _awsp"

# ctags
alias ctags="`brew --prefix`/bin/ctags"

############# Hyperconnect ################
alias vl="export VAULT_ADDR=https://vault.kube-prod-an1.hpcnt.com && vault login -method=oidc role=infra-role-devops"
alias has="hp aws write-credentials --refresh && vl"
alias kgn="kubectl get nodes -L node.hpcnt.com/role -L node.hpcnt.com/service -L node.hpcnt.com/stack -L node.hpcnt.com/duty -L node.hpcnt.com/hardware -L node.hpcnt.com/lifecycle -L node.hpcnt.com/os -L node.kubernetes.io/instance-type -L kubernetes.io/arch -L topology.kubernetes.io/zone -L vpc.amazonaws.com/has-trunk-attached"

autoload -U compinit && compinit -u
