#!/usr/bin/env bash
# IDE-style explorer sidebar. Lists every tmux session AND every running
# Claude agent (windows named "claude"), with a 🔔 on agents that finished or
# need input. Enter opens the selection; q / Esc hides the sidebar.
set -uo pipefail

CFG="$HOME/.config/tmux"

# field 1 = switch target (session, or session:window for agents)
# field 2+ = what's shown in the list
build_list() {
  tmux list-sessions \
    -F '#{session_name} #{?session_attached,●,○} #{session_name}' 2>/dev/null

  # Detect Claude agents by window name OR by the running command matching the
  # installed claude version (the native binary reports as e.g. "2.1.168"), so
  # agents are found however they were launched. Version is read live from the
  # symlink, so it survives upgrades.
  local ver
  ver=$(basename "$(readlink "$HOME/.local/bin/claude" 2>/dev/null)" 2>/dev/null)
  tmux list-windows -a \
    -f "#{||:#{==:#{window_name},claude},#{==:#{pane_current_command},$ver}}" \
    -F '#{session_name}:#{window_index} 🤖 #{session_name}#{?window_bell_flag, 🔔,}' 2>/dev/null
}

while true; do
  out=$(build_list | fzf --no-sort --reverse --cycle --no-info --with-nth '2..' \
          --prompt ' ⌘ ' --pointer '▸' \
          --color 'bg:-1,gutter:-1,prompt:#cba6f7,pointer:#f5c2e7' \
          --header 'sessions & agents  (⏎ open · q hide)' \
          --bind 'j:down,k:up,ctrl-j:down,ctrl-k:up' \
          --expect 'enter,esc,q') || { "$CFG/ide-toggle.sh"; exit 0; }

  key=$(printf '%s\n' "$out" | sed -n 1p)
  target=$(printf '%s\n' "$out" | sed -n 2p | awk '{print $1}')

  case "$key" in
    enter)
      [ -n "$target" ] || continue
      case "$target" in
        *:*) tmux switch-client -t "${target%%:*}"; tmux select-window -t "$target" ;;
        *)   tmux switch-client -t "$target" ;;
      esac
      ;;
    *) "$CFG/ide-toggle.sh"; exit 0 ;;
  esac
done
