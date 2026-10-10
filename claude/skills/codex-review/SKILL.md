---
name: codex-review
description: Ask Codex CLI (sol) for an independent code review of uncommitted changes, a branch diff, a commit, or a specific implementation. This is how sol is invoked for a review work. Use when the user asks Claude to have Codex or sol review perspective, or when Codex should audit a diff, find bugs or regressions, or compare Claude's implementation against requirements. For a review by Claude itself, use the normal review process instead.
---

# Codex review

Use Codex as an independent reviewer when the user wants a second-pass review or when a change is broad enough that another agent's perspective is useful.

Prefer Claude's normal review process for small local checks. Do not delegate review just to avoid reading the code yourself. Treat codex's output as evidence, not authority.

## Workflow

1. Identify the review target: uncommitted changes, base branch, commit SHA, PR checkout, or specific files.
2. Create a temporary artifact directory for the Codex report
3. Run the review with `codex exec` in a read-only sandbox, naming the target in the prompt.
4. Read Codex's report and verify important claims against the code before presenting them.

`<sol>` is the sol model ID pinned in `~/.claude/CLAUDE.md` (never rely on the config.toml default). Every codex call must pass it (`-m <sol>` for `exec`, `-c model="<sol>"` for `review`). If you can't find the pinned `sol = ...` line in CLAUDE.md, stop and ask the user instead of running codex with no model set.

`codex review` accepts EITHER a target flag (`--uncommitted` / `--base` / `--commit`) OR a custom prompt, never both. Since reviews here always carry a custom prompt, use `codex exec` and put the target in the prompt text (e.g. "Review the output of `git diff main...HEAD`" or "Review the uncommitted changes (`git diff HEAD` plus untracked files)"):

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-review.XXXXXX")"
REPORT="$ARTIFACT_DIR/report.md"
PROMPT="$ARTIFACT_DIR/prompt.md"

# Write the review prompt (target + instructions) to $PROMPT, then run:
codex exec -m <sol> -s read-only -C "$PWD" -o "$REPORT" - < "$PROMPT"
```

Only for a plain review with no custom instructions: `codex -C "$PWD" review -c model="<sol>" --base main > "$REPORT"`.

Add `--skip-git-repo-check` when the working directory is not a git repository (e.g. a parent folder holding several repos); without it codex refuses with "Not inside a trusted directory".

## Review Prompt

Ask Codex to use code-review stance:

```text
Review these changes for bugs, regressions, missing tests, security issues, and requirement mismatches.

Prioritize findings over summary. For each finding include:
- severity
- file and line reference
- concrete failure mode
- suggested fix direction

Do not edit files. If there are no substantive findings, say no and name any residual test gaps.

```

Add task-specific context when useful: requirements, risky areas, expected behaviour, relevant tests, or files Claude is unsure about.

## Reporting Back

Before relaying a Codex finding, inspect the cited code or diff enough to decide whether the finding is real. In the user-facing response, separate confirmed issues from Codex suggestions you did not verify.

If Codex finds nothing, say that clearly and mention what review target it inspected.

If `codex` is not installed or the command fails, report the error and offer to review the changes directly instead.

## Running in the background

If you launch codex with Bash `run_in_background`, the completion notice only means the launcher exited, not that codex finished. Append a done-marker and wait on it:

```bash
( codex exec ... ; echo "exit=$?" > "$ARTIFACT_DIR/done" ) 
```

Then wait until `$ARTIFACT_DIR/done` exists (e.g. with Monitor) before reading `$REPORT`. Check that `done` says `exit=0` first: a run codex refused (e.g. the trusted-directory check) writes no report, only console output.
