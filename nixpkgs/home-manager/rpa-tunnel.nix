# garage-hq only: agents reach the RPA app (Steel + its API) on garage-server
# at http://localhost:18080 through this SSH forward to garage-server's
# 127.0.0.1:8080. The `garage-server` SSH alias (user's ~/.ssh/config) points
# only at the Thunderbolt bridge (10.0.99.1): hq<->server traffic never uses the
# network, not even as a fallback. While the cable is down, ssh fails and launchd
# retries every 30 s (see rpa-tunnel.log); 18080 is refused until it is back.
# Humans keep using https://garage-server.<tailnet>.ts.net.
{ config, ... }:
let
  home = config.home.homeDirectory;
in {
  launchd.agents.rpa-tunnel = {
    enable = true;
    config = {
      ProgramArguments = [
        "/usr/bin/ssh" "-N" "-T"
        "-o" "BatchMode=yes"
        "-o" "StrictHostKeyChecking=yes"
        "-o" "ExitOnForwardFailure=yes"
        "-o" "ConnectTimeout=10"
        "-o" "ServerAliveInterval=15"
        "-o" "ServerAliveCountMax=3"
        "-o" "ControlMaster=no"
        "-o" "ControlPath=none"
        "-L" "127.0.0.1:18080:127.0.0.1:8080"
        "garage-server"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardErrorPath = "${home}/Library/Logs/rpa-tunnel.log";
    };
  };
}
