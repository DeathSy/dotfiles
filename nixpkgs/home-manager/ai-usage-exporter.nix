# garage-hq only: collects Claude (via CLIProxyAPI management API) and Codex
# (via ~/.codex/sessions) quota usage every 5 minutes and writes
# ~/.local/state/node-exporter/textfile/ai_usage.prom atomically for
# node_exporter's textfile collector. See docs/monitoring.md.
#
# Secret handling (same pattern as ai/hermes.nix): pass is the source of truth
# (`ai/cliproxyapi-management-secret`), synced into the login Keychain
# (service `ai-usage-exporter`, account `cliproxy-management-secret`) on
# activation via `ai-usage-keychain-sync`. The launchd agent reads the key from
# Keychain at runtime and never puts it in argv, logs, or the Nix store.
{ config, lib, pkgs, ... }:
let
  home = config.home.homeDirectory;
  textfileDir = "${home}/.local/state/node-exporter/textfile";
  passDir = config.programs.password-store.settings.PASSWORD_STORE_DIR or "";
  passEntry = config.dotfiles.ai.gateway.managementSecretPassEntry;
  keychainService = "ai-usage-exporter";
  keychainAccount = "cliproxy-management-secret";
  timeout = "${pkgs.coreutils}/bin/timeout";
  py = "${pkgs.python3}/bin/python3";

  # Syncs the CLIProxyAPI management key from pass into the login Keychain.
  # Value passes to `security -i` on stdin (hex-encoded with -X, never in argv)
  # and is read back to verify; decryption failure never overwrites the item.
  keychainSync = pkgs.writeShellScriptBin "ai-usage-keychain-sync" ''
    set -u +x
    ${lib.optionalString (passDir != "") "export PASSWORD_STORE_DIR=${lib.escapeShellArg passDir}"}
    store=''${PASSWORD_STORE_DIR:-$HOME/.password-store}
    pass=${config.programs.password-store.package}/bin/pass
    entry=${lib.escapeShellArg passEntry}
    svc=${lib.escapeShellArg keychainService}
    acct=${lib.escapeShellArg keychainAccount}
    say() { printf 'ai-usage-keychain-sync: %s\n' "$1" >&2; }

    if [ ! -f "$store/$entry.gpg" ]; then
      say "$svc/$acct: pass entry $entry does not exist; left as it is"
      exit 0
    fi
    v=$(${timeout} 60 $pass show "$entry" 2>/dev/null | head -n 1)
    if [ -z "$v" ]; then
      say "$svc/$acct: could not decrypt pass entry $entry (gpg locked or pinentry not answered); NOT updated"
      exit 1
    fi
    if [ "$(/usr/bin/security find-generic-password -s "$svc" -a "$acct" -w 2>/dev/null)" = "$v" ]; then
      unset v
      say "$svc/$acct: unchanged"
      exit 0
    fi
    printf '%s' "$v" \
      | ${py} -I -c 'import sys; svc, acct = sys.argv[1], sys.argv[2]; hx = sys.stdin.buffer.read().hex(); sys.stdout.write(f"add-generic-password -U -s {svc} -a {acct} -T /usr/bin/security -X {hx}\n")' "$svc" "$acct" \
      | /usr/bin/security -i >/dev/null 2>&1
    if [ "$(/usr/bin/security find-generic-password -s "$svc" -a "$acct" -w 2>/dev/null)" = "$v" ]; then
      unset v
      say "$svc/$acct: updated from $entry"
      exit 0
    fi
    unset v
    say "$svc/$acct: could not write the login Keychain (locked, or a session without access?); NOT updated"
    exit 1
  '';

  exporter = pkgs.writeShellScriptBin "ai-usage-exporter" ''
    exec ${py} -I ${./ai-usage-exporter.py} \
      --gateway-url ${lib.escapeShellArg config.dotfiles.ai.gateway.url} \
      --keychain-service ${lib.escapeShellArg keychainService} \
      --keychain-account ${lib.escapeShellArg keychainAccount} \
      --output ${lib.escapeShellArg "${textfileDir}/ai_usage.prom"} \
      --codex-sessions-dir ${lib.escapeShellArg "${home}/.codex/sessions"} \
      "$@"
  '';
in
{
  launchd.agents.ai-usage-exporter = {
    enable = true;
    config = {
      ProgramArguments = [ "${exporter}/bin/ai-usage-exporter" ];
      RunAtLoad = true;
      StartInterval = 300;
      StandardOutPath = "${home}/Library/Logs/ai-usage-exporter.log";
      StandardErrorPath = "${home}/Library/Logs/ai-usage-exporter.log";
    };
  };

  home.activation.aiUsageKeychain = lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ] ''
    if [ -z "''${DRY_RUN_CMD:-}" ]; then
      ${keychainSync}/bin/ai-usage-keychain-sync \
        || errorEcho "ai-usage-exporter: Keychain sync incomplete (see above). Run ai-usage-keychain-sync at the console."
    fi
  '';

  home.packages = [
    exporter
    keychainSync
  ];
}
