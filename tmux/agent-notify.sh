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
  # terminal-notifier gives a cleaner banner; fall back to osascript if absent.
  # Backgrounded (&) so a hook can never block on the notifier. (macOS locks the
  # banner icon to the posting app; -sender would set the Claude icon but hangs.)
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$1" -message "$2" -sound "$3" >/dev/null 2>&1 &
  else
    /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"$3\"" >/dev/null 2>&1 &
  fi
}

kind="${1:-waiting}"

# The project = the tmux session name (Claude hooks run in the agent's pane).
proj=""
[ -n "${TMUX:-}" ] && proj=$(tmux display-message -p '#S' 2>/dev/null)

case "$kind" in
  finished)
    printf '\a' > /dev/tty 2>/dev/null || true
    if [ -n "$proj" ]; then body="All done in $proj"; else body="All done"; fi
    notify "Claude finished ✅" "$body" "Glass"
    ;;
  waiting)
    printf '\a' > /dev/tty 2>/dev/null || true
    if [ -n "$proj" ]; then body="Waiting for you in $proj"; else body="Waiting for your reply"; fi
    notify "Claude needs you 💬" "$body" "Ping"
    ;;
  bell)
    sess="${2:-}"; win="${3:-}"; cmd="${4:-}"
    # Skip Claude agents — they notify themselves with friendlier messages.
    ver=$(basename "$(readlink "$HOME/.local/bin/claude" 2>/dev/null)" 2>/dev/null)
    { [ -n "$ver" ] && [ "$cmd" = "$ver" ]; } && exit 0
    [ "$win" = "claude" ] && exit 0
    notify "Heads up 🔔" "$sess needs your attention" "Submarine"
    ;;
esac
