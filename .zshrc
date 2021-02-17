export ZSH="/Users/ksotis/.oh-my-zsh"

# Environment variables

export HOMEBREW_NO_AUTO_UPDATE=1

export NVM_DIR="$HOME/.nvm"
  [ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && . "/usr/local/opt/nvm/etc/bash_completion.d/nvm"

# ALIAS

alias python=/usr/local/bin/python3
alias pip=/usr/local/bin/pip3
alias vim=nvim

# PLUGINS

source /usr/local/share/antigen/antigen.zsh

antigen init $HOME/dotfiles/.antigenrc

# INITIAL SHELL 

if [[ "$TERM" != "screen-256color" ]] then
  tmux attach-session -t workspace || tmux new-session -s workspace -c ~/workspace -n main
fi

# tabtab source for packages
# uninstall by removing these lines
[[ -f ~/.config/tabtab/__tabtab.zsh ]] && . ~/.config/tabtab/__tabtab.zsh || true
