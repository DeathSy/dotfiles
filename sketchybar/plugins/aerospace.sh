#!/usr/bin/env bash

source "$HOME/.config/sketchybar/colors.sh" # Loads all defined colors

if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME icon.color="$RED" \
      icon="$1"
else
    sketchybar --set $NAME icon.color="$TEXT" \
      icon="$1"
fi

