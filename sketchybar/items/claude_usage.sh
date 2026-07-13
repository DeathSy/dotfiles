#!/bin/bash

COLOR=$LAVENDER

sketchybar --add item claude_usage right \
  --set claude_usage \
  update_freq=120 \
  icon.color="$COLOR" \
  icon.padding_left=7 \
  label.color="$COLOR" \
  label.padding_right=7 \
  label.font="$FONT:Bold:12.0" \
  background.height=26 \
  background.corner_radius="$CORNER_RADIUS" \
  background.padding_right=5 \
  background.border_width="$BORDER_WIDTH" \
  background.border_color="$COLOR" \
  background.color="$BAR_COLOR" \
  background.drawing=on \
  script="$PLUGIN_DIR/claude_usage.sh $CLAUDE_5H_LIMIT"
