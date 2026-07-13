#!/bin/bash

# Resolve our own dir — the sketchybar daemon's env has no $PLUGIN_DIR.
DIR="$(cd "$(dirname "$0")" && pwd)"

# The 5h token limit is passed as $1 (baked in by the item at add time, since
# CLAUDE_5H_LIMIT is only set in the rc shell, not the daemon env).
label="$(CLAUDE_5H_LIMIT="${1:-0}" /usr/bin/python3 "$DIR/claude_usage.py" 2>/dev/null)"
[ -z "$label" ] && label="—"

sketchybar --set "$NAME" icon="󰚩" label="$label"
