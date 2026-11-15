# garage-hq: the Mac Studio that takes over the AI hub (../nix-darwin/ai-hub.nix)
# from garage-server. Added on top of the shared config in flake.nix.
{ ... }: {
  imports = [ ../nix-darwin/ai-hub.nix ];

  networking.computerName = "ksotis-hq";

  # A server: no desktop-only apps or settings (nixpkgs/nix-darwin/desktop-extras.nix).
  dotfiles.desktopExtras = false;

  # Trial of herdr (https://herdr.dev), an agent-native terminal multiplexer,
  # alongside tmux, which stays the default. No config or skill yet.
  homebrew.brews = [ "herdr" ];

  home-manager.users.ksotis = {
    imports = [ ../home-manager/ai/headroom.nix ];

    # Until the cutover (docs/ai-setup.md, "Moving the gateway server to
    # garage-hq") garage-server owns the workstation's port 18317, so this
    # gateway doesn't open Open Design's reverse tunnel.
    dotfiles.ai.openDesign.gatewayTunnel = false;
    # Nor does Homebrew start its cliproxyapi: step 3 starts it by hand once
    # garage-server's is stopped, so a rebuild never runs two live copies.
    dotfiles.ai.gateway.server.startService = false;
  };
}
