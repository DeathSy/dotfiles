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
  cfg = config.dotfiles.ai.hermes;
  timeout = "${pkgs.coreutils}/bin/timeout";
  sonnet = "claude-sonnet-5-5";
  haiku = "claude-haiku-5-5";

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
  };

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
    cp ${../../../hermes/inbox-monitor}/{inbox_mcp.py,im,reminders.js,fetch_gmail.py} $out/
    chmod 0555 $out/inbox_mcp.py $out/im $out/fetch_gmail.py
    chmod 0444 $out/reminders.js
  '';
  skillsDir = pkgs.linkFarm "hermes-inbox-skill" (lib.optional (cfg.inboxSkill != null) {
    name = "inbox-monitor/SKILL.md";
    path = cfg.inboxSkill;
  });

  # launchd runs /bin/zsh, which stays the job's root process: macOS TCC then
  # attributes the monitor's Reminders automation to "zsh" (allowed once)
  # instead of a nix-store Python that changes with every update.
  # Preflight: the gateway needs the model key; while the login Keychain is not
  # readable yet (just after a reboot) exit non-zero so launchd retries.
  # TERM/INT/HUP are forwarded to the recorded gateway pid, and zsh waits for it.
  gatewayWrapper = pkgs.writeText "hermes-gateway.zsh" ''
    for i in {1..12}; do
      ${timeout} 10 /usr/bin/security find-generic-password -s hermes-agent -a cliproxy-api-key -w >/dev/null 2>&1 && break
      (( i == 12 )) && { print -u2 "hermes-gateway: Keychain item hermes-agent/cliproxy-api-key not readable; retrying via launchd"; exit 75; }
      sleep 5
    done
    ${hermesBin} gateway ${lib.escapeShellArgs config.services.hermes-agent.extraArgs} "$@" &
    child=$!
    trap 'kill -TERM $child 2>/dev/null' TERM INT HUP
    wait $child; rc=$?
    while kill -0 $child 2>/dev/null; do wait $child; rc=$?; done
    exit $rc
  '';

  # Daily housekeeping (a no-agent Hermes cron job): monitor sessions and run
  # documents 1 day; chat sessions are kept (sessions.auto_prune off).
  pruneScript = pkgs.writeShellScript "hermes-prune" ''
    set -u
    ${hermesBin} sessions prune --source cron --older-than 1 --yes >/dev/null 2>&1 || echo "hermes-prune: session prune failed"
    find ${hermesHome}/cron/output -type f -mmin +1440 -delete 2>/dev/null
    for f in ${home}/Library/Logs/hermes-agent.log ${home}/Library/Logs/hermes-agent.err.log; do
      [ -f "$f" ] && [ "$(stat -f %z "$f")" -gt 5000000 ] && : > "$f"
    done
    echo "[SILENT]"
  '';

  # Dead-man check, outside Hermes: if the enabled monitor job has had no
  # successful cycle for an hour, DM the owner once; say so again once it recovers.
  deadman = pkgs.writeShellScript "inbox-monitor-deadman" ''
    set -u
    marker=${stateDir}/.deadman-alerted
    msg=$(/usr/bin/python3 -I - <<'PY'
    import json, os, time
    st = json.load(open("${stateDir}/state.json"))
    try:
        jobs = json.load(open("${hermesHome}/cron/jobs.json"))
        jobs = jobs.get("jobs", jobs) if isinstance(jobs, dict) else jobs
        job = next((j for j in jobs if j.get("name") == "inbox-monitor"), None)
    except (OSError, ValueError):
        job = None
    enabled = bool(job) and job.get("enabled", True) and not job.get("paused") and job.get("state") != "paused"
    last = st.get("last_ok_at") or 0
    # Before the first success, wait for an hour of attempts (12 logged cycles).
    late = time.time() - last > 3600 if last else len(st.get("log", [])) >= 12
    alerted = os.path.exists("${stateDir}/.deadman-alerted")
    if enabled and late and not alerted:
        print("ALERT Inbox monitor: no successful cycle since " + (time.strftime("%d %b %H:%M", time.localtime(last)) if last else "it started") + ". Check `hermes cron status` on garage-hq.")
    elif alerted and not late:
        print("OK Inbox monitor recovered.")
    PY
    ) || exit 0
    [ -z "$msg" ] && exit 0
    token=$(${timeout} 10 /usr/bin/security find-generic-password -s hermes-agent -a slack-bot-token -w 2>/dev/null) || exit 0
    owner=$(${timeout} 10 /usr/bin/security find-generic-password -s hermes-agent -a slack-owner-id -w 2>/dev/null) || exit 0
    body=$(/usr/bin/python3 -I -c 'import json,sys; print(json.dumps({"channel": sys.argv[1], "text": sys.argv[2]}))' "$owner" "''${msg#* }")
    # The token goes to curl on stdin (-K -), never on its command line.
    printf 'header = "Authorization: Bearer %s"\n' "$token" \
      | /usr/bin/curl -sS -K - -H 'Content-Type: application/json; charset=utf-8' --data "$body" \
          https://slack.com/api/chat.postMessage -o /dev/null --max-time 20 || exit 0
    case "$msg" in ALERT*) : > "$marker" ;; OK*) rm -f "$marker" ;; esac
  '';
