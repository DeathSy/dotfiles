# garage-server: the server Mac. Added on top of the shared config in flake.nix.
# A gateway client like garage since garage-hq took over the AI hub
# (docs/ai-setup.md). It still never sleeps: other Macs reach the services it
# hosts over Tailscale.
{ ... }: {
  imports = [ ../nix-darwin/never-sleep.nix ];

  networking.computerName = "ksotis-server";

  # A headless runtime box: no desktop-only apps or settings
  # (nixpkgs/nix-darwin/desktop-extras.nix).
  dotfiles.desktopExtras = false;

  home-manager.users.ksotis.imports = [
    ../home-manager/node-exporter.nix
    ../home-manager/podman-exporter.nix
  ];
}
