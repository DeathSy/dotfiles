{ config, lib, ... }:

# Auto Browser: a browser service on the workstation (its own repo and README
# under ~/studio/workstation/auto-browser) that agents drive over MCP and the
# user can watch or take over remotely. It listens only on the workstation's
# loopback (port 8000); this tunnels it to 127.0.0.1:18000 here, a port dev
# servers don't default to, and registers it with Claude Code. The agent
# token comes from pass at connect time.
let
  cfg = config.dotfiles.ai.autoBrowser;
  home = config.home.homeDirectory;
in
{
  options.dotfiles.ai.autoBrowser = with lib; {
    enable = mkEnableOption "the Auto Browser tunnel and MCP server";

    tunnel.host = mkOption {
      type = types.str;
      default = "workstation";
      description = "SSH alias of the machine running Auto Browser (from ~/.ssh/config).";
    };

    tokenPassEntry = mkOption {
      type = types.str;
      default = "workstation/auto-browser/agent-token";
      description = "pass entry with the agent token.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Same shape as the gateway tunnel (gateway.nix): Apple's ssh, no prompts,
    # and launchd retries whenever the forward fails or drops.
    launchd.agents.auto-browser-tunnel = {
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
          "-L" "127.0.0.1:18000:127.0.0.1:8000"
          cfg.tunnel.host
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        StandardErrorPath = "${home}/Library/Logs/auto-browser-tunnel.log";
      };
    };

    dotfiles.ai.mcp.userServers.auto-browser = {
      url = "http://127.0.0.1:18000/mcp";
      headersHelper = "pass show ${lib.escapeShellArg cfg.tokenPassEntry} | head -n1 | jq -Rc '{Authorization: (\"Bearer \" + .), \"X-Operator-Name\": \"claude-code\"}'";
    };
  };
}
