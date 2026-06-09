#!/usr/bin/env bash
# prefix+e : open the claude-squad agent dashboard in a dedicated "squad"
# window, or jump to it if it's already open. claude-squad manages its own
# tmux sessions per agent and renders them inline, so launching from within
# tmux is fine.
set -euo pipefail

if tmux list-windows -F '#{window_name}' | grep -qx 'squad'; then
  exec tmux select-window -t squad
fi

path=$(tmux display-message -p '#{pane_current_path}')
tmux new-window -n squad -c "$path" 'claude-squad'
