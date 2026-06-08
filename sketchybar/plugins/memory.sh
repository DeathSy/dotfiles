#!/bin/bash

sketchybar --set "$NAME" icon="󰍛" label="$(memory_pressure 2>/dev/null | awk '/free percentage/ {gsub(/%/,"",$NF); printf "%d%%\n", 100-$NF}')"
