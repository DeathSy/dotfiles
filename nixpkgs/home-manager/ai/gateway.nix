{ config, lib, pkgs, ... }:

# CLIProxyAPI gateway: Claude Code (and the sol/luna/astra agents) talk to a
# CLIProxyAPI on 127.0.0.1:8317 that holds the OAuth logins. It runs only on the
# host that sets `server.enable` (nixpkgs/hosts/garage-server.nix, which also
# declares the Homebrew service); there this writes its config on a fresh
# machine. Every other host forwards the same local port to it over SSH.
let
  cfg = config.dotfiles.ai.gateway;
  home = config.home.homeDirectory;
  passDir = config.programs.password-store.settings.PASSWORD_STORE_DIR or "";
in
{
  options.dotfiles.ai.gateway = with lib; {
    enable = mkEnableOption "routing Claude Code through the CLIProxyAPI gateway";

    url = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8317";
    };

    keyPassEntry = mkOption {
      type = types.str;
      default = "ai/cliproxyapi-key";
      description = "pass entry with the CLIProxyAPI client key (also Claude Code's ANTHROPIC_AUTH_TOKEN).";
    };

    server.enable = mkEnableOption "running CLIProxyAPI on this machine instead of tunnelling to it";

    managementSecretPassEntry = mkOption {
      type = types.str;
      default = "ai/cliproxyapi-management-secret";
      description = "pass entry with the CLIProxyAPI management key (plain text; it hashes it on load). Server only.";
    };

    tunnel.host = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "garage-server";
      description = ''
        SSH destination of the gateway server, normally a ~/.ssh/config alias
        (set it in the private overlay). The tunnel forwards 127.0.0.1:8317 to
        the server's 127.0.0.1:8317. Required unless `server.enable`.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      dotfiles.ai.claude.settingsOverlay.env = {
        ANTHROPIC_BASE_URL = cfg.url;
        CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
      };
      dotfiles.ai.claude.secretEnv.ANTHROPIC_AUTH_TOKEN = cfg.keyPassEntry;
    }

    (lib.mkIf cfg.server.enable {
      # CLIProxyAPI rewrites its own config (management API), so only write it
      # from the template when there is none yet.
      home.activation.cliproxyapiConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        cliproxyConf=/opt/homebrew/etc/cliproxyapi.conf
        if [[ -v DRY_RUN ]] || [ -e "$cliproxyConf" ] || [ ! -d /opt/homebrew/etc ]; then
          :
        else
          (
            set -uo pipefail
            ${lib.optionalString (passDir != "") "export PASSWORD_STORE_DIR=${lib.escapeShellArg passDir}"}
            pass=${config.programs.password-store.package}/bin/pass
            timeout=${pkgs.coreutils}/bin/timeout
            apiKey=$($timeout 60 $pass show ${lib.escapeShellArg cfg.keyPassEntry} | head -n 1) && [ -n "$apiKey" ] || exit 1
            mgmt=$($timeout 60 $pass show ${lib.escapeShellArg cfg.managementSecretPassEntry} | head -n 1) && [ -n "$mgmt" ] || exit 1
            tmp=$(mktemp "$cliproxyConf.XXXXXX") || exit 1
            API_KEY="$apiKey" MGMT="$mgmt" ${pkgs.perl}/bin/perl -pe \
              's/\@HOME\@/$ENV{HOME}/g; s/\@API_KEY\@/$ENV{API_KEY}/g; s/\@MANAGEMENT_SECRET\@/$ENV{MGMT}/g' \
              ${../../../cliproxyapi/config.yaml} > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$cliproxyConf" \
              || { rm -f "$tmp"; exit 1; }
            echo "Wrote $cliproxyConf; run: brew services restart cliproxyapi"
          ) || warnEcho "cliproxyapi config not written (needs pass entries ${cfg.keyPassEntry} and ${cfg.managementSecretPassEntry})"
        fi
      '';
    })

    (lib.mkIf (!cfg.server.enable) {
      assertions = [{
        assertion = cfg.tunnel.host != null;
        message = "dotfiles.ai.gateway.enable on a host without the gateway server needs dotfiles.ai.gateway.tunnel.host (an SSH alias for the server; see docs/ai-setup.md).";
      }];

      # Apple's ssh, which understands UseKeychain in ~/.ssh/config. BatchMode:
      # no prompts, so the host key must already be in known_hosts and
      # authentication must work unattended. While something else holds
      # 127.0.0.1:8317, ExitOnForwardFailure makes ssh exit and launchd retries.
      launchd.agents.cliproxyapi-tunnel = {
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
            "-L" "127.0.0.1:8317:127.0.0.1:8317"
            (toString cfg.tunnel.host)
          ];
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 30;
          StandardErrorPath = "${home}/Library/Logs/cliproxyapi-tunnel.log";
        };
      };
    })
  ]);
}
