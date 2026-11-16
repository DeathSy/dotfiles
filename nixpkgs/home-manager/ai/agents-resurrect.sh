#!/usr/bin/env bash
# agents-resurrect: after a reboot or a herdr-core crash, resume the Claude
# Code conversations that ran in herdr terminals. The records come from
# ~/.claude/hooks/herdr-agent-record.sh. Prints the plan unless --yes.
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: agents-resurrect [--yes] [--prune]

Resume the Claude Code conversations that ran in herdr terminals before a
reboot: each recorded terminal that is back as a plain shell gets
`cd <folder> && claude -r <session id>` typed into it. Without --yes it only
prints the plan.

  -y, --yes   type the commands
  --prune     delete the records of gone terminals and stale ones (with or
              without --yes)
  -h, --help  show this help

Skipped: terminals that are gone (the line shows the command to resume by
hand) or run anything but a shell, a conversation recorded in two terminals
(the newest wins), a terminal recreated under the same address (created_ms
differs; the line shows the command), and records older than 30 days, whose
folder is gone or whose transcript is missing. Warns about claude terminals
with keep off, which herdr won't bring back after a reboot (hc keep <t>).
EOF
}

yes=0 prune=0
for a in "$@"; do
  case $a in
    -y | --yes) yes=1 ;;
    --prune) prune=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "agents-resurrect: unknown option: $a" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "agents-resurrect: $*" >&2; exit 1; }
dir=${AGENTS_RESURRECT_DIR:-$HOME/.claude/herdr-agents}
projects=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
max_age_days=30

command -v hc >/dev/null || die "hc (the herdr-core CLI) not found; this only works on a Mac with herdr"
terminals=$(hc ls --json 2>&1) || die "herdr-core isn't answering (hc ls --json: $terminals); start herdr and retry"
jq -e '.terminals | type == "array"' <<<"$terminals" >/dev/null 2>&1 \
  || die "unexpected output from hc ls --json: $terminals"

shopt -s nullglob
files=("$dir"/*.json)
[ ${#files[@]} -gt 0 ] || { echo "agents-resurrect: no recorded agents in $dir"; exit 0; }

line() { printf '%-6s %-8s %s\n' "$1" "$2" "$3"; }

# One row per record, newest first: file, terminal, session id, folder,
# transcript, updated (epoch), created_ms, and the terminal's current agent
# and state. A field with a control character makes the record unreadable
# (an empty row), so a row can never split.
rows=$(for f in "${files[@]}"; do
  if [[ $f == *[[:cntrl:]]* ]]; then line "?" skip "a record in $dir has an unprintable name" >&2; continue; fi
  jq -r --arg f "$f" --argjson ls "$terminals" '
    def clean: tostring | if test("[[:cntrl:]]") then error("control character") else . end;
    (.terminal // "" | clean) as $t
    | ([$ls.terminals[] | select(.address == $t)][0] // {}) as $term
    | [$f, $t, (.session_id // "" | clean), (.cwd // "" | clean),
       (.transcript_path // "" | clean),
       (.updated // "" | try fromdateiso8601 catch 0 | tostring),
       (.created_ms // "" | clean), ($term.agent // "" | clean), ($term.state // "" | clean)]
    | join("\u001f")' "$f" 2>/dev/null || printf '%s\x1f\x1f\x1f\x1f\x1f0\x1f\x1f\x1f\n' "$f"
done | sort -t $'\x1f' -k6,6nr)

now=$(date +%s)
declare -A seen owner
planned=0 failed=0
drop() { # <file> <terminal> <reason>: report a skipped record, delete it with --prune
  if [ "$prune" = 1 ]; then rm -f "$1"; line "$2" pruned "$3"; else line "$2" skip "$3"; fi
}

while IFS=$'\x1f' read -r f t sid cwd transcript updated created agent state; do
  [ -n "$f" ] || continue
  if [[ ! $t =~ ^[A-Za-z0-9_-]+$ ]] || [[ ! $sid =~ ^[A-Za-z0-9-]+$ ]] || [ -z "$cwd" ]; then
    drop "$f" "${t:-?}" "unreadable record $f"; continue
  fi
  # An older record of a terminal already handled (the hook normally deletes those).
  if [ -n "${seen[$t]:-}" ]; then [ "$prune" = 1 ] && rm -f "$f"; continue; fi
  seen[$t]=1
  # The same conversation recorded in two terminals: the newest record wins.
  if [ -n "${owner[$sid]:-}" ]; then drop "$f" "$t" "duplicate: $sid is also in ${owner[$sid]}"; continue; fi
  owner[$sid]=$t
  where=${cwd/#$HOME/\~}
  cmd="cd $(printf '%q' "$cwd") && claude -r $sid"

  if [ -z "$state" ]; then drop "$f" "$t" "terminal gone; to resume by hand: $cmd"; continue; fi
  if [ "$state" != live ]; then line "$t" skip "terminal $state; to resume by hand: $cmd"; continue; fi
  case ${agent#-} in
    zsh | bash | sh | fish) ;;
    *) line "$t" skip "busy: running ${agent:-an unknown program}"; continue ;;
  esac
  age=$(((now - updated) / 86400))
  if [ "$age" -gt "$max_age_days" ]; then drop "$f" "$t" "stale: last started $age days ago in $where"; continue; fi
  [ -d "$cwd" ] || { drop "$f" "$t" "folder gone: $where"; continue; }
  if [ ! -f "$transcript" ]; then
    found=("$projects"/*/"$sid".jsonl)
    [ ${#found[@]} -gt 0 ] || { drop "$f" "$t" "stale: transcript of $sid missing"; continue; }
  fi
  # herdr keeps created_ms when it restores a terminal in place, so a
  # different one means a new terminal under a reused address. Only compared
  # when both are known (older records have none).
  now_created=$(hc get "$t" --json 2>/dev/null | jq -r '.created_ms // empty' 2>/dev/null)
  if [ -n "$created" ] && [ -n "$now_created" ] && [ "$created" != "$now_created" ]; then
    line "$t" skip "terminal $t was recreated (created_ms differs); to resume by hand: $cmd"; continue
  fi

  planned=$((planned + 1))
  if [ "$yes" = 0 ]; then line "$t" resume "$where: claude -r $sid"; continue; fi
  if err=$(hc send "$t" "$cmd" 2>&1 >/dev/null); then
    line "$t" resumed "$where: claude -r $sid"
  else
    failed=$((failed + 1)); line "$t" failed "hc send: $err"
  fi
done <<<"$rows"

# Terminals with keep off don't come back after a reboot, so neither do
# their agents.
nokeep=()
for t in $(jq -r '.terminals[] | select(.agent == "claude-code") | .address' <<<"$terminals"); do
  [[ $t =~ ^[A-Za-z0-9_-]+$ ]] || continue
  [ "$(hc get "$t" --json 2>/dev/null | jq -r '.keep' 2>/dev/null)" = false ] && nokeep+=("$t")
done
if [ ${#nokeep[@]} -gt 0 ]; then
  echo "Warning: keep is off for ${nokeep[*]}: those agents won't come back after a reboot. Run hc keep <t> for each."
fi

if [ "$yes" = 0 ] && [ "$planned" -gt 0 ]; then
  echo "Dry run: nothing typed. Run agents-resurrect --yes to resume $planned agent(s)."
fi
[ "$failed" = 0 ]
