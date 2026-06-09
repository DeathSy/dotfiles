#!/usr/bin/env bash
# prefix+A : fuzzy-pick a running Claude agent across ALL sessions and switch.
# Agents are found by window name OR by the running command matching the
# installed claude version (native binary reports as e.g. "2.1.168"), so they
# are detected however they were launched. 🔔 marks ones waiting on you.
set -uo pipefail

ver=$(basename "$(readlink "$HOME/.local/bin/claude" 2>/dev/null)" 2>/dev/null)

target=$(tmux list-windows -a \
    -f "#{||:#{==:#{window_name},claude},#{==:#{pane_current_command},$ver}}" \
    -F '#{session_name}:#{window_index} #{session_name} → #{window_name}#{?window_bell_flag, 🔔 needs-you,}' \
  | fzf --with-nth '2..' --no-sort --reverse --height 100% \
        --prompt '🤖 agents > ' --border-label ' running claude agents ' \
  | awk '{print $1}') || exit 0

if [ -n "${target:-}" ]; then
  tmux switch-client -t "${target%%:*}"
  tmux select-window -t "$target"
fi
