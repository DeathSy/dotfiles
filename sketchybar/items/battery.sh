#!/bin/bash

COLOR=$GREEN

sketchybar --add item battery right \
  --set battery \
  update_freq=60 \
  icon.color="$COLOR" \
  icon.padding_left=7 \
  label.color="$COLOR" \
  label.padding_right=7 \
  background.height=26 \
  background.color="$BAR_COLOR" \
  background.corner_radius="$CORNER_RADIUS" \
  background.padding_right=5 \
  background.border_width="$BORDER_WIDTH" \
  background.border_color="$COLOR" \
  background.drawing=on \
  script="$PLUGIN_DIR/battery.sh" \
  --subscribe battery power_source_change

