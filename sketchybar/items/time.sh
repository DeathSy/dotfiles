#!/bin/bash

COLOR=$LAVENDER

sketchybar --add item time right \
  --set time update_freq=1 \
  icon.padding_left=7 \
  icon.color="$COLOR" \
  label.color="$COLOR" \
  label.width=70 \
  align=center \
  background.height=26 \
  background.corner_radius="$CORNER_RADIUS" \
  background.padding_right=2 \
  background.border_width="$BORDER_WIDTH" \
  background.border_color="$COLOR" \
  background.color="$BAR_COLOR" \
  background.drawing=on \
  script="$PLUGIN_DIR/time.sh"

