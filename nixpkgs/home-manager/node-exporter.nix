# Prometheus node_exporter on localhost:9100, with the textfile collector reading
# ~/.local/state/node-exporter/textfile (e.g. for AI-usage .prom files).
# Imported on garage-server and garage-hq (not the laptop).
# On garage-server, Prometheus in the Podman VM scrapes it via
# host.containers.internal:9100; garage-hq's exporter is reverse-forwarded to
# garage-server's 127.0.0.1:9102 (see node-exporter-tunnel.nix) and scraped via
# host.containers.internal:9102.
{ config, lib, pkgs, ... }:
let
  home = config.home.homeDirectory;
  textfileDir = "${home}/.local/state/node-exporter/textfile";
in {
  launchd.agents.node-exporter = {
    enable = true;
    config = {
      ProgramArguments = [
        "${lib.getExe pkgs.prometheus-node-exporter}"
        "--web.listen-address=127.0.0.1:9100"
        "--collector.textfile.directory=${textfileDir}"
        # Fails on every scrape on Apple silicon ("no CPU power status has been recorded").
        "--no-collector.thermal"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "${home}/Library/Logs/node-exporter.log";
      StandardErrorPath = "${home}/Library/Logs/node-exporter.log";
    };
  };

  # Apple silicon CPU temperature (node_exporter's thermal collector can't read it):
  # writes mac_cpu_temp_celsius to the textfile directory every 30 s, no root needed.
  launchd.agents.mac-temp-exporter = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "-I"
        "${./mac-temp-exporter.py}"
        "${textfileDir}/mac_temp.prom"
      ];
      RunAtLoad = true;
      StartInterval = 30;
      StandardOutPath = "${home}/Library/Logs/mac-temp-exporter.log";
      StandardErrorPath = "${home}/Library/Logs/mac-temp-exporter.log";
    };
  };

  # Ensure the textfile collector directory exists before launchd starts the agent.
  home.activation.nodeExporterTextfileDir = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
    run mkdir -p "${textfileDir}"
  '';
}
