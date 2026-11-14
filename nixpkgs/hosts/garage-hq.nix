# garage-hq: the Mac Studio that takes over the AI hub (../nix-darwin/ai-hub.nix)
# from garage-server. Added on top of the shared config in flake.nix.
{ ... }: {
  imports = [ ../nix-darwin/ai-hub.nix ];

  networking.computerName = "ksotis-hq";

  home-manager.users.ksotis = {
    imports = [ ../home-manager/ai/headroom.nix ];

    # Until the cutover (docs/ai-setup.md, "Moving the gateway server to
    # garage-hq") garage-server owns the workstation's port 18317, so this
    # gateway doesn't open Open Design's reverse tunnel.
    dotfiles.ai.openDesign.gatewayTunnel = false;
  };
}
