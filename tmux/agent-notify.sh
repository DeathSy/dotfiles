#!/usr/bin/env bash
# macOS notifications for LLM/agent events in tmux.
#
#   agent-notify.sh finished   # an agent finished        (Claude Code Stop hook)
#   agent-notify.sh waiting    # an agent wants input      (Claude Code Notification hook)
#   agent-notify.sh bell <session> <window> <command>     (tmux alert-bell hook)
#
# The finished/waiting calls run inside the agent's tmux pane, so they also ring
# the bell to flag the window (🔔) in the status bar. The generic bell handler
# skips Claude windows, since those already notify via the hooks above.
set -uo pipefail

notify() { # title  body  sound
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"$3\"" 2>/dev/null || true
}

kind="${1:-waiting}"

# Current tmux location (Claude hooks run in the agent's pane).
loc=""
[ -n "${TMUX:-}" ] && loc=$(tmux display-message -p '#S:#W' 2>/dev/null)

case "$kind" in
  finished)
    printf '\a' > /dev/tty 2>/dev/null || true
    notify "✅ Claude finished" "${loc:-claude} is done" "Glass"
    ;;
  waiting)
    printf '\a' > /dev/tty 2>/dev/null || true
    notify "🔔 Claude needs you" "${loc:-claude} is waiting for input" "Ping"
    ;;
  bell)
    sess="${2:-}"; win="${3:-}"; cmd="${4:-}"
    # Skip Claude agents — they notify themselves with precise messages.
    ver=$(basename "$(readlink "$HOME/.local/bin/claude" 2>/dev/null)" 2>/dev/null)
    { [ -n "$ver" ] && [ "$cmd" = "$ver" ]; } && exit 0
    [ "$win" = "claude" ] && exit 0
    notify "🔔 ${sess}:${win}" "needs your attention" "Submarine"
    ;;
esac
