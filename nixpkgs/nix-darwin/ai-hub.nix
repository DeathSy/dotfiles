# The AI hub role, imported by the hub's nixpkgs/hosts/<host>.nix: the
# CLIProxyAPI gateway for every Mac (the others reach it through an SSH
# tunnel, docs/ai-setup.md), and the Mac where the Claude Code sessions run,
# so their agents also get Auto Browser, Open Design and the local LLM server
# from the workstation. It never sleeps. Headroom stays a separate import in
# the host file (ai/headroom.nix).
{ ... }: {
  imports = [ ./never-sleep.nix ];

  homebrew.brews = [
    { name = "cliproxyapi"; start_service = true; }
    "cliclick" # UI automation for a private skill
  ];

  home-manager.users.ksotis = {
    dotfiles.ai.gateway.server.enable = true;
    dotfiles.ai.autoBrowser.enable = true;
    dotfiles.ai.openDesign.enable = true;
    dotfiles.ai.localLlm.enable = true;
  };
}
