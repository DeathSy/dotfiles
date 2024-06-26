export ZSH="/Users/ksotis/.oh-my-zsh"

# Environment variables

export HOMEBREW_NO_AUTO_UPDATE=1

# Setting GoPath
export GOPATH=$(go env GOPATH)
export GOBIN=$GOPATH/bin

export PATH=$PATH:$(go env GOPATH)/bin

export VISUAL=lvim
export EDITOR=lvim

# Setting NVM path
export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# PLUGINS

source ~/dotfiles/antigen/antigen.zsh

antigen init $HOME/dotfiles/.antigenrc

# SPACESHIP TERMINAL THEME FLAG
SPACESHIP_PROMPT_SEPARATE_LINE=true

# tabtab source for packages
# uninstall by removing these lines
[[ -f ~/.config/tabtab/__tabtab.zsh ]] && . ~/.config/tabtab/__tabtab.zsh || true

source ~/dotfiles/.aliasrc
source ~/dotfiles/.secretrc

# pnpm
export PNPM_HOME="/Users/ksotis/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# bun completions
[ -s "/Users/ksotis/.bun/_bun" ] && source "/Users/ksotis/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$HOME/.local/bin":$PATH

neofetch


eval $(thefuck --alias)
eval "$(zoxide init zsh)"
