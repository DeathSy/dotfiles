#!/usr/bin/env python3
"""PreToolUse (Bash): refuse process kills that match by pattern.

On 2026-09-29 an agent ran `pkill -f "cat"` to clear one hung `cat`; `-f`
matches the full command line, "cat" is inside "/Applications/…", and 37 GUI
apps were killed. Kill by recorded PID or port owner instead.

Blocks: `pkill -f`, `pkill` without `-x`, `killall -m`, `kill` aimed at -1 or 0,
and `pgrep` without `-x` (or with `-f`) piped into a kill.
"""
import json
import re
import shlex
import sys

ADVICE = (
    'Kill by recorded PID instead: the `$!` of the process you started, a pidfile, '
    'or the port owner (`lsof -ti :PORT -sTCP:LISTEN`; plain `lsof -ti :PORT` also returns clients such as the browser). To find a process by name, list first with '
    '`pgrep -lx <exact-name>` (or `pgrep -lf <pattern>` only to LOOK), check the list, '
    'then `kill <pid>` for the specific PIDs. `pkill -x <exact-name>` and plain '
    '`killall <exact-name>` are allowed.'
)


OPERATORS = {';', '&&', '||', '&', '|', ';;'}


def statements(command):
    """Pipelines as lists of commands, each a token list. Operators inside
    quotes are data, not operators: `grep "pkill -f\\|killall -m"` is one grep."""
    pipelines = []
    for line in command.split('\n'):
        lexer = shlex.shlex(line, posix=True, punctuation_chars=';&|')
        lexer.whitespace_split = True
        try:
            tokens = list(lexer)
        except ValueError:
            tokens = line.split()
        pipeline, current = [], []
        for token in tokens:
            if token in OPERATORS:
                pipeline.append(current)
                current = []
                if token != '|':
                    pipelines.append(pipeline)
                    pipeline = []
            else:
                current.append(token)
        pipeline.append(current)
        pipelines.append(pipeline)
    return [[strip_wrappers(c) for c in p] for p in pipelines]


def strip_wrappers(tokens):
    # Skip env assignments and wrappers before the command itself.
    while tokens and (re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', tokens[0])
                      or tokens[0] in ('sudo', 'command', 'exec', 'nohup', 'time', 'env')):
        tokens = tokens[1:]
    return tokens


def short_flags(args):
    """Single-letter flags, expanded from clusters like -fl."""
    flags = set()
    for a in args:
        if a.startswith('-') and not a.startswith('--') and len(a) > 1 and not a[1:].isdigit():
            flags.update(a[1:])
    return flags


def base(cmd):
    return cmd.rsplit('/', 1)[-1]


def check_segment(tokens):
    if not tokens:
        return None
    cmd, args = base(tokens[0]), tokens[1:]
    if cmd == 'pkill':
        flags = short_flags(args)
        if 'f' in flags or '--full' in args:
            return '`pkill -f` matches the full command line of every process, so a short pattern hits unrelated apps'
        if 'x' not in flags and '--exact' not in args:
            return '`pkill` without `-x` matches any process whose name contains the pattern'
    if cmd == 'killall' and ('m' in short_flags(args)):
        return '`killall -m` matches process names by regex'
    if cmd == 'kill':
        rest = list(args)
        if rest and rest[0] == '-s' and len(rest) > 1:
            rest = rest[2:]
        elif rest and rest[0] == '--':
            rest = rest[1:]
        elif rest and rest[0].startswith('-') and rest[0] not in ('-1',):
            rest = rest[1:]
        elif rest and rest[0] == '-1' and len(rest) > 1:
            rest = rest[1:]  # `kill -1 <pid>` sends SIGHUP to <pid>
        if rest and rest[0] == '--':
            rest = rest[1:]
        if any(t in ('-1', '0') for t in rest):
            return '`kill -1` / `kill 0` signals every process you own or your whole process group'
    return None


def check_pipeline(parts):
    """`pgrep` without -x (or with -f) feeding a kill."""
    seen_loose_pgrep = False
    for tokens in parts:
        if not tokens:
            continue
        cmd, args = base(tokens[0]), tokens[1:]
        if cmd == 'pgrep':
            flags = short_flags(args)
            if 'f' in flags or 'x' not in flags:
                seen_loose_pgrep = True
        elif seen_loose_pgrep and ('kill' in [base(t) for t in tokens]):
            return 'piping a pattern `pgrep` into kill has the same blast radius as `pkill -f`'
    return None


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    command = (data.get('tool_input') or {}).get('command') or ''
    if not re.search(r'\b(pkill|killall|kill|pgrep)\b', command):
        return 0
    reasons = []
    for pipe_parts in statements(command):
        for tokens in pipe_parts:
            r = check_segment(tokens)
            if r:
                reasons.append(r)
        r = check_pipeline(pipe_parts)
        if r:
            reasons.append(r)
    if not reasons:
        return 0
    reason = 'Blocked by the global kill guard (~/.claude/hooks/block-pattern-kill.py): ' + reasons[0] + '. ' + ADVICE
    print(json.dumps({'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': reason,
    }}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