in
{
  config = {
    programs.hermes-agent.enable = true;

    services.hermes-agent = {
      enable = true;
      gateway.enable = true;
      workingDirectory = home;

      environment.HERMES_CRON_TIMEOUT = "600";

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
          cron = [ "mcp-inbox" ];
        };

        skills.external_dirs = lib.optional (cfg.inboxSkill != null) "${skillsDir}";

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
      ProgramArguments = lib.mkForce [ "/bin/zsh" "${gatewayWrapper}" ];
      ExitTimeOut = 60;
      ThrottleInterval = lib.mkForce 30;
    };

    launchd.agents.inbox-monitor-deadman = {
      enable = true;
      config = {
        Label = "com.ksotis.inbox-monitor-deadman";
        ProgramArguments = [ "/bin/sh" "${deadman}" ];
        StartInterval = 1800;
        StandardOutPath = "${home}/Library/Logs/inbox-monitor-deadman.log";
        StandardErrorPath = "${home}/Library/Logs/inbox-monitor-deadman.log";
      };
    };

    # pass -> login Keychain on every rebuild. Values go to `security -i` on
    # stdin (never a command line), are read back to check, and an empty or
    # missing pass entry never overwrites an existing item.
    home.activation.hermesKeychain = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      (
        set -u +x
        ${lib.optionalString ((config.programs.password-store.settings.PASSWORD_STORE_DIR or "") != "")
          "export PASSWORD_STORE_DIR=${lib.escapeShellArg config.programs.password-store.settings.PASSWORD_STORE_DIR}"}
        pass=${config.programs.password-store.package}/bin/pass
        ${lib.concatStrings (lib.mapAttrsToList (item: entry: let
          svc = builtins.head (lib.splitString "/" item);
          acct = lib.last (lib.splitString "/" item);
        in ''
          if v=$(${timeout} 60 $pass show ${lib.escapeShellArg entry} 2>/dev/null | head -n 1) && [ -n "$v" ]; then
            case "$v" in
              *[!A-Za-z0-9._~+/=-]*) warnEcho "hermes: pass entry ${entry} has unexpected characters; Keychain not updated" ;;
              *)
                if [ -z "''${DRY_RUN_CMD:-}" ]; then
                  printf 'add-generic-password -U -s ${svc} -a ${acct} -T /usr/bin/security -w "%s"\n' "$v" \
                    | /usr/bin/security -i >/dev/null 2>&1
                  [ "$(/usr/bin/security find-generic-password -s ${svc} -a ${acct} -w 2>/dev/null)" = "$v" ] \
                    || errorEcho "hermes: could not store ${item} in the login Keychain (locked, or an SSH session without access?). Rebuild from the console session."
                fi ;;
            esac
          else
            noteEcho "hermes: pass entry ${entry} not found; Keychain item ${item} left as it is"
          fi
        '') keychainItems)}
        unset v
      )
    '';

    home.packages = [
      # Creates the paused monitor job and the daily prune job, then checks them.
      # Idempotent; run once after the first switch (docs/ai-setup.md).
      (pkgs.writeShellScriptBin "hermes-inbox-jobs" ''
        set -eu
        exec /usr/bin/python3 -I ${./hermes-inbox-jobs.py} \
          --hermes ${hermesBin} --hermes-home ${hermesHome} --state-dir ${stateDir} \
          --prune-script ${pruneScript} --model ${sonnet} \
          ${lib.optionalString (cfg.inboxSkill == null) "--no-monitor"}
      '')
    ];
  };
}
