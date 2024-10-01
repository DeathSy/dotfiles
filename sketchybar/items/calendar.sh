#!/bin/sh

COLOR=$SAPPHIRE

sketchybar --add item calendar right \
  --set calendar \
  update_freq=30 \
  background.corner_radius="$CORNER_RADIUS" \
  icon.padding_left=7 \
  label.padding_right=7 \
  icon.color="$COLOR" \
  label.color="$COLOR" \
  background.height=26 \
  background.padding_right=5 \
  background.border_color="$COLOR" \
  background.color="$BAR_COLOR" \
  background.border_width="$BORDER_WIDTH" \
  background.drawin=on \
  script="$PLUGIN_DIR/calendar.sh"
