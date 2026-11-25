# garage-server only: LAN/WAN/DNS/HTTPS reachability probes for the Homelab
# dashboard. Every 30 s probes the router, 5G internet link, router DNS, and
# end-to-end HTTPS and writes network_probe_* gauges to node_exporter's
# textfile directory (see network-probe.py, docs/monitoring.md).
{ config, pkgs, ... }:
let
  home = config.home.homeDirectory;
in
{
  launchd.agents.network-probe = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "-I"
        "${./network-probe.py}"
        "${home}/.local/state/node-exporter/textfile/network.prom"
      ];
      RunAtLoad = true;
      StartInterval = 30;
      StandardOutPath = "${home}/Library/Logs/network-probe.log";
      StandardErrorPath = "${home}/Library/Logs/network-probe.log";
    };
  };
}
