# garage-hq: the Mac Studio, the AI hub (../nix-darwin/ai-hub.nix). Added on
# top of the shared config in flake.nix.
{ inputs, ... }: {
  imports = [ ../nix-darwin/ai-hub.nix ];

  networking.computerName = "ksotis-hq";

  # A server: no desktop-only apps or settings (nixpkgs/nix-darwin/desktop-extras.nix).
  dotfiles.desktopExtras = false;

  # Trial of herdr (https://herdr.dev), an agent-native terminal multiplexer,
  # alongside tmux, which stays the default. Keybindings: ../home-manager/herdr.nix.
  # herdr-core (`hc`, the runtime the Herdr phone/desktop app connects to over
  # SSH) has no formula: it comes from https://releases.herdr.dev/core/install.sh
  # into ~/.local and updates itself with `hc update`.
  homebrew.brews = [ "herdr" ];

  # Google Antigravity (agent IDE). Installed with `brew install --cask` on
  # 2026-11-22, before it was declared. It updates itself (auto_updates).
  homebrew.casks = [ "antigravity" ];

  home-manager.users.ksotis.imports = [
    ../home-manager/ai/hermes.nix
    ../home-manager/ai/headroom.nix
    ../home-manager/herdr.nix
    ../home-manager/rpa-tunnel.nix
  ];
}
