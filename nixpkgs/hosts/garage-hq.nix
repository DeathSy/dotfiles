# garage-hq: the Mac Studio, the AI hub (../nix-darwin/ai-hub.nix). Added on
# top of the shared config in flake.nix.
{ ... }: {
  imports = [ ../nix-darwin/ai-hub.nix ];

  networking.computerName = "ksotis-hq";

  # A server: no desktop-only apps or settings (nixpkgs/nix-darwin/desktop-extras.nix).
  dotfiles.desktopExtras = false;

  # Trial of herdr (https://herdr.dev), an agent-native terminal multiplexer,
  # alongside tmux, which stays the default. No config or skill yet.
  homebrew.brews = [ "herdr" ];

  home-manager.users.ksotis.imports = [ ../home-manager/ai/headroom.nix ];
}
