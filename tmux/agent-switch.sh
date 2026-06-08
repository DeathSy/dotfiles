#!/usr/bin/env bash
# prefix+A : fuzzy-pick a running Claude agent across ALL sessions and switch.
# 🔔 marks windows that rang the bell (agent finished / is waiting on you).
set -euo pipefail

target=$(tmux list-windows -a \
    -F '#{session_name}:#{window_index} #{session_name} → #{window_name}#{?window_bell_flag, 🔔 needs-you,}' \
  | grep -i 'claude' \
  | fzf --with-nth 2.. --no-sort --reverse --height 100% \
        --prompt '🤖 agents > ' --border-label ' running claude agents ' \
  | awk '{print $1}') || exit 0

[ -n "${target:-}" ] && tmux switch-client -t "$target"
