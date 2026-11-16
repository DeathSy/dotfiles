#!/bin/bash
# SessionStart / SessionEnd: remember which Claude Code conversation runs in
# each herdr terminal, so `agents-resurrect` can resume it after a reboot
# (herdr brings kept terminals back as plain shells and never re-runs them).
#
# One file per terminal and session: <dir>/<terminal>.<session_id>.json.
# SessionStart (any source: /clear, compaction and forks change the id) writes
# it and drops the terminal's older ones; SessionEnd removes its own. A reboot
# fires no SessionEnd, so the record survives exactly then.
#
# Only the terminal's own foreground claude counts: an agent's `claude -p`
# (or an SDK run, or a background fork) inherits HC_TERMINAL_ID, so starts
# from those are skipped: a non-interactive entrypoint, a subagent, or a
# process that herdr doesn't report as the terminal's foreground program.
# Silent, never blocks, always exits 0. AGENTS_RESURRECT_DIR overrides the
# directory (for tests).
t=${HC_TERMINAL_ID:-}
[[ $t =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

input=$(cat)
IFS=$'\x1f' read -r event sid agent < <(jq -r \
  '[.hook_event_name, .session_id, .agent_id] | map(. // "" | tostring) | join("\u001f")' \
  <<<"$input" 2>/dev/null)
[[ $sid =~ ^[A-Za-z0-9-]+$ ]] || exit 0

dir=${AGENTS_RESURRECT_DIR:-$HOME/.claude/herdr-agents}
own="$dir/$t.$sid.json"

case $event in
  SessionEnd) rm -f "$own"; exit 0 ;;
  SessionStart) ;;
  *) exit 0 ;;
esac

[ "${CLAUDE_CODE_ENTRYPOINT:-}" = cli ] && [ -z "$agent" ] || exit 0
hc=$(command -v hc || echo "$HOME/.local/bin/hc")
if [ -x "$hc" ]; then
  fg=$("$hc" get "$t" --json 2>/dev/null | jq -r '.foreground.pid // empty' 2>/dev/null)
  # Unknown (hc down, no foreground) still records; a different pid doesn't.
  [ -z "$fg" ] || [ "$fg" = "${CLAUDE_PID:-}" ] || [ "$fg" = "$PPID" ] || exit 0
fi

umask 077
mkdir -p "$dir" && chmod 700 "$dir" || exit 0
tmp=$(mktemp "$dir/.$t.XXXXXX") || exit 0
if jq -c --arg t "$t" \
  '{terminal: $t, session_id, cwd, transcript_path, updated: (now | todate)}' \
  <<<"$input" >"$tmp" 2>/dev/null && mv -f "$tmp" "$own"; then
  for f in "$dir/$t".*.json; do [ "$f" = "$own" ] || rm -f "$f"; done
else
  rm -f "$tmp"
fi
exit 0
