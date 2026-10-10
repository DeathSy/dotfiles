{ config, lib, pkgs, ... }:

# CLIProxyAPI gateway: Claude Code (and the sol/luna/astra agents) talk to a
# local CLIProxyAPI that holds the OAuth logins. The Homebrew service is
# declared in nix-darwin/configuration.nix; this writes its config on a fresh
# machine and points Claude Code at it.
let
  cfg = config.dotfiles.ai.gateway;
  passDir = config.programs.password-store.settings.PASSWORD_STORE_DIR or "";
in
{
  options.dotfiles.ai.gateway = with lib; {
    enable = mkEnableOption "routing Claude Code through the local CLIProxyAPI gateway";

    url = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8317";
    };

    keyPassEntry = mkOption {
      type = types.str;
      default = "ai/cliproxyapi-key";
      description = "pass entry with the CLIProxyAPI client key (also Claude Code's ANTHROPIC_AUTH_TOKEN).";
    };

    managementSecretPassEntry = mkOption {
      type = types.str;
      default = "ai/cliproxyapi-management-secret";
      description = "pass entry with the CLIProxyAPI management key (plain text; it hashes it on load).";
    };
  };

  config = lib.mkIf cfg.enable {
    dotfiles.ai.claude.settingsOverlay.env = {
      ANTHROPIC_BASE_URL = cfg.url;
      CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
    };
    dotfiles.ai.claude.secretEnv.ANTHROPIC_AUTH_TOKEN = cfg.keyPassEntry;

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
  };
}
