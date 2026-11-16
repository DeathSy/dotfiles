#!/usr/bin/env bash
# prefix+C : jump to this workspace's "claude" tab, or spawn one with a model picker.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
ws="${HERDR_ACTIVE_WORKSPACE_ID:?not running inside herdr}"

tab=$("$herdr" tab list --workspace "$ws" \
  | jq -r 'first(.result.tabs[] | select(.label == "claude") | .tab_id) // empty')
if [ -n "$tab" ]; then
  exec "$herdr" tab focus "$tab"
fi

model=$(printf '%s\n' default opus sonnet haiku \
  | fzf --no-sort --reverse --height 100% \
        --prompt '🤖 model > ' --border-label ' new claude agent ') || exit 0

case "$model" in
  default | '') cmd='claude' ;;
  *)            cmd="claude --model $model" ;;
esac

pane=$("$herdr" tab create --workspace "$ws" --cwd "${HERDR_ACTIVE_PANE_CWD:-$PWD}" \
  --label claude --focus | jq -r '.result.root_pane.pane_id')
# Exit the shell with claude so the tab closes, like the tmux window did.
exec "$herdr" pane run "$pane" "$cmd; exit"
