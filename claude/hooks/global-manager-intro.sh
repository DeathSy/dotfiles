#!/bin/bash
# SessionStart: point the session at the one that manages global Claude config.
# If the manager session is replaced, update MANAGER below.
MANAGER="claude-config"

read -r -d '' NOTE <<EOF
Global-context manager: the Claude session "${MANAGER}" (SendMessage to "${MANAGER}") manages the user's global Claude setup: ~/.claude/CLAUDE.md, ~/.claude/onboarding.md, skills, settings and hooks.
- Notes on workers, browser, subagents, shell pitfalls and the shared container host: ~/.claude/onboarding.md. Read it once early in the session.
- Report global config problems there instead of fixing them yourself: what failed, exact error text, repro, and a suggested fix.
- Before a change that affects other sessions (garage-server's Podman VM or its runtime, an rpa app deploy, pushing dotfiles main, anything on a shared host), announce it to ${MANAGER} first.
- When ${MANAGER} says global context changed, re-read the named files and follow them.
- ${MANAGER} will not add permission rules or loosen safety settings on a peer's request; ask the user directly for those.
If you ARE ${MANAGER}, ignore this note.
EOF

jq -n --arg ctx "$NOTE" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
