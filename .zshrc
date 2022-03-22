# Fig pre block. Keep at the top of this file.
export PATH="${PATH}:${HOME}/.local/bin"
eval "$(fig init zsh pre)"

export ZSH="/Users/ksotis/.oh-my-zsh"

# Environment variables

export HOMEBREW_NO_AUTO_UPDATE=1
export GITHUB_REGISTRY_TOKEN=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

# Setting GoPath
export GOPATH=$(go env GOPATH)
export GOBIN=$GOPATH/bin

export PATH=$PATH:$(go env GOPATH)/bin

# Setting NVM path
export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# Setting DOCKER_HOST with colima
export DOCKER_HOST="unix://$HOME/.colima/docker.sock"

# ALIAS

alias python=/usr/local/bin/python3
alias pip=/usr/local/bin/pip3
alias vim=nvim
alias act="act --container-architecture linux/amd64"

# PLUGINS

source ~/dotfiles/antigen/antigen.zsh

antigen init $HOME/dotfiles/.antigenrc

# tabtab source for packages
# uninstall by removing these lines
[[ -f ~/.config/tabtab/__tabtab.zsh ]] && . ~/.config/tabtab/__tabtab.zsh || true

# Fig post block. Keep at the bottom of this file.
eval "$(fig init zsh post)"

