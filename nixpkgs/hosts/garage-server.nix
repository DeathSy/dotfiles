# garage-server: the server Mac. Added on top of the shared config in flake.nix.
# It runs the CLIProxyAPI gateway and Headroom for every Mac; the others reach
# the gateway through an SSH tunnel (docs/ai-setup.md). Its agents also get
# Auto Browser and Open Design from the workstation.
{ ... }: {
  networking.computerName = "ksotis-server";

  homebrew.brews = [
    { name = "cliproxyapi"; start_service = true; }
  ];

  home-manager.users.ksotis = {
    imports = [ ../home-manager/ai/headroom.nix ];
    dotfiles.ai.gateway.server.enable = true;
    dotfiles.ai.autoBrowser.enable = true;
    dotfiles.ai.openDesign.enable = true;
  };
}
