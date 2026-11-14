# Never sleep, lid closed or not: other Macs reach this one over Tailscale.
# Keep-awake apps (Vorssaint) flip this same switch off when they quit or
# are toggled, so a root daemon puts it back when the power settings file
# changes (best effort: launchd may take a moment) and every minute as a
# backstop, noting each fix and any error in /var/log/never-sleep.log.
{ ... }: {
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
}
