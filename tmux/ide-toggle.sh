#!/usr/bin/env bash
# Toggle the IDE session sidebar on/off (prefix + Tab).
set -uo pipefail

if [ "$(tmux show-option -gqv '@ide')" = "1" ]; then
  # Turn off: drop the flag and remove every sidebar pane.
  tmux set-option -gu '@ide'
  tmux list-panes -a -F '#{@sidebar} #{pane_id}' 2>/dev/null \
    | awk '$1=="1" {print $2}' \
    | while read -r p; do tmux kill-pane -t "$p" 2>/dev/null || true; done
else
  # Turn on: set the flag and spawn the sidebar (focused) in the current window.
  tmux set-option -g '@ide' 1
  "$HOME/.config/tmux/ide-ensure.sh" focus
fi
