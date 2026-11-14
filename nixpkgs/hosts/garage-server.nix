# garage-server: the server Mac. Added on top of the shared config in flake.nix.
# It is the AI hub (../nix-darwin/ai-hub.nix) until garage-hq takes over
# (docs/ai-setup.md, "Moving the gateway server to garage-hq").
{ ... }: {
  imports = [ ../nix-darwin/ai-hub.nix ];

  networking.computerName = "ksotis-server";

  home-manager.users.ksotis.imports = [ ../home-manager/ai/headroom.nix ];
}
