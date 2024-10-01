#!/bin/bash

COLOR=$PEACH

sketchybar --add item cpu right \
  --set cpu \
  update_freq=3 \
  icon.color="$COLOR" \
  icon.padding_left=7 \
  label.color="$COLOR" \
  label.padding_right=7 \
  background.height=26 \
  background.corner_radius="$CORNER_RADIUS" \
  background.padding_right=5 \
  background.border_width="$BORDER_WIDTH" \
  background.border_color="$COLOR" \
  background.color="$BAR_COLOR" \
  background.drawing=on \
  script="$PLUGIN_DIR/cpu.sh"

