---
name: codex-computer-use
description: Ask Codex CLI (sol) to run local app verification that needs computer use, browser automation, simulators, screenshots, app launching, or independent runtime inspection. This is how sol is invoked for computer-use work. Use when the user asks Claude to have Codex or sol test a flow, verify UI behavior, inspect a running app, capture screenshots, or report confirmation and feedback about implemented behavior.
---

# Codex Computer Use

Use Codex as a separate local verification agent when the task needs real UI interaction, screenshots, simulator/browser/device state, or an independent runtime check outside Claude's current context.

Do not use this for ordinary code reading, typechecking, linting, or tests Claude can run directly. Launching apps, simulators, or browsers to verify the requested work is fine without asking; ask first only if the run could disrupt the user's environment beyond that (closing their apps, changing system settings, acting on real accounts or data).

## Workflow

1. Create a temporary artifact directory.
2. Give Codex a self-contained prompt with the repo path, exact flow, constraints, artifact directory and report format.
3. Run `codex exec` non-interactively.
4. Read Codex's report, inspect or reference screenshot paths, and summarize the result for the user.

Use this command shape:

Pass the sol model explicitly as `-m gpt-6.1-sol`; never rely on the config.toml default. Codex reaches OpenAI through its own `codex login`, not the CLIProxyAPI gateway, so this is the OpenAI model id (the `sol` agent in `~/.claude/agents/sol.md` uses a gateway alias instead). When a newer sol ships, update the id here.

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-cu.XXXXXX")"
REPORT="$ARTIFACT_DIR/report.md"
PROMPT="$ARTIFACT_DIR/prompt.md"


# Write a self-contained prompt to $PROMPT, then run:
codex exec \
  -m gpt-6.1-sol \
  -C "$PWD" \
  --add-dir "$ARTIFACT_DIR" \
  -s danger-full-access \
  -o "$REPORT" \
  - < "$PROMPT"
```

Always pass the prompt on stdin (`- < "$PROMPT"`), never as an argument. Codex reads stdin whenever it isn't a TTY, and under Claude Code's Bash tool stdin is a pipe that never closes, so the argument form hangs forever. A run stuck at `Reading additional input from stdin...` with no activity is this bug: kill it and rerun with stdin.


Use `-s danger-full-access` for GUI automation, iOS simulators, desktop app launching, taking screenshots, or access outside the repo. For non-GUI checks that only need the repo and artifact directory, prefer `-s workspace-write`. Add `--skip-git-repo-check` when the working directory is not a git repository.

## Prompt Requirements

Tell Codex:

- The exact behavior to verify.
- The platform and app type, such as iOS, web, Electron, CLI, or desktop.
- Known launch commands, test credentials, seed data, deep links, or fixtures.
- Whether source edits are allowed. Default to no edits.
- Where screenshots, logs, and the final report should be saved.
- To return pass, fail, or blocked, plus steps performed, observed behavior, screenshot paths, and actionable feedback.

Keep the prompt specific enough that Codex doesn't need the surrounding Claude conversation.

## Running in the background

If you launch codex with Bash `run_in_background`, the completion notice only means the launcher exited, not that codex finished. Append a done-marker and wait on it:

```bash
( codex exec ... ; echo "exit=$?" > "$ARTIFACT_DIR/done" ) 
```

Then wait until `$ARTIFACT_DIR/done` exists (e.g. with Monitor) before reading `$REPORT`. Check that `done` says `exit=0` first: a run codex refused (e.g. the trusted-directory check) writes no report, only console output.
