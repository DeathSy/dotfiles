#!/usr/bin/env bash
# prefix+C : jump to this session's Claude agent window, or spawn a new one
# with a quick model picker. The agent window is always named "claude".
set -euo pipefail

# Already have an agent in this session? Just jump to it.
if tmux list-windows -F '#{window_name}' | grep -qx 'claude'; then
  exec tmux select-window -t claude
fi

path=$(tmux display-message -p '#{pane_current_path}')

model=$(printf '%s\n' default opus sonnet haiku \
  | fzf --no-sort --reverse --height 100% \
        --prompt '🤖 model > ' --border-label ' new claude agent ') || exit 0

case "$model" in
  default | '') cmd='claude' ;;
  *)            cmd="claude --model $model" ;;
esac

tmux new-window -n claude -c "$path" "$cmd"
