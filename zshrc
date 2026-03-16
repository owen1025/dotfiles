# Set TERM only outside tmux — inside tmux, let tmux's default-terminal take effect
if [[ -z "$TMUX" ]]; then
  export TERM="xterm-256color"
fi

# Path to your oh-my-zsh installation.
export ZSH="${HOME}/.oh-my-zsh"

plugins=(
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
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle Aloxaf/fzf-tab
antigen bundle djui/alias-tips

# Load the theme.
antigen theme romkatv/powerlevel10k

# Tell Antigen that you're done.
antigen apply

# `Frozing' tty, so after any command terminal settings will be restored
ttyctl -f

# history-substring-search key bindings
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Custom eza alias (modern ls replacement)
alias ls="eza"
alias ll="eza -l --icons"
alias la="eza -la --icons"
alias lt="eza --tree --icons"

# Custom bat alias (modern cat replacement)
alias cat="bat"

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
alias gopen="open $(git remote -v | grep fetch | awk '{print $2}' | sed 's/git@/http:\/\//' | sed 's/com:/com\//'| head -n1)"

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

# GCP Terraform SA credentials
# export GOOGLE_APPLICATION_CREDENTIALS="$HOME/Desktop/gowid/gowid-devops/devops-terraform/config/gowid-prd-terraform-admin.json"

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
alias kgp="kubectl get pods -o wide"
alias kge="kubectl get events --sort-by=.metadata.creationTimestamp"
alias kgn="kubectl get nodes -L beta.kubernetes.io/instance-type -L node.carpenstreet.com/type -L beta.kubernetes.io/arch -L node.carpenstreet.com/hardware"

function kx() { kubectx "$@" }
function ke() { kubens "$@" }

alias krb="kubectl run -i --rm --tty busybox --image=busybox -- sh"
alias krc="kubectl run -i --rm --tty busybox --image=centos:latest -- bash"

alias krh="kubectl rollout history"
alias krr="kubectl rollout restart"
alias kru="kubectl rollout undo"

alias ktd="kubectl tree deployment"
alias kts="kubectl tree service"

alias kcc="kubectl config current-context"

alias kdn="kubectl drain node --ignore-daemonsets --delete-emptydir-data"

# helm alias
alias h="helm"
alias hla="helm list -A"

# Custom lazygit alias
alias lg="lazygit"

# Custom lazydocker alias
alias ld="lazydocker"

# Custom tldr alias (tealdeer)
alias tl="tldr"

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
source <(fzf --zsh)

# forgit (installed via brew)
source /opt/homebrew/opt/forgit/share/forgit/forgit.plugin.zsh

# Custom ENV
export EDITOR="nvim"
export TMUXINATOR_CONFIG="$HOME/.tmuxinator"

# Set iCloud path
export ICLOUD=~/Library/Mobile\ Documents/com~apple~CloudDocs

# zoxide (replaces fasd + autojump)
eval "$(zoxide init zsh)"
alias cd="z"
alias cdi="zi"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
source ~/.p10k.zsh

# krew environment
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# k9s
alias k9s="export XDG_CONFIG_HOME=~ && k9s"

# awsp alias
# https://github.com/johnnyopao/awsp
alias awsp="source _awsp"

# ctags
alias ctags="`brew --prefix`/bin/ctags"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


# python3
alias python="python3"
alias pip="pip3"

autoload -U compinit && compinit -u

# kubectx/kubens alias completions (fzf-tab compatible)
_comp_kx() {
    local -a contexts
    contexts=(${(f)"$(kubectl config get-contexts --output='name' 2>/dev/null)"})
    _describe 'kube contexts' contexts
}
_comp_ke() {
    local -a namespaces
    namespaces=(${(f)"$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"})
    _describe 'kube namespaces' namespaces
}
compdef _comp_kx kx
compdef _comp_ke ke
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# kubecolor
source <(kubectl completion zsh)
alias kubectl="kubecolor --force-colors"
alias k="kubecolor"
# complete -o default -F __start_kubectl kubecolor
compdef kubecolor=kubectl

# claude
alias ch="claude -p" # headless

export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools
export UV_USE_IO_URING=0
export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH=/Users/gowid/.opencode/bin:$PATH

# Load local machine-specific config (not committed to git)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Tailscale with custom socket (userspace mode)
alias tailscale="tailscale --socket=/Users/gowid/.local/share/tailscale/tailscaled.sock"

# Claude Code OTEL Telemetry (devops-bot usage tracking)
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_ENABLED=true
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative
export OTEL_METRICS_INCLUDE_SESSION_ID=false
export OTEL_RESOURCE_ATTRIBUTES="team=devops,user=jepil.choi@gowid.com"

# OpenClaw Completion
source "/Users/gowid/.openclaw/completions/openclaw.zsh"
