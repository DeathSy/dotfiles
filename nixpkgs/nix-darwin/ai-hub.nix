# The AI hub role, imported by the hub's nixpkgs/hosts/<host>.nix: the
# CLIProxyAPI gateway for every Mac (the others reach it through an SSH
# tunnel, docs/ai-setup.md), and the Mac where the Claude Code sessions run.
# It never sleeps. Headroom stays a separate import in the host file
# (ai/headroom.nix).
{ config, ... }: {
  imports = [ ./never-sleep.nix ];

  homebrew.brews = [
    {
      name = "cliproxyapi";
      start_service = config.home-manager.users.ksotis.dotfiles.ai.gateway.server.startService;
    }
    "cliclick" # UI automation for a private skill
  ];

  home-manager.users.ksotis = {
    dotfiles.ai.gateway.server.enable = true;
  };
}
