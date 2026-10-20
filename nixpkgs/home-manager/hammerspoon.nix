# Hammerspoon: keyboard window focus and throw-window-to-Space (hammerspoon/init.lua).
# init.lua links to the checkout, not the Nix store, so edits reload live.
{ config, pkgs, ... }:
let
  # `space N` switches to Desktop N of the focused window's display.
  space = pkgs.writeShellScriptBin "space" ''
    case "$1" in
      [1-9]) exec /usr/bin/open -g "hammerspoon://space?n=$1" ;;
      *) echo "usage: space N  (N = 1-9)" >&2; exit 2 ;;
    esac
  '';
in {
  # dotfiles.ai.repoPath is reused on purpose: it is this repo's checkout path.
  home.file.".hammerspoon/init.lua".source =
    config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.ai.repoPath}/hammerspoon/init.lua";

  home.packages = [ space ];
}
