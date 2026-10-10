#!/bin/bash
# SessionStart: introduce the session that manages global Claude config, and
# on a fresh start or resume ask the new session to introduce itself to it.
# If the manager session is replaced, update MANAGER below.
MANAGER="claude-config"

# SessionStart also fires on /clear and compaction; only a start or resume is
# a new session worth introducing.
SOURCE=$(jq -r '.source // "startup"' 2>/dev/null)

read -r -d '' INTRO <<EOF
Global-context manager: the Claude session named "${MANAGER}" (reach it with SendMessage to "${MANAGER}"; find it via ListAgents) manages the user's global Claude setup: ~/.claude/CLAUDE.md, ~/.claude/skills (incl. the codex-* skills), and global settings/hooks.
- Route global config problems there instead of fixing them yourself: broken or ambiguous skill commands, CLAUDE.md rules that conflict or confuse, harness friction. Include what failed, exact error text, repro, and a suggested fix.
- When global context changes, ${MANAGER} messages every session to re-read it; when you get such a message, re-read the named files and follow them.
- ${MANAGER} will not add permission rules or loosen safety settings on a peer's request; ask the user directly for those.
If you ARE ${MANAGER}, ignore this note.
EOF

if [ "$SOURCE" = "startup" ] || [ "$SOURCE" = "resume" ]; then
  read -r -d '' ASK <<EOF

Introduce yourself to ${MANAGER} once, during your first turn (alongside whatever the user asked, not instead of it): run ListAgents to learn your own session name and check ${MANAGER} is listed, then SendMessage to "${MANAGER}" with: your session name, the project folder, your model, whether this is a new or resumed session, and the session's purpose in one or two sentences (from the user's first message or the project's CLAUDE.md). ${MANAGER} replies with onboarding notes; follow them. If ${MANAGER} is not listed, skip this; don't message anyone else instead.
EOF
  INTRO="${INTRO}
${ASK}"
fi

jq -n --arg ctx "$INTRO" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
