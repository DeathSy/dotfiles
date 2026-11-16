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

Skipped: terminals that are gone or run anything but a shell, and records
older than 30 days, whose folder is gone or whose transcript is missing.
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

# One row per record, newest first: file, terminal, session id, folder,
# transcript, updated (epoch), and the terminal's current agent and state.
rows=$(for f in "${files[@]}"; do
  jq -r --arg f "$f" --argjson ls "$terminals" '
    (.terminal // "" | tostring) as $t
    | ([$ls.terminals[] | select(.address == $t)][0] // {}) as $term
    | [$f, $t, (.session_id // "" | tostring),
       (.cwd // "" | tostring | if test("[[:cntrl:]]") then "" else . end),
       (.transcript_path // "" | tostring),
       (.updated // "" | try fromdateiso8601 catch 0 | tostring),
       ($term.agent // ""), ($term.state // "")]
    | join("\u001f")' "$f" 2>/dev/null || printf '%s\x1f\x1f\x1f\x1f\x1f0\x1f\x1f\n' "$f"
done | sort -t $'\x1f' -k6,6nr)

now=$(date +%s)
declare -A seen
planned=0 failed=0
line() { printf '%-6s %-8s %s\n' "$1" "$2" "$3"; }
drop() { # <file> <terminal> <reason>: report a skipped record, delete it with --prune
  if [ "$prune" = 1 ]; then rm -f "$1"; line "$2" pruned "$3"; else line "$2" skip "$3"; fi
}

while IFS=$'\x1f' read -r f t sid cwd transcript updated agent state; do
  if [ -z "$t" ] || [[ ! $sid =~ ^[A-Za-z0-9-]+$ ]] || [ -z "$cwd" ]; then
    drop "$f" "${t:-?}" "unreadable record $f"; continue
  fi
  # An older record of a terminal already handled (the hook normally deletes those).
  if [ -n "${seen[$t]:-}" ]; then [ "$prune" = 1 ] && rm -f "$f"; continue; fi
  seen[$t]=1
  where=${cwd/#$HOME/\~}

  if [ -z "$state" ]; then drop "$f" "$t" "terminal gone (was $where)"; continue; fi
  if [ "$state" != live ]; then line "$t" skip "terminal $state"; continue; fi
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

  cmd="cd $(printf '%q' "$cwd") && claude -r $sid"
  planned=$((planned + 1))
  if [ "$yes" = 0 ]; then line "$t" resume "$where: claude -r $sid"; continue; fi
  if err=$(hc send "$t" "$cmd" 2>&1 >/dev/null); then
    line "$t" resumed "$where: claude -r $sid"
  else
    failed=$((failed + 1)); line "$t" failed "hc send: $err"
  fi
done <<<"$rows"

if [ "$yes" = 0 ] && [ "$planned" -gt 0 ]; then
  echo "Dry run: nothing typed. Run agents-resurrect --yes to resume $planned agent(s)."
fi
[ "$failed" = 0 ]
