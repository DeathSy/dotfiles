#!/bin/bash

sketchybar --set "$NAME" icon="" label="$(\ps -A -o %cpu | awk -v n="$(sysctl -n hw.ncpu)" '{s+=$1} END {printf "%.1f%%\n", s/n}')"
