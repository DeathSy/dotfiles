#!/bin/bash

label="$(/usr/bin/python3 "$PLUGIN_DIR/claude_usage.py" 2>/dev/null)"
[ -z "$label" ] && label="—"
sketchybar --set "$NAME" icon="󰚩" label="$label"
