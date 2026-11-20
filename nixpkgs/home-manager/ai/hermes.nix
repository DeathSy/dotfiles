{ config, lib, pkgs, ... }:

# Hermes Agent (Nous Research, https://hermes-agent.nousresearch.com) on the AI
# hub: the owner's always-on agent, reachable as a Slack DM bot, plus the inbox
# monitor as one of its cron jobs. Imported by nixpkgs/hosts/garage-hq.nix
# together with the flake's (locally patched) Home Manager module. Guide and the
# accepted risk: docs/ai-setup.md, "Hermes Agent".
#
# Secrets: pass is the source of truth. The gpg key has a passphrase, so a
# launchd start can't read pass; activation (an interactive rebuild) copies the
# entries into the login Keychain and the processes read them from there:
#   service hermes-agent:  cliproxy-api-key, slack-bot-token, slack-app-token,
#                          slack-owner-id  -> Hermes, via `secrets.command`
#   service inbox-monitor: slack-user-token -> only the inbox MCP server reads it
# Nothing secret or personal is written to ~/.hermes/.env, config.yaml or the
# Nix store.
let
  home = config.home.homeDirectory;
  hermesHome = "${home}/.hermes";
  stateDir = "${home}/.local/state/inbox-monitor";
  hermesBin = "${config.programs.hermes-agent.package}/bin/hermes";
  timeout = "${pkgs.coreutils}/bin/timeout";
  sonnet = "claude-sonnet-5-5";
  haiku = "claude-haiku-5-5";
  cfg = config.dotfiles.ai.hermes;

  # Keychain "service/account" -> pass entry.
  keychainItems = {
    "hermes-agent/cliproxy-api-key" = config.dotfiles.ai.gateway.keyPassEntry;
    "hermes-agent/slack-bot-token" = "hermes/slack-bot-token";
    "hermes-agent/slack-app-token" = "hermes/slack-app-token";
    "hermes-agent/slack-owner-id" = "hermes/slack-owner-id";
    "inbox-monitor/slack-user-token" = "hermes/slack-user-token";
  };
  # Environment variable -> Keychain account (service hermes-agent), for Hermes.
  hermesEnv = {
    CLIPROXY_API_KEY = "cliproxy-api-key";
    SLACK_BOT_TOKEN = "slack-bot-token";
    SLACK_APP_TOKEN = "slack-app-token";
    SLACK_ALLOWED_USERS = "slack-owner-id";
    # Dashboard sign-in (basic provider): the scrypt hash of the owner's password
    # and the token-signing secret, both made at activation (see below).
    HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH = "dashboard-password-hash";
    HERMES_DASHBOARD_BASIC_AUTH_SECRET = "dashboard-session-secret";
  };

  # Copies each pass entry into its Keychain item and says what it did. Values
  # go to `security -i` on stdin (never a command line) and are read back; an
  # entry that can't be decrypted (gpg locked, pinentry not answered) is an
  # error, not a silent skip, and never overwrites the item. Writes a
  # value-free status to ~/.local/state/hermes-keychain-sync.log.
  keychainSync = pkgs.writeShellScriptBin "hermes-keychain-sync" ''
    set -u +x
    ${lib.optionalString ((config.programs.password-store.settings.PASSWORD_STORE_DIR or "") != "")
      "export PASSWORD_STORE_DIR=${lib.escapeShellArg config.programs.password-store.settings.PASSWORD_STORE_DIR}"}
    store=''${PASSWORD_STORE_DIR:-$HOME/.password-store}
    pass=${config.programs.password-store.package}/bin/pass
    log=$HOME/.local/state/hermes-keychain-sync.log
    mkdir -p "$(dirname "$log")"; : > "$log"
    updated=0 unchanged=0 failed=0 missing=0
    say() { printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$log"; printf 'hermes-keychain-sync: %s\n' "$1" >&2; }
    sync_one() {  # service account pass-entry
      if [ ! -f "$store/$3.gpg" ]; then missing=$((missing + 1)); say "$1/$2: pass entry $3 does not exist; left as it is"; return; fi
      v=$(${timeout} 60 $pass show "$3" 2>/dev/null | head -n 1)
      if [ -z "$v" ]; then failed=$((failed + 1)); say "$1/$2: could not decrypt pass entry $3 (gpg locked or pinentry not answered); NOT updated"; return; fi
      case "$v" in *[!A-Za-z0-9._~+/=-]*) failed=$((failed + 1)); say "$1/$2: pass entry $3 has unexpected characters; NOT updated"; unset v; return ;; esac
      if [ "$(/usr/bin/security find-generic-password -s "$1" -a "$2" -w 2>/dev/null)" = "$v" ]; then
        unchanged=$((unchanged + 1)); unset v; return
      fi
      printf 'add-generic-password -U -s %s -a %s -T /usr/bin/security -w "%s"\n' "$1" "$2" "$v" | /usr/bin/security -i >/dev/null 2>&1
      if [ "$(/usr/bin/security find-generic-password -s "$1" -a "$2" -w 2>/dev/null)" = "$v" ]; then
        updated=$((updated + 1)); say "$1/$2: updated from $3"
      else
        failed=$((failed + 1)); say "$1/$2: could not write the login Keychain (locked, or a session without access?); NOT updated"
      fi
      unset v
    }
    ${lib.concatStrings (lib.mapAttrsToList (item: entry: ''
      sync_one ${lib.escapeShellArg (builtins.head (lib.splitString "/" item))} ${lib.escapeShellArg (lib.last (lib.splitString "/" item))} ${lib.escapeShellArg entry}
    '') keychainItems)}
    say "$updated updated, $unchanged unchanged, $failed failed, $missing missing"
    [ "$failed" -eq 0 ]
  '';

  secretsHelper = pkgs.writeShellScript "hermes-secrets" ''
    # KEY=VALUE lines for Hermes' secrets.command (stdout only; Hermes discards stderr).
    ${lib.concatStrings (lib.mapAttrsToList (var: acct: ''
      v=$(/usr/bin/security find-generic-password -s hermes-agent -a ${acct} -w 2>/dev/null) \
        && [ -n "$v" ] && printf '%s=%s\n' ${var} "$v"
    '') hermesEnv)}
    exit 0
  '';

  # The monitor's code, read-only in the store. State and config.json stay in
  # ~/.local/state/inbox-monitor (see hermes/inbox-monitor/README.md).
  inboxMonitor = pkgs.runCommand "inbox-monitor" { } ''
    mkdir -p $out
    cp ${../../../hermes/inbox-monitor}/{inbox_mcp.py,im,reminders.js,fetch_gmail.py,deadman.py} $out/
    chmod 0555 $out/inbox_mcp.py $out/im $out/fetch_gmail.py $out/deadman.py
    chmod 0444 $out/reminders.js
  '';
  # The skill is generic; the owner's names, ids, lists and known not-tasks come
  # from config.json (0600, outside the store) through the `window` tool.
  skillsDir = pkgs.linkFarm "hermes-inbox-skill" [{
    name = "inbox-monitor/SKILL.md";
    path = ../../../hermes/inbox-monitor/SKILL.md;
  }];
  # graphify (the knowledge-graph skill Claude Code uses) for chat sessions;
  # a link to the live skill folder, not a copy.
  chatSkillsDir = pkgs.runCommand "hermes-chat-skills" { } ''
    mkdir -p $out
    ln -s ${home}/.claude/skills/graphify $out/graphify
  '';

  # tailscale serve: HTTPS on the tailnet (never Funnel) -> the loopback
  # dashboard. Refuses to touch port 443 when something else serves it there.
  dashboardPort = 9119;
  serveTarget = "http://127.0.0.1:${toString dashboardPort}";

  # launchd runs /bin/zsh, which stays the job's root process: macOS TCC then
  # attributes the monitor's Reminders automation to "zsh" (allowed once)
  # instead of a nix-store Python that changes with every update.
  # Preflight: the gateway needs the model key; while the login Keychain is not
  # readable yet (just after a reboot) exit non-zero so launchd retries.
  # TERM/INT/HUP are forwarded to the recorded gateway pid, and zsh waits for it.
  gatewayWrapper = pkgs.writeText "hermes-gateway.zsh" ''
    child=
    trap 'if [[ -n $child ]]; then kill -TERM $child 2>/dev/null; else exit 143; fi' TERM INT HUP
    for i in {1..12}; do
      ${timeout} 10 /usr/bin/security find-generic-password -s hermes-agent -a cliproxy-api-key -w >/dev/null 2>&1 && break
      (( i == 12 )) && { print -u2 "hermes-gateway: Keychain item hermes-agent/cliproxy-api-key not readable; retrying via launchd"; exit 75; }
      sleep 5
    done
    ${hermesBin} gateway ${lib.escapeShellArgs config.services.hermes-agent.extraArgs} "$@" &
    child=$!
    wait $child; rc=$?
    while kill -0 $child 2>/dev/null; do wait $child; rc=$?; done
    exit $rc
  '';

  # Daily housekeeping (a no-agent Hermes cron job): monitor sessions, run
  # documents and spilled tool output 1 day; chat sessions are kept
  # (sessions.auto_prune off), but their spilled tool output goes too.
  pruneScript = pkgs.writeShellScript "hermes-prune" ''
    set -u
    ${hermesBin} sessions prune --source cron --older-than 1 --yes >/dev/null 2>&1 || echo "hermes-prune: session prune failed"
    find ${hermesHome}/cron/output ${hermesHome}/cache/spillover -type f -mmin +1440 -delete 2>/dev/null
    for f in ${home}/Library/Logs/hermes-agent.log ${home}/Library/Logs/hermes-agent.err.log; do
      [ -f "$f" ] && [ "$(stat -f %z "$f")" -gt 5000000 ] && : > "$f"
    done
    echo "[SILENT]"
  '';

