# garage-server only: container metrics from the local Podman VM for the
# Homelab dashboard. Every 60 s writes podman_up, podman_containers{state} and
# per-container state, uptime, CPU time, memory and process count to
# node_exporter's textfile directory (see podman-exporter.py, docs/monitoring.md).
{ config, pkgs, ... }:
let
  home = config.home.homeDirectory;
in
{
  launchd.agents.podman-exporter = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "-I"
        "${./podman-exporter.py}"
        "${pkgs.podman}/bin/podman"
        "${home}/.local/state/node-exporter/textfile/podman.prom"
      ];
      RunAtLoad = true;
      StartInterval = 60;
      StandardOutPath = "${home}/Library/Logs/podman-exporter.log";
      StandardErrorPath = "${home}/Library/Logs/podman-exporter.log";
    };
  };
}
