{ config, lib, pkgs, ... }:

# Hermes Agent (Nous Research, https://hermes-agent.nousresearch.com) on the AI
# hub: the owner's always-on agent, reachable as a Slack DM bot, plus the inbox
# monitor as one of its cron jobs. Imported by nixpkgs/hosts/garage-hq.nix.
# Guide and the accepted risk: docs/ai-setup.md, "Hermes Agent".
#
# Hermes itself is NOT installed by Nix: it is a normal, mutable install from
# its own installer (~/.hermes/hermes-agent, command ~/.local/bin/hermes), so
# the dashboard and the apps can install skills, plugins and MCP servers, edit
# config.yaml and run `hermes update`. Its gateway runs as Hermes' own launchd
# job ai.hermes.gateway (`hermes gateway install`), so `hermes gateway restart`,
# the dashboard's System page and `hermes update` drive that job instead of
# starting a second, unmanaged gateway. This module keeps our plumbing around it:
# Keychain secrets, the inbox MCP code and skills (stable links), the dashboard
# launchd job, tailscale serve, the dead-man and hermes-config-check (our config
# rules, restored at every rebuild and checked every 15 minutes).
#
# Secrets: pass is the source of truth. The gpg key has a passphrase, so a
# launchd start can't read pass; activation (an interactive rebuild) copies the
# entries into the login Keychain and the processes read them from there:
#   service hermes-agent:  cliproxy-api-key, slack-bot-token, slack-app-token,
#                          slack-owner-id  -> Hermes, via `secrets.command`
#   service inbox-monitor: slack-user-token -> only the inbox MCP server reads it
# Nothing secret or personal is written to ~/.hermes/.env, config.yaml or the
# Nix store; hermes-config-check reports secret-looking keys that appear there.
let
  home = config.home.homeDirectory;
  hermesHome = "${home}/.hermes";
  stateDir = "${home}/.local/state/inbox-monitor";
  hermesBin = "${home}/.local/bin/hermes";  # published by Hermes' installer
  # Stable paths for config.yaml (it outlives rebuilds now): links into the store.
  share = "${home}/.local/share/hermes-inbox";
  secretsPath = "${home}/.local/bin/hermes-secrets";
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
    "hermes-agent/api-server-key" = "hermes/api-server-key";
    "hermes-agent/dashboard-session-token" = "hermes/dashboard-session-token";
  };
  # Environment variable -> Keychain account (service hermes-agent), for Hermes.
  hermesEnv = {
    CLIPROXY_API_KEY = "cliproxy-api-key";
    SLACK_BOT_TOKEN = "slack-bot-token";
    SLACK_APP_TOKEN = "slack-app-token";
    # Dashboard sign-in (basic provider): the scrypt hash of the owner's password
    # and the token-signing secret, both made at activation (see below).
    HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH = "dashboard-password-hash";
    HERMES_DASHBOARD_BASIC_AUTH_SECRET = "dashboard-session-secret";
    # API server bearer key (the API server refuses to start without it).
    API_SERVER_KEY = "api-server-key";
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
    # Dashboard deployment token for token-mode clients (Hermes Desktop's remote
    # gateway, the mobile app's Bot Mode): bearer REST + /api/ws ?token=. Only a
    # token of 32+ characters is handed over.
    t=$(/usr/bin/security find-generic-password -s hermes-agent -a dashboard-session-token -w 2>/dev/null)
    [ "''${#t}" -ge 32 ] && printf 'HERMES_DASHBOARD_SESSION_TOKEN=%s\n' "$t"
    unset t
    # Who July answers: the owner (Keychain) plus the colleagues from the private overlay.
    owner=$(/usr/bin/security find-generic-password -s hermes-agent -a slack-owner-id -w 2>/dev/null)
    [ -n "$owner" ] && printf 'SLACK_ALLOWED_USERS=%s\n' "$owner${lib.concatMapStrings (id: ",${id}") cfg.colleagueSlackIds}"
    exit 0
  '';

  # The monitor's code, read-only in the store. State and config.json stay in
  # ~/.local/state/inbox-monitor (see hermes/inbox-monitor/README.md).
  inboxMonitor = pkgs.runCommand "inbox-monitor" { } ''
    mkdir -p $out
    cp ${../../../hermes/inbox-monitor}/{inbox_mcp.py,personal_mcp.py,im,reminders.js,docs_text.js,fetch_gmail.py,deadman.py} $out/
    chmod 0555 $out/inbox_mcp.py $out/personal_mcp.py $out/im $out/fetch_gmail.py $out/deadman.py
    chmod 0444 $out/reminders.js $out/docs_text.js
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
  apiPort = 8642;        # Hermes' OpenAI-compatible API server, loopback only
  apiServePort = 8443;   # its tailnet HTTPS port
  apiTarget = "http://127.0.0.1:${toString apiPort}";

  # The dashboard as our own launchd job. Not Home Manager's launchd.agents: that
  # wraps every job in `/bin/sh -c "wait4path … && exec …"`, and Hermes only
  # recognises a launchd-supervised dashboard (for `hermes update`'s restart)
  # when ProgramArguments is the `hermes dashboard` command itself.
  dashboardLabel = "com.ksotis.hermes-dashboard";
  dashboardPlist = pkgs.writeText "${dashboardLabel}.plist" (lib.generators.toPlist { escape = true; } {
    Label = dashboardLabel;
    ProgramArguments = [ hermesBin "dashboard" "--host" "127.0.0.1" "--port" (toString dashboardPort) "--no-open" ];
    EnvironmentVariables = {
      HERMES_HOME = hermesHome;
      PATH = lib.concatStringsSep ":" [ "${home}/.local/bin" "/etc/profiles/per-user/${config.home.username}/bin"
        "/run/current-system/sw/bin" "/nix/var/nix/profiles/default/bin" "/opt/homebrew/bin" "/usr/bin" "/bin" "/usr/sbin" "/sbin" ];
    };
    WorkingDirectory = home;
    RunAtLoad = true;
    KeepAlive = true;
    ThrottleInterval = 5;
    ProcessType = "Background";
    StandardOutPath = "${home}/Library/Logs/hermes-backend.log";
    StandardErrorPath = "${home}/Library/Logs/hermes-backend.err.log";
  });

  # Daily housekeeping (a no-agent Hermes cron job): monitor sessions, run
  # documents and spilled tool output 1 day; chat sessions are kept
  # (sessions.auto_prune off), but their spilled tool output goes too.
  # Copied into ~/.hermes/scripts, so it uses the system shell (no store path to go stale).
  pruneScript = pkgs.writeScript "hermes-prune" ''
    #!/bin/bash
    set -u
    ${hermesBin} sessions prune --source cron --older-than 1 --yes >/dev/null 2>&1 || echo "hermes-prune: session prune failed"
    find ${hermesHome}/cron/output ${hermesHome}/cache/spillover -type f -mmin +1440 -delete 2>/dev/null
    for f in ${hermesHome}/logs/gateway.log ${hermesHome}/logs/gateway.error.log \
             ${home}/Library/Logs/hermes-backend.log ${home}/Library/Logs/hermes-backend.err.log; do
      [ -f "$f" ] && [ "$(stat -f %z "$f")" -gt 5000000 ] && : > "$f"
    done
    echo "[SILENT]"
  '';

  # ── config.yaml rules for hermes-config-check ─────────────────────────────
  # `rules` are ours and restored when they drift (safety and plumbing);
  # `defaults` are seeded once and then belong to Hermes, the dashboard and the
  # owner (model choice, skills, memory …).
  mcpServer = script: {
    command = "/usr/bin/python3";
    args = [ "-I" "${share}/code/${script}" ];
    env = {
      INBOX_STATE_DIR = stateDir;
      INBOX_GWS = "/opt/homebrew/bin/gws";
      INBOX_GH = "/etc/profiles/per-user/${config.home.username}/bin/gh";  # stable, unlike a store path
      PATH = "/usr/bin:/bin";
    };
    timeout = 280;
  };
  # Colleagues have every tool (owner's choice) but are regular users for slash
  # commands: plain chat plus these. Answering a dangerous-command approval is
  # /approve or /deny, which only the owner (the admin) may run, so a colleague
  # can't approve even their own command.
  userCommands = [ "help" "whoami" "commands" "new" "stop" "retry" "undo" "title" "save"
                   "resume" "sessions" "usage" "btw" "queue" "steer" "compress" "context" ];
  # `auto`: the security subset, which the 15-minute agent restores by itself
  # (and DMs about); the rest is restored at the next rebuild and only reported.
  eq = path: value: { inherit path value; op = "equals"; auto = true; };
  chatPlatforms = [ "slack" "cli" "api_server" "acp" "tui" "webhook" ];
  rules = [
    (eq [ "secrets" "command" ] {
      enabled = true;
      command = secretsPath;
      override_existing = true;
      helper_timeout_seconds = 10;  # seven Keychain reads
    })
    (eq [ "mcp_servers" "inbox" ] (mcpServer "inbox_mcp.py"))
    # The owner's own data tools for chat (owner's choice: unmasked Slack-as-owner,
    # Gmail, Reminders in any list, GitHub PRs). No monitor bookkeeping in it.
    (eq [ "mcp_servers" "personal" ] (mcpServer "personal_mcp.py"))
    # Naming servers makes a platform's list an allowlist: the monitor's inbox
    # server stays cron-only, chat keeps its preset plus the personal server
    # (and whatever else the owner adds from the dashboard).
    (eq [ "platform_toolsets" "cron" ] [ "mcp-inbox" ])
  ] ++ lib.concatMap (p: [
    # A platform without its own list gets EVERY enabled MCP server (inbox too),
    # so each chat surface Hermes has (acp, tui, webhook included) gets a list.
    { path = [ "platform_toolsets" p ]; op = "contains"; value = [ "hermes-${lib.replaceStrings [ "_" ] [ "-" ] p}" "mcp-personal" ]; auto = true; }
    { path = [ "platform_toolsets" p ]; op = "excludes"; value = [ "mcp-inbox" ]; auto = true; }
  ]) chatPlatforms ++ [
    # The monitor's skill and the chat skills (stable links; extra dirs too).
    { path = [ "skills" "external_dirs" ]; op = "contains"; value = skillDirs; drop_prefix = "/nix/store/"; }
    # Web dashboard, reachable only through tailscale serve. A non-loopback
    # public_url engages the sign-in gate although the listener is on loopback;
    # with no password hash the listener refuses to start.
    (eq [ "dashboard" "basic_auth" "username" ] config.home.username)
    (eq [ "unauthorized_dm_behavior" ] "ignore")
    (eq [ "slack" "unauthorized_dm_behavior" ] "ignore")
    (eq [ "slack" "require_mention" ] true)
    (eq [ "slack" "free_response_channels" ] "")
    # The owner chose smart approvals (2026-11-23): an auxiliary model approves low-risk
    # commands (code exploration), denies clearly dangerous ones and escalates the rest to the owner.
    (eq [ "approvals" "mode" ] "smart")
    (eq [ "approvals" "smart_policy" ] (lib.concatStringsSep " " [
      "Approve read-only code and docs exploration (reading, searching, listing, git log/diff/show)."
      "ESCALATE, never approve: sending data off this machine (curl/wget with a body or upload, scp, rsync, nc, webhooks);"
      "reading secrets (security find-generic-password, pass show, ~/.ssh, .env files, cloud credentials);"
      "package or tool installs; git push, merge or tag; and anything that changes a cluster, cloud or database"
      "(kubectl apply/delete/edit/scale/patch/exec/rollout, helm, terraform apply, aws/gcloud writes, SQL writes)."
    ]))
    (eq [ "approvals" "cron_mode" ] "deny")
    (eq [ "approvals" "single_query_mode" ] "deny")
    (eq [ "approvals" "unattended_mode" ] "deny")
    # Narrowing approvals.approvers lets every requester approve their own commands.
    { path = [ "approvals" "approvers" ]; op = "absent"; auto = true; }
    (eq [ "security" "redact_secrets" ] true)
  ] ++ lib.concatLists (lib.mapAttrsToList (task: model: [
    # Side tasks pinned to the model gateway: `provider: main` resolved to a generic
    # "custom" provider with no endpoint, and vision failed with "connection error".
    (eq [ "auxiliary" task "provider" ] "cliproxy")
    (eq [ "auxiliary" task "model" ] model)
  ]) {
    title_generation = haiku;
    approval = sonnet;
    compression = sonnet;
    vision = sonnet;
    background_review = sonnet;
    curator = sonnet;
  }) ++ lib.optional (cfg.dashboardPublicUrl != null) (eq [ "dashboard" "public_url" ] cfg.dashboardPublicUrl)
    ++ lib.optionals (cfg.ownerSlackId != null) [
    (eq [ "slack" "allow_admin_from" ] [ cfg.ownerSlackId ])
    (eq [ "slack" "group_allow_admin_from" ] [ cfg.ownerSlackId ])
    (eq [ "slack" "user_allowed_commands" ] userCommands)
    (eq [ "slack" "group_user_allowed_commands" ] userCommands)
    # The owner's posts through another Slack app with their user token (the
    # Claude app: app_id, no client_msg_id) look like bot messages to Hermes and
    # were dropped; these users' API posts count as human.
    (eq [ "platforms" "slack" "extra" "api_human_users" ] [ cfg.ownerSlackId ])
  ];
  defaults = lib.mapAttrsToList (k: value: { path = lib.splitString "." k; inherit value; }) ({
    "providers.cliproxy" = {
      api = config.dotfiles.ai.gateway.url;
      transport = "anthropic_messages";
      key_env = "CLIPROXY_API_KEY";
    };
    "model" = { provider = "cliproxy"; default = sonnet; };
    "dashboard.basic_auth.session_ttl_seconds" = 43200;
    "memory.memory_enabled" = true;  # built-in, local files only; no external provider
    # Chat history is kept for good (owner's choice); the daily prune job
    # removes cron sessions after a day.
    "sessions.auto_prune" = false;
  } // lib.optionalAttrs (cfg.terminalCwd != null) { "terminal.cwd" = cfg.terminalCwd; });
  skillDirs = [ "${share}/skills" "${share}/chat-skills" ]
    ++ lib.imap0 (i: _: "${share}/extra-skills/${toString i}") cfg.extraSkillDirs;
  # Non-secret .env keys Hermes reads at start.
  envRules = {
    HERMES_CRON_TIMEOUT = "600";
  } // lib.optionalAttrs cfg.apiServer {
    API_SERVER_ENABLED = "true";
    API_SERVER_HOST = "127.0.0.1";
    API_SERVER_PORT = toString apiPort;
  } // lib.optionalAttrs (cfg.slackHomeChannel != null) { SLACK_HOME_CHANNEL = cfg.slackHomeChannel; };
  checkSpec = pkgs.writeText "hermes-config-check.json" (builtins.toJSON {
    hermes_home = hermesHome;
    state_file = "${stateDir}/.config-check.json";
    deadman = "${share}/code/deadman.py";
    inherit rules defaults;
    env = envRules;
    env_absent = lib.optionals (!cfg.apiServer) [ "API_SERVER_ENABLED" ];
    soul = if cfg.soulFile != null then "${cfg.soulFile}" else null;
    gateway_label = "ai.hermes.gateway";
    dashboard_label = dashboardLabel;
    hermes_bin = hermesBin;
    hermes_root = "${hermesHome}/hermes-agent";
    chat_platforms = chatPlatforms ++ [ "cron" ];
    cron_only_server = "inbox";
    dashboard_port = if cfg.dashboardPublicUrl != null then dashboardPort else null;
    api_port = if cfg.apiServer then apiPort else null;
  });
  configCheck = pkgs.writeShellScriptBin "hermes-config-check" ''
    exec ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 -I ${./hermes-config-check.py} --spec ${checkSpec} "$@"
  '';

in
{
  config = {
    assertions = [{
      assertion = cfg.colleagueSlackIds == [ ] || cfg.ownerSlackId != null;
      message = "dotfiles.ai.hermes.colleagueSlackIds needs dotfiles.ai.hermes.ownerSlackId, or the owner-only approval gating disappears.";
    }];

    # Stable links into the store for config.yaml, which now outlives rebuilds.
    home.file = {
      ".local/bin/hermes-secrets".source = secretsHelper;
      ".local/share/hermes-inbox/code".source = inboxMonitor;
      ".local/share/hermes-inbox/skills".source = skillsDir;
      ".local/share/hermes-inbox/chat-skills".source = chatSkillsDir;
    } // lib.listToAttrs (lib.imap0 (i: dir: lib.nameValuePair ".local/share/hermes-inbox/extra-skills/${toString i}" {
      source = config.lib.file.mkOutOfStoreSymlink dir;
    }) cfg.extraSkillDirs);

    # Hermes' installer adds ~/.local/bin to PATH in ~/.zprofile unless a line
    # there already does; that file is a read-only store link, so the append
    # would fail the install. This is the line it looks for.
    programs.zsh.profileExtra = ''
      case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
    '';

    # Every minute: the inbox monitor's dead-man (DM after an hour without a
    # successful cycle) and the Slack safeguard (5 min unhealthy -> one graceful
    # gateway restart and a DM; alert and no more restarts if that doesn't heal it).
    launchd.agents.inbox-monitor-deadman = {
      enable = true;
      config = {
        Label = "com.ksotis.inbox-monitor-deadman";
        ProgramArguments = [ "/usr/bin/python3" "-I" "${inboxMonitor}/deadman.py" ];
        EnvironmentVariables = { HERMES_HOME = hermesHome; HERMES_BIN = hermesBin; };
        StartInterval = 60;
        StandardOutPath = "${home}/Library/Logs/inbox-monitor-deadman.log";
        StandardErrorPath = "${home}/Library/Logs/inbox-monitor-deadman.log";
      };
    };

    # Every 30 minutes and whenever config.yaml or .env change: restores the
    # security rules (DM + graceful gateway restart when needed) and checks the
    # rest and the runtime (one gateway under ai.hermes.gateway, no unmanaged
    # runtime job, loopback listeners, resolved toolsets). DMs the owner when a
    # problem stays unchanged for 20 minutes, and when it clears.
    launchd.agents.hermes-config-check = {
      enable = true;
      config = {
        Label = "com.ksotis.hermes-config-check";
        ProgramArguments = [ "${configCheck}/bin/hermes-config-check" "--auto" "--alert" "--quiet" ];
        StartInterval = 1800;
        WatchPaths = [ "${hermesHome}/config.yaml" "${hermesHome}/.env" ];
        ThrottleInterval = 60;
        StandardOutPath = "${home}/Library/Logs/hermes-config-check.log";
        StandardErrorPath = "${home}/Library/Logs/hermes-config-check.log";
      };
    };

    # Our config rules into the live config.yaml/.env at every rebuild (replaces
    # the Nix module's deep merge). Skipped until Hermes is installed.
    home.activation.hermesConfig = lib.hm.dag.entryAfter [ "linkGeneration" "hermesKeychain" ] ''
      if [ -z "''${DRY_RUN_CMD:-}" ] && [ -f ${hermesHome}/config.yaml ]; then
        ${configCheck}/bin/hermes-config-check --fix --quiet \
          || warnEcho "hermes: hermes-config-check reports problems (above)"
      elif [ ! -f ${hermesHome}/config.yaml ]; then
        noteEcho "hermes: ~/.hermes/config.yaml not found; install Hermes (docs/ai-setup.md), then rebuild"
      fi
    '';

    # The dashboard job: a real file in ~/Library/LaunchAgents (launchd ignores
    # symlinked plists), reloaded when it changes. Waits for Hermes' command.
    home.activation.hermesDashboard = lib.hm.dag.entryAfter [ "linkGeneration" "hermesDashboardAuth" ] ''
      (
        set +e -u
        dst=${home}/Library/LaunchAgents/${dashboardLabel}.plist
        target=gui/$(id -u)/${dashboardLabel}
        if [ ${if cfg.dashboardPublicUrl != null then "1" else "0"} = 0 ]; then
          if [ -f "$dst" ]; then
            $DRY_RUN_CMD /bin/launchctl bootout "$target" 2>/dev/null
            $DRY_RUN_CMD rm -f "$dst"
          fi
        elif [ ! -x ${hermesBin} ]; then
          noteEcho "hermes: ${hermesBin} not found; dashboard job not installed yet"
        elif ! cmp -s ${dashboardPlist} "$dst" || ! /bin/launchctl print "$target" >/dev/null 2>&1; then
          $DRY_RUN_CMD /bin/launchctl bootout "$target" 2>/dev/null
          $DRY_RUN_CMD install -m 0644 ${dashboardPlist} "$dst"
          $DRY_RUN_CMD /bin/launchctl bootstrap "gui/$(id -u)" "$dst" \
            || errorEcho "hermes: could not load ${dashboardLabel} (launchctl bootstrap gui/$(id -u) $dst)"
        fi
      )
    '';

    # pass -> login Keychain on every rebuild (and by hand: hermes-keychain-sync).
    home.activation.hermesKeychain = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        ${keychainSync}/bin/hermes-keychain-sync \
          || errorEcho "hermes: Keychain sync incomplete (see above). Fix it, then run hermes-keychain-sync at the console."
      fi
    '';

    # The owner id lives in two places (pass/Keychain for SLACK_ALLOWED_USERS, the
    # private overlay for the admin gating); they must agree.
    home.activation.hermesOwnerCheck = lib.mkIf (cfg.ownerSlackId != null)
      (lib.hm.dag.entryAfter [ "hermesKeychain" ] ''
        k=$(/usr/bin/security find-generic-password -s hermes-agent -a slack-owner-id -w 2>/dev/null)
        if [ -n "$k" ] && [ "$k" != ${lib.escapeShellArg cfg.ownerSlackId} ]; then
          errorEcho "hermes: pass hermes/slack-owner-id and dotfiles.ai.hermes.ownerSlackId differ; fix one so the allowlist and the admin are the same person"
        fi
        unset k
      '');

    # Dashboard sign-in material, kept out of the store, argv and logs: the
    # owner's password (pass hermes/dashboard-password) is hashed with Hermes'
    # scrypt format (hermes-dashboard-password.py), password on stdin; the
    # token-signing secret is made once.
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
          hpy=${pkgs.python3}/bin/python3
          if [ ! -f "$store/hermes/dashboard-password.gpg" ]; then
            noteEcho "hermes: pass entry hermes/dashboard-password does not exist; the dashboard will not start until it does"
          elif ! pw=$(${timeout} 60 ${config.programs.password-store.package}/bin/pass show hermes/dashboard-password 2>/dev/null | head -n 1) || [ -z "$pw" ]; then
            errorEcho "hermes: could not decrypt pass entry hermes/dashboard-password (gpg passphrase prompt not answered); dashboard password not updated"
          else
            old=$(/usr/bin/security find-generic-password -s hermes-agent -a dashboard-password-hash -w 2>/dev/null)
            # Keep the stored hash while it still matches (a fresh salt each rebuild would churn).
            if [ -n "$old" ] && printf '%s' "$pw" | OLD="$old" "$hpy" -I ${./hermes-dashboard-password.py} verify 2>/dev/null; then
              :
            else
              hash=$(printf '%s' "$pw" | "$hpy" -I ${./hermes-dashboard-password.py} hash 2>/dev/null)
              case "$hash" in
                *[!A-Za-z0-9\$._+/=:-]*|"") errorEcho "hermes: could not hash the dashboard password" ;;
                *)
                  if put dashboard-password-hash "$hash"; then
                    noteEcho "hermes: dashboard password updated"
                    /bin/launchctl kickstart -k "gui/$(id -u)/${dashboardLabel}" >/dev/null 2>&1 || true
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

    # tailscale serve, one HTTPS port per service (tailnet only, never Funnel).
    # States per port: free (nothing there), ours (exactly that port -> our
    # loopback target, no Funnel), other (anything else), unknown (status or jq
    # failed). Only free is claimed; only ours is removed when a service is
    # turned off; other and unknown just warn.
    home.activation.hermesTailscaleServe = lib.hm.dag.entryAfter [ "writeBoundary" "hermesKeychain" ] ''
      (
        set +e -u
        ts=/opt/homebrew/bin/tailscale
        jq=${pkgs.jq}/bin/jq
        out=""
        [ -x "$ts" ] && out=$($ts serve status --json 2>/dev/null) || out=""
        serve_state() {  # port target [v1-target]: free | ours | oursv1 (plus /v1 -> v1-target) | other | unknown
          [ -n "$out" ] || { echo unknown; return; }
          st=$(printf '%s' "$out" | $jq -r --arg p "$1" --arg t "$2" --arg v "''${3:-}" '
            [.Web // {} | to_entries[] | select(.key | endswith(":" + $p))] as $w
            | if ((.TCP // {})[$p] == null and ($w | length) == 0) then "free"
              elif ((.TCP // {})[$p] == {"HTTPS": true} and ($w | length) == 1
                    and ((.AllowFunnel // {})[$w[0].key] // false) == false) then
                (if $w[0].value == {"Handlers": {"/": {"Proxy": $t}}} then "ours"
                 elif ($v != "" and $w[0].value == {"Handlers": {"/": {"Proxy": $t}, "/v1": {"Proxy": $v}}}) then "oursv1"
                 else "other" end)
              else "other" end' 2>/dev/null) || st=unknown
          echo "''${st:-unknown}"
        }
        serve_map() {  # port target want(on|off) name
          case "$3:$(serve_state "$1" "$2")" in
            on:ours|on:oursv1|off:free|off:other|off:unknown) ;;
            on:free) $DRY_RUN_CMD $ts serve --bg --https="$1" "$2" >/dev/null 2>&1 \
                       || errorEcho "hermes: tailscale serve failed for the $4; run: tailscale serve --bg --https=$1 $2" ;;
            on:other) warnEcho "hermes: tailscale serve already uses HTTPS $1 for something else; $4 not published (tailscale serve status)" ;;
            on:unknown) warnEcho "hermes: couldn't read tailscale serve status; $4 mapping on $1 not checked" ;;
            off:ours|off:oursv1) $DRY_RUN_CMD $ts serve --https="$1" off >/dev/null 2>&1 \
                        || warnEcho "hermes: could not remove the $4's tailscale serve mapping (tailscale serve --https=$1 off)" ;;
          esac
        }
        api=${if cfg.apiServer && cfg.dashboardPublicUrl != null then "on" else "off"}
        # No key in the Keychain: the API server doesn't start, so don't publish it.
        if [ "$api" = on ]; then
          key=$(/usr/bin/security find-generic-password -s hermes-agent -a api-server-key -w 2>/dev/null)
          [ "''${#key}" -ge 16 ] || api=off
          unset key
        fi
        v1=${lib.escapeShellArg "${apiTarget}/v1"}
        # 443: the dashboard at /, and (with the API server on) /v1 -> the API server,
        # so one URL serves both the dashboard sign-in and the OpenAI-style API.
        serve_map 443 ${lib.escapeShellArg serveTarget} ${if cfg.dashboardPublicUrl != null then "on" else "off"} dashboard
        out=$($ts serve status --json 2>/dev/null) || out=""
        case "$api:$(serve_state 443 ${lib.escapeShellArg serveTarget} "$v1")" in
          on:ours) $DRY_RUN_CMD $ts serve --bg --https=443 --set-path /v1 "$v1" >/dev/null 2>&1 \
                     || errorEcho "hermes: tailscale serve failed for /v1; run: tailscale serve --bg --https=443 --set-path /v1 $v1" ;;
          off:oursv1) $DRY_RUN_CMD $ts serve --https=443 --set-path /v1 off >/dev/null 2>&1 \
                        || warnEcho "hermes: could not remove /v1 from the 443 mapping" ;;
        esac
        out=$($ts serve status --json 2>/dev/null) || out=""
        serve_map ${toString apiServePort} ${lib.escapeShellArg apiTarget} "$api" "API server"
      )
    '';

    home.packages = [
      keychainSync
      configCheck
      # Creates the paused monitor job and the daily prune job (and removes the
      # retired inbox-digest job), then checks them.
      # Idempotent; run once after the first switch (docs/ai-setup.md).
      (pkgs.writeShellScriptBin "hermes-inbox-jobs" ''
        set -eu
        exec /usr/bin/python3 -I ${./hermes-inbox-jobs.py} \
          --hermes ${hermesBin} --hermes-home ${hermesHome} \
          --state-dir ${stateDir} \
          --prune-script ${pruneScript} --model ${sonnet}
      '')
    ];
  };
}
