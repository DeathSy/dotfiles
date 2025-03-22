#!/bin/bash

sketchybar --add event aerospace_workspace_change

for sid in $(aerospace list-workspaces --all); do
  sketchybar --add item space.$sid left \
    --subscribe space.$sid aerospace_workspace_change \
    --set space.$sid \
    background.color=0x44ffffff \
    background.corner_radius=10 \
    background.height=20 \
    background.drawing=off \
    click_script="aerospace workspace $sid" \
    script="$CONFIG_DIR/plugins/aerospace.sh $sid"
done

sketchybar --add item spacer.2 left \
  --set spacer.2 background.drawing=off \
  label.drawing=off \
  icon.drawing=off \
  width=5

sketchybar --add bracket spaces '/space.*/' \
  --set spaces background.border_width="$BORDER_WIDTH" \
  background.border_color="$RED" \
  background.corner_radius="$CORNER_RADIUS" \
  background.color="$BAR_COLOR" \
  background.height=26 \
  background.drawing=on

sketchybar --add item separator left \
  --set separator icon="" \
  icon.font="$FONT:Bold:16.8" \
  background.padding_left=10 \
  background.padding_right=7 \
  label.drawing=off \
  associated_display=active \
  icon.color="$TEXT"
