export ZSH="/Users/ksotis/.oh-my-zsh"

# Environment variables

export HOMEBREW_NO_AUTO_UPDATE=1

# ALIAS

alias python=/usr/local/bin/python3
alias pip=/usr/local/bin/pip3

# PLUGINS

source /usr/local/share/antigen/antigen.zsh

antigen init $HOME/dotfiles/.antigenrc

# INITIAL SHELL 

if [[ "$TERM" != "screen-256color" ]] then
  tmux attach-session -t workspace || tmux new-session -s workspace -c ~/workspace -n main
fi
