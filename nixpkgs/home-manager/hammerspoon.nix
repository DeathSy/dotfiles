# Hammerspoon: keyboard window focus and virtual workspaces (hammerspoon/).
# init.lua links to the checkout, not the Nix store, so edits reload live; it
# loads workspaces.lua from the same directory.
{ config, pkgs, ... }:
let
  # `space N` does what ⌃N does; `space unpark` brings every window back.
  space = pkgs.writeShellScriptBin "space" ''
    case "$1" in
      [1-9]) exec /usr/bin/open -g "hammerspoon://space?n=$1" ;;
      unpark) exec /usr/bin/open -g "hammerspoon://space?unpark=1" ;;
      *) echo "usage: space N (N = 1-9) | space unpark" >&2; exit 2 ;;
    esac
  '';
in {
  # dotfiles.ai.repoPath is reused on purpose: it is this repo's checkout path.
  home.file.".hammerspoon/init.lua".source =
    config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.ai.repoPath}/hammerspoon/init.lua";

  home.packages = [ space ];
}
