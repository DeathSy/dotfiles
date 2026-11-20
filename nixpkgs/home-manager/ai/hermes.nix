{ config, lib, pkgs, ... }:

# Hermes Agent (Nous Research, https://hermes-agent.nousresearch.com) on the AI
# hub: the user's always-on agent, reachable as a Slack DM bot, plus the inbox
# monitor as one of its cron jobs. Imported by nixpkgs/hosts/garage-hq.nix
# together with the flake's own Home Manager module.
#
# Secrets: pass is the source of truth. The gpg key has a passphrase, so a
# launchd start can't read pass; activation (an interactive rebuild) copies the
# entries below into the login Keychain (service "hermes-agent"), and Hermes'
# `secrets.command` reads them from there at every start. Nothing lands in
# ~/.hermes/.env or config.yaml. The Slack user token is read from the Keychain
# by the inbox MCP server itself, so it never enters Hermes' environment.
let
  home = config.home.homeDirectory;
  hermesHome = "${home}/.hermes";
  inboxDir = "${home}/.local/state/inbox-monitor";
  service = "hermes-agent";
  owner = config.dotfiles.ai.hermes.slackUserId;
  hermesBin = "${config.programs.hermes-agent.package}/bin/hermes";
  passDir = config.programs.password-store.settings.PASSWORD_STORE_DIR or "";

  # Keychain account -> pass entry.
  keychainItems = {
    cliproxy-api-key = config.dotfiles.ai.gateway.keyPassEntry;
    slack-bot-token = "hermes/slack-bot-token";
    slack-app-token = "hermes/slack-app-token";
    slack-user-token = "hermes/slack-user-token";
  };
  # Environment variable -> Keychain account, handed to Hermes at start.
  hermesEnv = {
    CLIPROXY_API_KEY = "cliproxy-api-key";
    SLACK_BOT_TOKEN = "slack-bot-token";
    SLACK_APP_TOKEN = "slack-app-token";
  };

  secretsHelper = pkgs.writeShellScript "hermes-secrets" ''
    # Prints KEY=VALUE lines for Hermes' secrets.command. stderr is discarded by Hermes.
    ${lib.concatStrings (lib.mapAttrsToList (var: acct: ''
      v=$(/usr/bin/security find-generic-password -s ${service} -a ${acct} -w 2>/dev/null) \
        && [ -n "$v" ] && printf '%s=%s\n' ${var} "$v"
    '') hermesEnv)}
    exit 0
  '';

  # launchd runs /bin/zsh, which stays the job's root process: macOS TCC then
  # attributes the Reminders automation of the inbox monitor to "zsh" (granted
  # once) instead of a nix-store Python that changes with every update.
  # The gateway's pid is kept here and forwarded TERM/INT/HUP, so launchctl
  # stop/kickstart stops exactly that process.
  gatewayWrapper = pkgs.writeText "hermes-gateway.zsh" ''
    ${hermesBin} gateway "$@" &
    child=$!
    trap 'kill -TERM $child 2>/dev/null' TERM INT HUP
    wait $child; rc=$?
    while kill -0 $child 2>/dev/null; do wait $child; rc=$?; done
    exit $rc
  '';

  # Daily housekeeping, run as a no-agent Hermes cron job: monitor sessions
  # 3 days, monitor run documents 3 days, launchd logs capped.
  pruneScript = pkgs.writeShellScript "hermes-prune" ''
    set -u
    hermes=${hermesBin}
    "$hermes" sessions prune --source cron --older-than 3 --yes >/dev/null 2>&1 || echo "session prune failed"
    find ${hermesHome}/cron/output -type f -mmin +4320 -delete 2>/dev/null
    for f in ${home}/Library/Logs/hermes-agent.log ${home}/Library/Logs/hermes-agent.err.log; do
      [ -f "$f" ] && [ "$(stat -f %z "$f")" -gt 5000000 ] && : > "$f"
    done
    echo "[SILENT]"
  '';
