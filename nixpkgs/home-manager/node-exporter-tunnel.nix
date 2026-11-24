# garage-hq only: reverse-forwards garage-hq's Prometheus node_exporter
# (127.0.0.1:9100) to garage-server's 127.0.0.1:9102 so Prometheus in
# garage-server's Podman VM can scrape it via host.containers.internal:9102
# without opening any network port. The `garage-server` SSH alias (user's
# ~/.ssh/config) points only at the Thunderbolt bridge (10.0.99.1):
# hq<->server traffic never uses the network, not even as a fallback. While
# the cable is down, ssh fails and launchd retries every 30 s (see
# node-exporter-tunnel.log).
{ config, ... }:
let
  home = config.home.homeDirectory;
in {
  launchd.agents.node-exporter-tunnel = {
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
        "-R" "127.0.0.1:9102:127.0.0.1:9100"
        "garage-server"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardErrorPath = "${home}/Library/Logs/node-exporter-tunnel.log";
    };
  };
}
