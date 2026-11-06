{ config, lib, ... }:

# Local LLM: a llama.cpp server (llama-server, OpenAI-compatible API) that a
# research session runs by hand on the workstation, bound to its loopback with
# no API key. This tunnels it to the same port here, on this Mac's loopback
# only. When the server isn't running, the tunnel stays up and requests fail
# until it starts again.
let
  cfg = config.dotfiles.ai.localLlm;
  home = config.home.homeDirectory;
  port = toString cfg.port;
in
{
  options.dotfiles.ai.localLlm = with lib; {
    enable = mkEnableOption "the tunnel to the workstation's local LLM server";

    host = mkOption {
      type = types.str;
      default = "workstation";
      description = "SSH alias of the machine running llama-server (from ~/.ssh/config).";
    };

    port = mkOption {
      type = types.port;
      default = 18083;
      description = "llama-server's loopback port on the workstation, and the local port here.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Same shape as the Auto Browser tunnel (auto-browser.nix).
    launchd.agents.local-llm-tunnel = {
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
          "-L" "127.0.0.1:${port}:127.0.0.1:${port}"
          cfg.host
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        StandardErrorPath = "${home}/Library/Logs/local-llm-tunnel.log";
      };
    };
  };
}
