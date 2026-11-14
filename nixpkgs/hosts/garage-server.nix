# garage-server: the server Mac. Added on top of the shared config in flake.nix.
# A gateway client like garage since garage-hq took over the AI hub
# (docs/ai-setup.md). It still never sleeps: other Macs reach the services it
# hosts over Tailscale.
{ ... }: {
  imports = [ ../nix-darwin/never-sleep.nix ];

  networking.computerName = "ksotis-server";
}
