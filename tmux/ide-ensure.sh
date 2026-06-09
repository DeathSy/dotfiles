#!/usr/bin/env bash
# Keep exactly one IDE sidebar pane in the CURRENT window (and none elsewhere).
# Called on toggle-on and from the session/window hooks so the sidebar
# "follows" you across sessions, giving a persistent-feeling left panel.
set -uo pipefail

[ "$(tmux show-option -gqv '@ide')" = "1" ] || exit 0

win=$(tmux display-message -p '#{window_id}')

# Remove any sidebars left behind in other windows.
tmux list-panes -a -F '#{@sidebar} #{window_id} #{pane_id}' 2>/dev/null \
  | awk -v w="$win" '$1=="1" && $2!=w {print $3}' \
  | while read -r p; do tmux kill-pane -t "$p" 2>/dev/null || true; done

# Already a sidebar in this window? Then we're done.
if tmux list-panes -F '#{@sidebar}' 2>/dev/null | grep -qx '1'; then
  exit 0
fi

main=$(tmux display-message -p '#{pane_id}')

# Spawn the sidebar as a FULL-HEIGHT left column (-f spans the whole window,
# not just the active pane). -d so creation doesn't steal focus.
sb=$(tmux split-window -f -h -b -d -l 30 -P -F '#{pane_id}' -t "$main" \
  "$HOME/.config/tmux/ide-sidebar.sh" 2>/dev/null) || exit 0
tmux set-option -p -t "$sb" '@sidebar' 1

# Focus the sidebar only when explicitly toggled on (not when it follows you).
[ "${1:-}" = "focus" ] && tmux select-pane -t "$sb"
