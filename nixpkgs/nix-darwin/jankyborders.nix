# JankyBorders: highlight the focused window. Same style as before AeroSpace
# was removed.
{ ... }: {
  services.jankyborders = {
    enable = true;
    style = "round";
    hidpi = false;
    active_color = "0xc0e2e2e3";
    inactive_color = "0xc02c2e34";
    background_color = "0x302c2e34";
    width = 6.0;
  };
}