in
{
  config = {
    programs.hermes-agent.enable = true;

    services.hermes-agent = {
      enable = true;
      gateway.enable = true;
      workingDirectory = home;

      environment = {
        HERMES_CRON_TIMEOUT = "600";
      } // lib.optionalAttrs (cfg.slackHomeChannel != null) { SLACK_HOME_CHANNEL = cfg.slackHomeChannel; };

      # The dashboard (and Hermes Desktop's remote backend) on loopback only.
      backend = {
        mode = if cfg.dashboardPublicUrl != null then "dashboard" else "none";
        host = "127.0.0.1";
        port = dashboardPort;
      };

      settings = {
        providers.cliproxy = {
          api = config.dotfiles.ai.gateway.url;
          transport = "anthropic_messages";
          key_env = "CLIPROXY_API_KEY";
        };
        model = {
          provider = "cliproxy";
          default = sonnet;
        };
        # Side tasks stay on the gateway too: cheap ones on Haiku, the rest on the main model.
        auxiliary = {
          title_generation = { provider = "cliproxy"; model = haiku; };
          compression = { provider = "cliproxy"; model = sonnet; };
          vision = { provider = "main"; };
          background_review = { provider = "main"; };
          curator = { provider = "main"; };
        };

        secrets.command = {
          enabled = true;
          command = "${secretsHelper}";
          override_existing = true;
          helper_timeout_seconds = 10;  # six Keychain reads
        };

        mcp_servers.inbox = {
          command = "/usr/bin/python3";
          args = [ "-I" "${inboxMonitor}/inbox_mcp.py" ];
          env = {
            INBOX_STATE_DIR = stateDir;
            INBOX_GWS = "/opt/homebrew/bin/gws";
            INBOX_GH = "${pkgs.gh}/bin/gh";
            PATH = "/usr/bin:/bin";
          };
          timeout = 280;
        };
        # Chat gets everything Hermes ships for Slack (the owner's choice,
        # see docs) but no MCP servers; cron jobs get only the inbox tools.
        platform_toolsets = {
          slack = [ "hermes-slack" "no_mcp" ];
          cli = [ "hermes-cli" "no_mcp" ];  # CLI, TUI, Desktop and dashboard chats
          cron = [ "mcp-inbox" ];
        };

        skills.external_dirs = [ "${skillsDir}" "${chatSkillsDir}" ] ++ cfg.extraSkillDirs;
        terminal = lib.optionalAttrs (cfg.terminalCwd != null) { cwd = cfg.terminalCwd; };

        # Web dashboard (backend below), reachable only through tailscale serve.
        # A non-loopback public_url engages the sign-in gate even though the
        # listener is on loopback; with no password hash the listener refuses to start.
        dashboard = {
          basic_auth = {
            username = config.home.username;
            session_ttl_seconds = 43200;
          };
        } // lib.optionalAttrs (cfg.dashboardPublicUrl != null) { public_url = cfg.dashboardPublicUrl; };

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
        # Chat history is kept for good (owner's choice); the daily prune job
        # removes cron sessions after a day.
        sessions.auto_prune = false;
      };
    };

    launchd.agents.hermes-agent.config = {
      ProgramArguments = lib.mkForce [ "/bin/zsh" "-f" "${gatewayWrapper}" ];
      ExitTimeOut = 60;
      ThrottleInterval = lib.mkForce 30;
    };

    launchd.agents.inbox-monitor-deadman = {
      enable = true;
      config = {
        Label = "com.ksotis.inbox-monitor-deadman";
        ProgramArguments = [ "/usr/bin/python3" "-I" "${inboxMonitor}/deadman.py" ];
        StartInterval = 1800;
        StandardOutPath = "${home}/Library/Logs/inbox-monitor-deadman.log";
        StandardErrorPath = "${home}/Library/Logs/inbox-monitor-deadman.log";
      };
    };

    # pass -> login Keychain on every rebuild (and by hand: hermes-keychain-sync).
    home.activation.hermesKeychain = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        ${keychainSync}/bin/hermes-keychain-sync \
          || errorEcho "hermes: Keychain sync incomplete (see above). Fix it, then run hermes-keychain-sync at the console."
      fi
    '';

    # Dashboard sign-in material, kept out of the store, argv and logs: the
    # owner's password (pass hermes/dashboard-password) is hashed with Hermes'
    # own scrypt helper, password on stdin; the token-signing secret is made once.
    home.activation.hermesDashboardAuth = lib.hm.dag.entryAfter [ "hermesKeychain" ] ''
      (
        set +e -u +x
        ${lib.optionalString ((config.programs.password-store.settings.PASSWORD_STORE_DIR or "") != "")
          "export PASSWORD_STORE_DIR=${lib.escapeShellArg config.programs.password-store.settings.PASSWORD_STORE_DIR}"}
        store=''${PASSWORD_STORE_DIR:-$HOME/.password-store}
        put() {  # put <account> <value>: Keychain item hermes-agent/<account>, value on stdin
          printf 'add-generic-password -U -s hermes-agent -a %s -T /usr/bin/security -w "%s"\n' "$1" "$2" \
            | /usr/bin/security -i >/dev/null 2>&1
          [ "$(/usr/bin/security find-generic-password -s hermes-agent -a "$1" -w 2>/dev/null)" = "$2" ]
        }
        if [ -z "''${DRY_RUN_CMD:-}" ]; then
          hpy="$(${pkgs.gnused}/bin/sed -n 's/^exec "\(.*\)\/hermes" .*/\1/p' ${hermesBin})/python3"
          if [ ! -f "$store/hermes/dashboard-password.gpg" ]; then
            noteEcho "hermes: pass entry hermes/dashboard-password does not exist; the dashboard will not start until it does"
          elif ! pw=$(${timeout} 60 ${config.programs.password-store.package}/bin/pass show hermes/dashboard-password 2>/dev/null | head -n 1) || [ -z "$pw" ]; then
            errorEcho "hermes: could not decrypt pass entry hermes/dashboard-password (gpg passphrase prompt not answered); dashboard password not updated"
          else
            old=$(/usr/bin/security find-generic-password -s hermes-agent -a dashboard-password-hash -w 2>/dev/null)
            # Keep the stored hash while it still matches (a fresh salt each rebuild would churn).
            if [ -n "$old" ] && printf '%s' "$pw" | OLD="$old" "$hpy" -I -c 'import os, sys; from plugins.dashboard_auth.basic import _verify_password; sys.exit(0 if _verify_password(sys.stdin.read(), os.environ["OLD"]) else 1)' 2>/dev/null; then
              :
            else
              hash=$(printf '%s' "$pw" | "$hpy" -I -c 'import sys; from plugins.dashboard_auth.basic import hash_password; print(hash_password(sys.stdin.read()))' 2>/dev/null)
              case "$hash" in
                *[!A-Za-z0-9\$._+/=:-]*|"") errorEcho "hermes: could not hash the dashboard password" ;;
                *)
                  if put dashboard-password-hash "$hash"; then
                    noteEcho "hermes: dashboard password updated"
                    /bin/launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.hermes-backend" >/dev/null 2>&1 || true
                  else
                    errorEcho "hermes: could not store the dashboard password hash in the login Keychain (rebuild from the console session)"
                  fi ;;
              esac
            fi
          fi
          if ! /usr/bin/security find-generic-password -s hermes-agent -a dashboard-session-secret -w >/dev/null 2>&1; then
            put dashboard-session-secret "$(${pkgs.openssl}/bin/openssl rand -base64 48 | tr -d '\n')" \
              || errorEcho "hermes: could not store the dashboard session secret"
          fi
        fi
        unset pw hash old
      )
    '';

    # tailscale serve for the dashboard. States: free (nothing on 443), ours
    # (exactly 443 -> the loopback dashboard, no Funnel), other (anything else),
    # unknown (status or jq failed). Only free is claimed, and only ours is
    # removed when the dashboard is turned off; other and unknown just warn.
    home.activation.hermesTailscaleServe = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      (
        set +e -u
        ts=/opt/homebrew/bin/tailscale
        jq=${pkgs.jq}/bin/jq
        target=${lib.escapeShellArg serveTarget}
        state=unknown
        if [ -x "$ts" ] && out=$($ts serve status --json 2>/dev/null) && [ -n "$out" ]; then
          state=$(printf '%s' "$out" | $jq -r --arg t "$target" '
            [.Web // {} | to_entries[] | select(.key | endswith(":443"))] as $w
            | if (.TCP["443"] == null and ($w | length) == 0) then "free"
              elif (.TCP["443"] == {"HTTPS": true} and ($w | length) == 1
                    and $w[0].value == {"Handlers": {"/": {"Proxy": $t}}}
                    and ((.AllowFunnel // {})[$w[0].key] // false) == false) then "ours"
              else "other" end' 2>/dev/null) || state=unknown
          [ -n "$state" ] || state=unknown
        fi
        ${if cfg.dashboardPublicUrl != null then ''
          case "$state" in
            ours) ;;
            free) $DRY_RUN_CMD $ts serve --bg --https=443 "$target" >/dev/null 2>&1 \
                    || errorEcho "hermes: tailscale serve failed; run: tailscale serve --bg --https=443 ${serveTarget}" ;;
            other) warnEcho "hermes: tailscale serve already uses HTTPS 443 for something else; not changing it (tailscale serve status)" ;;
            *) warnEcho "hermes: couldn't read tailscale serve status; dashboard mapping not checked" ;;
          esac
        '' else ''
          case "$state" in
            ours) $DRY_RUN_CMD $ts serve --https=443 off >/dev/null 2>&1 \
                    || warnEcho "hermes: could not remove the dashboard's tailscale serve mapping (tailscale serve --https=443 off)" ;;
          esac
        ''}
      )
    '';

    home.packages = [
      keychainSync
      # Creates the paused monitor job and the daily prune job (and removes the
      # retired inbox-digest job), then checks them.
      # Idempotent; run once after the first switch (docs/ai-setup.md).
      (pkgs.writeShellScriptBin "hermes-inbox-jobs" ''
        set -eu
        exec /usr/bin/python3 -I ${./hermes-inbox-jobs.py} \
          --hermes ${hermesBin} --hermes-home ${hermesHome} --state-dir ${stateDir} \
          --prune-script ${pruneScript} --model ${sonnet}
      '')
    ];
  };
}
