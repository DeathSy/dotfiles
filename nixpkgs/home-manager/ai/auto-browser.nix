{ config, lib, pkgs, ... }:

# Auto Browser: a browser service on the workstation (its own repo and README
# under ~/studio/workstation/auto-browser) that agents drive over MCP and the
# user can watch or take over remotely. It listens only on the workstation's
# loopback (port 8000); this tunnels it to 127.0.0.1:18000 here, a port dev
# servers don't default to, and registers it with Claude Code. At connect time
# a helper script reads the agent token from pass and names the calling session.
let
  cfg = config.dotfiles.ai.autoBrowser;
  home = config.home.homeDirectory;
  pass = "${config.programs.password-store.package}/bin/pass";
  passDir = config.programs.password-store.settings.PASSWORD_STORE_DIR or "";

  # Prints the request headers as JSON for Claude Code's headersHelper. The
  # token goes through a pipe, never argv. X-Operator-Name tells the user
  # which session drives a browser: claude:<project dir>:p<tmux pane id>, or
  # the first 8 characters of the session id outside tmux. The project part is
  # cut first so the session part always survives the 64-character limit.
  headersScript = ''
    #!/bin/sh
    set -u +x
    ${lib.optionalString (passDir != "") "export PASSWORD_STORE_DIR=${lib.escapeShellArg passDir}"}
    project=$(printf '%s' "$(basename "''${PWD:-unknown}")" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-' | cut -c1-40)
    if [ -n "''${TMUX_PANE:-}" ]; then
      where="p''${TMUX_PANE#%}"
    else
      where=$(printf '%s' "''${CLAUDE_CODE_SESSION_ID:-unknown}" | cut -c1-8)
    fi
    name=$(printf 'claude:%s:%s' "$project" "$where" | LC_ALL=C tr -c 'A-Za-z0-9._:-' '-' | cut -c1-64)
    token=$(${pass} show ${lib.escapeShellArg cfg.tokenPassEntry}) || exit 1
    printf '%s\n' "$token" | head -n1 |
      ${pkgs.jq}/bin/jq -Rc --arg n "$name" '{Authorization: ("Bearer " + .), "X-Operator-Name": $n}'
  '';
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

    # A fixed path rather than a store path: ~/.claude.json keeps the command
    # across rebuilds and garbage collection.
    home.file.".local/bin/auto-browser-headers" = {
      executable = true;
      text = headersScript;
    };

    dotfiles.ai.mcp.userServers.auto-browser = {
      url = "http://127.0.0.1:18000/mcp";
      headersHelper = "${home}/.local/bin/auto-browser-headers";
    };
  };
}
