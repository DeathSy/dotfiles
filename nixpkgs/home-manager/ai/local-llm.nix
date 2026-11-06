{ config, lib, ... }:

# Local LLM: a llama.cpp server (llama-server, OpenAI-compatible API) on the
# workstation's loopback, port 18083, with no API key. This tunnels it to the
# same port on this Mac's loopback only. While the server is down the tunnel
# stays up: ssh accepts each connection and then closes it, so clients see a
# reset or an empty reply rather than "connection refused".
let
  cfg = config.dotfiles.ai.localLlm;
  home = config.home.homeDirectory;
in
{
  options.dotfiles.ai.localLlm = with lib; {
    enable = mkEnableOption "the tunnel to the workstation's local LLM server";

    host = mkOption {
      type = types.str;
      default = "workstation";
      description = "SSH alias of the machine running llama-server (from ~/.ssh/config).";
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
          "-L" "127.0.0.1:18083:127.0.0.1:18083"
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
