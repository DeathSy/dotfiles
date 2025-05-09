{ config, pkgs, lib, ... }:
{
  services.sketchybar = {
    enable = true;
    config = ''
      #!/bin/bash

      source "$HOME/.config/sketchybar/colors.sh"

      export ITEM_DIR="$HOME/.config/sketchybar/items"
      export PLUGIN_DIR="$HOME/.config/sketchybar/plugins"
      export FONT="Hack Nerd Font Mono"
      export CORNER_RADIUS=30
      export BORDER_WIDTH=2

      sketchybar --bar \
        height=30 \
        color=$TRANSPARENT \
        position=top \
        sticky=on \
        padding_right=0 \
        padding_left=3 \
        corner_radius=$CORNER_RADIUS \
        y_offset=5 \
        margin=5 \
        blur_radius=20 \
        notch_width=200 \
        --default updates=when_shown \
        icon.font="$FONT:Bold:17.0" \
        icon.color="$TEXT" \
        icon.padding_left=3 \
        icon.padding_right=3 \
        background.padding_left=3 \
        background.padding_right=3 \
        label.font="$FONT:Bold:13.0"

      source "$ITEM_DIR/aerospace.sh"
      source "$ITEM_DIR/front_app.sh"

      source "$ITEM_DIR/time.sh"
      source "$ITEM_DIR/calendar.sh"
      source "$ITEM_DIR/cpu.sh"
      source "$ITEM_DIR/battery.sh"

      sketchybar --update
    '';
  };
}
