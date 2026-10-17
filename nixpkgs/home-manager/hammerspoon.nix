# Hammerspoon: keyboard window focus and throw-window-to-Space (hammerspoon/init.lua).
# init.lua links to the checkout, not the Nix store, so edits reload live.
{ config, pkgs, ... }:
let
  # `space N` switches to Desktop N, `space throw N` moves the focused window there.
  space = pkgs.writeShellScriptBin "space" ''
    action=space
    if [ "$1" = throw ]; then action=throw; shift; fi
    case "$1" in
      [1-9]) exec /usr/bin/open -g "hammerspoon://$action?n=$1" ;;
      *) echo "usage: space [throw] N  (N = 1-9)" >&2; exit 2 ;;
    esac
  '';
in {
  home.file.".hammerspoon/init.lua".source =
    config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.ai.repoPath}/hammerspoon/init.lua";

  home.packages = [ space ];
}
