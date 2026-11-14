# Desktop-only apps and settings, on unless a host file turns them off
# (garage-hq, a server, does): Vorssaint, Hammerspoon (and `space`), WezTerm
# and its config, desktoppr and the wallpaper, sf-symbols, the system hotkeys,
# Obsidian, LibreOffice, Upscayl and TablePlus. Each stays where it is
# defined, behind this flag; home-manager modules read it through osConfig.
{ lib, ... }: {
  options.dotfiles.desktopExtras = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Install the desktop-only apps and settings listed in nixpkgs/nix-darwin/desktop-extras.nix.";
  };
}
