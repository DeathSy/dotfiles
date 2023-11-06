# Fig pre block. Keep at the top of this file.
[[ -f "$HOME/.fig/shell/zshrc.pre.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.pre.zsh"
export ZSH="/Users/ksotis/.oh-my-zsh"

# Environment variables

export HOMEBREW_NO_AUTO_UPDATE=1

# Setting GoPath
export GOPATH=$(go env GOPATH)
export GOBIN=$GOPATH/bin

export PATH=$PATH:$(go env GOPATH)/bin
export FIG_TERM=1

# Setting NVM path
export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# Setting DOCKER_HOST with colima
export DOCKER_HOST="unix:///Users/ksotis/.docker/run/docker.sock"
export DOCKER_BUILDKIT=1

# PLUGINS

source ~/dotfiles/antigen/antigen.zsh

antigen init $HOME/dotfiles/.antigenrc

# tabtab source for packages
# uninstall by removing these lines
[[ -f ~/.config/tabtab/__tabtab.zsh ]] && . ~/.config/tabtab/__tabtab.zsh || true

source ~/dotfiles/.aliasrc
source ~/dotfiles/.secretrc

# Fig post block. Keep at the bottom of this file.
[[ -f "$HOME/.fig/shell/zshrc.post.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.post.zsh"

# pnpm
export PNPM_HOME="/Users/ksotis/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
