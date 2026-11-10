# garage-server: the server Mac. Added on top of the shared config in flake.nix.
# It runs the CLIProxyAPI gateway and Headroom for every Mac; the others reach
# the gateway through an SSH tunnel (docs/ai-setup.md). Its agents also get
# Auto Browser, Open Design and the local LLM server from the workstation.
{ ... }: {
  networking.computerName = "ksotis-server";

  # Never sleep, lid closed or not: other Macs reach this one over Tailscale.
  # Keep-awake apps (Vorssaint) flip this same switch off when they quit or
  # are toggled, so a root daemon puts it back when the power settings file
  # changes (best effort: launchd may take a moment) and every minute as a
  # backstop, noting each fix and any error in /var/log/never-sleep.log.
  system.activationScripts.postActivation.text = ''
    pmset -a disablesleep 1
  '';
  launchd.daemons.never-sleep.serviceConfig = {
    ProgramArguments = [ "/bin/sh" "-c" ''
      /usr/bin/pmset -g | /usr/bin/grep -Eq '^ *SleepDisabled[[:space:]]+1' ||
        { /usr/bin/pmset -a disablesleep 1 && echo "$(/bin/date '+%F %T') disablesleep was off; set it back to 1" >> /var/log/never-sleep.log; }
    '' ];
    WatchPaths = [ "/Library/Preferences/com.apple.PowerManagement.plist" ];
    RunAtLoad = true;
    StartInterval = 60;
    ThrottleInterval = 0;
    StandardErrorPath = "/var/log/never-sleep.log";
  };

  homebrew.brews = [
    { name = "cliproxyapi"; start_service = true; }
    "cliclick" # UI automation for a private skill
  ];

  home-manager.users.ksotis = {
    imports = [ ../home-manager/ai/headroom.nix ];
    dotfiles.ai.gateway.server.enable = true;
    dotfiles.ai.autoBrowser.enable = true;
    dotfiles.ai.openDesign.enable = true;
    dotfiles.ai.localLlm.enable = true;
  };
}
