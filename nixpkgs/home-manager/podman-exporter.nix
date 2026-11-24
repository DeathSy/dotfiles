# garage-server only: container counts from the local Podman VM for the
# Homelab dashboard. Every 60 s writes podman_containers{state} and podman_up
# to node_exporter's textfile directory (see node-exporter.nix, docs/monitoring.md).
{ config, pkgs, ... }:
let
  home = config.home.homeDirectory;
  out = "${home}/.local/state/node-exporter/textfile/podman.prom";
  script = pkgs.writeShellScript "podman-exporter" ''
    set -u
    tmp="${out}.$$.tmp"
    if states=$(${pkgs.podman}/bin/podman ps -a --format '{{.State}}' 2>/dev/null); then up=1; else up=0; states=""; fi
    count() { printf '%s\n' "$states" | grep -c "$@" || true; }
    {
      echo "# HELP podman_containers Containers in the Podman VM by state."
      echo "# TYPE podman_containers gauge"
      echo "podman_containers{state=\"running\"} $(count '^running$')"
      echo "podman_containers{state=\"exited\"} $(count '^exited$')"
      echo "podman_containers{state=\"other\"} $(count -v -e '^running$' -e '^exited$' -e '^$')"
      echo "# HELP podman_up 1 if podman ps succeeded (Podman VM reachable)."
      echo "# TYPE podman_up gauge"
      echo "podman_up $up"
    } > "$tmp" && mv "$tmp" "${out}"
  '';
in
{
  launchd.agents.podman-exporter = {
    enable = true;
    config = {
      ProgramArguments = [ "${script}" ];
      RunAtLoad = true;
      StartInterval = 60;
      StandardOutPath = "${home}/Library/Logs/podman-exporter.log";
      StandardErrorPath = "${home}/Library/Logs/podman-exporter.log";
    };
  };
}
