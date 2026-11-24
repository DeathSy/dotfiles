# Monitoring exporters

Prometheus runs in a container inside **garage-server**'s Podman VM and scrapes
host metrics from both always-on Macs without opening any network port.
**garage** (the laptop) runs neither agent.

## LaunchAgents

- **`org.nix-community.home.node-exporter`** (`nixpkgs/home-manager/node-exporter.nix`,
  imported by `garage-server` and `garage-hq`): runs `prometheus-node-exporter`
  bound to `127.0.0.1:9100` (loopback only, never `0.0.0.0`), with the default
  unprivileged Darwin collectors and the textfile collector enabled on
  `~/.local/state/node-exporter/textfile` (created at activation before launchd
  starts the agent; custom `.prom` files such as AI-usage metrics can be dropped
  there). Kept alive by launchd (30 s restart throttle).
  Log: `~/Library/Logs/node-exporter.log`.
- **`org.nix-community.home.node-exporter-tunnel`**
  (`nixpkgs/home-manager/node-exporter-tunnel.nix`, imported by `garage-hq`
  only): runs Apple's
  `/usr/bin/ssh -N -T -R 127.0.0.1:9102:127.0.0.1:9100 garage-server` so
  `garage-hq`'s exporter is exposed on `garage-server`'s `127.0.0.1:9102` only.
  Uses the `garage-server` SSH alias (which points at the Thunderbolt bridge,
  `10.0.99.1`, never the network), with `BatchMode=yes`,
  `StrictHostKeyChecking=yes`, `ExitOnForwardFailure=yes`, `ConnectTimeout=10`,
  15 s keepalives (`ServerAliveInterval=15`, `ServerAliveCountMax=3`) and no
  connection sharing (`ControlMaster=no`, `ControlPath=none`); launchd restarts
  it at most every 30 s.
  Log: `~/Library/Logs/node-exporter-tunnel.log`.

## Scraping from the Podman VM

Containers in `garage-server`'s Podman VM reach the host loopback listeners via
`host.containers.internal`:

| Host | Target from Podman VM | Backing listener |
|---|---|---|
| `garage-server` | `host.containers.internal:9100` | local `node_exporter` (`127.0.0.1:9100`) |
| `garage-hq` | `host.containers.internal:9102` | SSH reverse forward from `garage-hq` (`127.0.0.1:9100`) over Thunderbolt |
