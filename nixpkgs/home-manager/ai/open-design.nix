{ config, lib, ... }:

# Open Design: a design tool on the workstation (handoff doc under
# ~/studio/workstation/open-design). Agents reach its MCP server by running it
# inside the container over SSH, so the MCP path needs no tunnel or token. The
# tunnel is only for the web UI: local 127.0.0.1:7456 to the workstation's
# hardening proxy on 7457. The local port must stay 7456, the daemon's own
# port, because preview URLs and the origin check use it.
let
  cfg = config.dotfiles.ai.openDesign;
  home = config.home.homeDirectory;
  ssh = [
    "-o" "BatchMode=yes"
    "-o" "StrictHostKeyChecking=yes"
    "-o" "ConnectTimeout=10"
    "-o" "ControlMaster=no"
    "-o" "ControlPath=none"
  ];
in
{
  options.dotfiles.ai.openDesign = with lib; {
    enable = mkEnableOption "the Open Design web UI tunnel and MCP server";

    host = mkOption {
      type = types.str;
      default = "workstation";
      description = "SSH alias of the machine running Open Design (from ~/.ssh/config).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Same shape as the Auto Browser tunnel (auto-browser.nix).
    launchd.agents.open-design-tunnel = {
      enable = true;
      config = {
        ProgramArguments = [ "/usr/bin/ssh" "-N" "-T" ] ++ ssh ++ [
          "-o" "ExitOnForwardFailure=yes"
          "-o" "ServerAliveInterval=15"
          "-o" "ServerAliveCountMax=3"
          "-L" "127.0.0.1:7456:127.0.0.1:7457"
          cfg.host
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        StandardErrorPath = "${home}/Library/Logs/open-design-tunnel.log";
      };
    };

    dotfiles.ai.mcp.userServers.open-design = {
      transport = "stdio";
      command = [ "/usr/bin/ssh" "-T" ] ++ ssh ++ [
        "-o" "ServerAliveInterval=30"
        "-o" "ServerAliveCountMax=3"
        cfg.host
        "open-design/mcp.sh"
      ];
    };
  };
}
