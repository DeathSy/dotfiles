# JankyBorders: only the focused window has a border; no background fill.
{ config, ... }: {
  services.jankyborders = {
    enable = true;
    style = "round";
    hidpi = false;
    active_color = "0xc0e2e2e3";
    inactive_color = "0x00000000";
    width = 6.0;
  };

  # Hammerspoon restores this colour after Mission Control closes.
  environment.etc."hammerspoon-borders.lua".text =
    "return ${builtins.toJSON config.services.jankyborders.active_color}\n";
}