in
{
  programs.hermes-agent.enable = true;

  services.hermes-agent = {
    enable = true;
    gateway.enable = true;
    workingDirectory = home;

    # Not secrets; written to ~/.hermes/.env (0600) by the module.
    environment = {
      SLACK_ALLOWED_USERS = owner;
      HERMES_CRON_TIMEOUT = "600";
    };

    settings = {
      providers.cliproxy = {
        api = config.dotfiles.ai.gateway.url;
        transport = "anthropic_messages";
        key_env = "CLIPROXY_API_KEY";
      };
      model = {
        provider = "cliproxy";
        default = "claude-sonnet-5-5";
      };

      secrets.command = {
        enabled = true;
        command = "${secretsHelper}";
        override_existing = true;
      };

      mcp_servers.inbox = {
        command = "/usr/bin/python3";
        args = [ "-I" "${inboxDir}/inbox_mcp.py" ];
        env.PATH = "/opt/homebrew/bin:/etc/profiles/per-user/${config.home.username}/bin:/usr/bin:/bin";
        timeout = 280;
      };
      # The inbox tools are only for the monitor job (enabled_toolsets on the
      # job); chat sessions never get them.
      platform_toolsets.slack = [ "web" "clarify" "skills" "memory" "todo" ];

      skills.external_dirs = [ "${inboxDir}/skill" ];

      unauthorized_dm_behavior = "ignore";
      slack = {
        require_mention = true;
        unauthorized_dm_behavior = "ignore";
        free_response_channels = "";
      };

      approvals = {
        mode = "manual";
        cron_mode = "deny";
        single_query_mode = "deny";
        unattended_mode = "deny";
      };

      memory.memory_enabled = true; # built-in, local files only; no external provider
      security.redact_secrets = true;

      sessions = {
        auto_prune = true;
        retention_days = 30;
      };
    };
  };

  launchd.agents.hermes-agent.config.ProgramArguments = lib.mkForce [ "/bin/zsh" "${gatewayWrapper}" ];

  # pass -> login Keychain. Runs on every rebuild; values go to `security -i`
  # on stdin, never on a command line. A missing pass entry is skipped with a
  # warning (the Slack ones exist only after the Slack app is set up).
  home.activation.hermesKeychain = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    (
      set -u
      ${lib.optionalString (passDir != "") "export PASSWORD_STORE_DIR=${lib.escapeShellArg passDir}"}
      pass=${config.programs.password-store.package}/bin/pass
      timeout=${pkgs.coreutils}/bin/timeout
      ${lib.concatStrings (lib.mapAttrsToList (acct: entry: ''
        if v=$($timeout 60 $pass show ${lib.escapeShellArg entry} 2>/dev/null | head -n 1) && [ -n "$v" ]; then
          case "$v" in
            *[!A-Za-z0-9._~+/=-]*) warnEcho "hermes: pass entry ${entry} has unexpected characters; not copied" ;;
            *) printf 'add-generic-password -U -s ${service} -a ${acct} -w "%s"\n' "$v" | $DRY_RUN_CMD /usr/bin/security -i >/dev/null 2>&1 \
                 || warnEcho "hermes: could not store ${acct} in the Keychain" ;;
          esac
        else
          noteEcho "hermes: pass entry ${entry} not found; skipped"
        fi
      '') keychainItems)}
    )
  '';

  home.packages = [
    # Creates (paused) or shows the monitor job and the daily prune job. Idempotent.
    (pkgs.writeShellScriptBin "hermes-inbox-jobs" ''
      set -eu
      hermes=${hermesBin}
      mkdir -p ${hermesHome}/scripts
      ln -sf ${pruneScript} ${hermesHome}/scripts/prune.sh
      if ! "$hermes" cron list --json 2>/dev/null | grep -q '"name": *"inbox-monitor"'; then
        "$hermes" cron create "every 5m" "Run one inbox-monitor cycle." \
          --name inbox-monitor --skill inbox-monitor \
          --workdir ${inboxDir} \
          --provider cliproxy --model claude-sonnet-5-5 \
          --toolsets mcp-inbox \
          --deliver ${if owner != "" then "slack:${owner}" else "local"} \
          --paused
      fi
      if ! "$hermes" cron list --json 2>/dev/null | grep -q '"name": *"hermes-prune"'; then
        "$hermes" cron create "every 1d at 04:00" --name hermes-prune --no-agent \
          --script ${hermesHome}/scripts/prune.sh --deliver local
      fi
      "$hermes" cron list
    '')
  ];
}
