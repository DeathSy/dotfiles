# herdr (https://herdr.dev) keybindings ported from tmux.nix, plus the prefix+C
# agent popup script. Imported by hosts that install herdr (garage-hq).
# Linked to the checkout, not the Nix store: herdr's settings screen writes to
# config.toml, and `prefix+r` reloads edits without a rebuild.
{ config, ... }:
let
  link = p: config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.ai.repoPath}/herdr/${p}";
in {
  home.file.".config/herdr/config.toml".source = link "config.toml";
  home.file.".config/herdr/scripts/agent.sh".source = link "agent.sh";
}
