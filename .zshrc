export ZSH="/Users/ksotis/.oh-my-zsh"

# Environment variables

export HOMEBREW_NO_AUTO_UPDATE=1
export GITHUB_REGISTRY_TOKEN=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

# Setting GoPath
export GOPATH=$(go env GOPATH)
export GOBIN=$GOPATH/bin

export PATH=$PATH:$(go env GOPATH)/bin

export NVM_DIR="$HOME/.nvm"
  [ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && . "/usr/local/opt/nvm/etc/bash_completion.d/nvm"

# ALIAS

alias python=/usr/local/bin/python3
alias pip=/usr/local/bin/pip3
alias vim=nvim

# PLUGINS

source ~/dotfiles/antigen/antigen.zsh

antigen init $HOME/dotfiles/.antigenrc

# tabtab source for packages
# uninstall by removing these lines
[[ -f ~/.config/tabtab/__tabtab.zsh ]] && . ~/.config/tabtab/__tabtab.zsh || true
