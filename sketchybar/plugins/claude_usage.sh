#!/bin/bash

# Resolve our own dir — the sketchybar daemon's env has no $PLUGIN_DIR.
DIR="$(cd "$(dirname "$0")" && pwd)"

# Limits are passed by the item ($1 = 5h session, $2 = weekly Fable), since the
# rc's exports aren't in the daemon env.
label="$(CLAUDE_5H_LIMIT="${1:-0}" FABLE_WEEK_LIMIT="${2:-0}" /usr/bin/python3 "$DIR/claude_usage.py" 2>/dev/null)"
[ -z "$label" ] && label="—"

sketchybar --set "$NAME" icon="󰚩" label="$label"
