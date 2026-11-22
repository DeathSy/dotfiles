#!/usr/bin/python3 -I
"""Dead-man checks for Hermes, run by launchd every minute outside Hermes.

Inbox monitor: while its cron job is enabled, DM the owner once when there has been no successful cycle
for an hour (or state.json can't be read), and once when it recovers. The hour counts from the later of
the last success and the moment the job was first seen enabled, so resuming a long-paused job doesn't
alert at once.

Slack: when the gateway's Slack connection has been unhealthy for 5 minutes, restart the gateway once
(`hermes gateway restart`, which drains running turns) and DM the owner. If Slack isn't healthy 10 minutes
after that restart, or it fails again within an hour of the last one, DM an alert and don't restart again
until it has recovered. Health comes from gateway_state.json (the platform state Hermes records) and, since
the Slack adapter's own Socket Mode reconnects never reach that file, from its log lines in agent.log.

The bot token and owner id come from the login Keychain; the token only travels in an HTTP header, never
on a command line.
"""
import datetime, http.client, json, os, re, subprocess, time, urllib.request

STATE_DIR = os.environ.get("INBOX_STATE_DIR") or os.path.expanduser("~/.local/state/inbox-monitor")
HERMES_HOME = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
MINE = os.path.join(STATE_DIR, ".deadman.json")
LATE = 3600
HERMES_BIN = os.environ.get("HERMES_BIN") or os.path.expanduser("~/.local/bin/hermes")
GATEWAY_LABEL = os.environ.get("HERMES_GATEWAY_LABEL") or "ai.hermes.gateway"
SLACK_ERRORS = 10     # consecutive failed Slack checks before one DM about the check itself
SLACK_DOWN = 300      # unhealthy this long -> one graceful gateway restart
SLACK_HEAL = 600      # still unhealthy this long after the restart -> alert, stop restarting
SLACK_QUIET = 180     # no bad Socket Mode line for this long ends an episode (flapping stays one episode)
RESTART_GAP = 3600    # at most one automatic restart per hour
LOG_TAIL = 3_000_000  # bytes of agent.log to read
LOG_LINE = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d),\d+ \w+ (\S+): (.*)$")
BAD_STATES = {"retrying", "fatal", "connecting", "disconnected"}


def keychain(account):
    try:
        p = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", "hermes-agent", "-a", account, "-w"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return p.stdout.strip() if p.returncode == 0 else ""


def send(text):
    token, owner = keychain("slack-bot-token"), keychain("slack-owner-id")
    if not token or not owner:
        print("deadman: bot token or owner id missing in the Keychain")
        return False
    req = urllib.request.Request("https://slack.com/api/chat.postMessage",
                                 data=json.dumps({"channel": owner, "text": text}).encode(),
                                 headers={"Authorization": f"Bearer {token}",
                                          "Content-Type": "application/json; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            body = json.load(r)
    except (OSError, ValueError, http.client.HTTPException) as e:
        print(f"deadman: Slack request failed: {e.__class__.__name__}")
        return False
    if not body.get("ok"):
        print(f"deadman: Slack refused the DM: {body.get('error')}")
        return False
    return True


def slack_events(text):
    """(time, "bad"/"good") Socket Mode events from agent.log text, since the last gateway start."""
    events = []
    for line in text.splitlines():
        m = LOG_LINE.match(line)
        if not m:
            continue
        stamp, logger, msg = m.groups()
        if logger == "gateway.run" and msg.startswith("Starting Hermes Gateway"):
            events = []
            continue
        if logger.startswith("slack_bolt"):
            if msg.startswith("A new session") and "has been established" in msg:
                kind = "good"
            elif msg.startswith(("Failed to connect", "Failed to run message listeners")) \
                    or ("seems to be already closed" in msg):
                kind = "bad"
            else:
                continue
        elif msg.startswith("[Slack] Socket Mode connected"):
            kind = "good"
        elif msg.startswith(("[Slack] Socket Mode unhealthy", "[Slack] Socket Mode reconnect failed")):
            kind = "bad"
        else:
            continue
        events.append((time.mktime(time.strptime(stamp, "%Y-%m-%d %H:%M:%S")), kind))
    return events


def pid_alive(pid):
    if not isinstance(pid, int) or pid <= 1:
        return False
    try:
        os.kill(pid, 0)
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def slack_unhealthy_since(now, events, gateway_state, job_pid=None):
    """When the current Slack outage began, or None if Slack is healthy now.

    Log: an episode is a run of bad lines less than SLACK_QUIET apart; a reconnect that drops again
    (flapping) stays in the same episode. It is ongoing while the newest event is a bad line from the
    last SLACK_QUIET seconds; a newer good line (a fresh session) counts as healthy. State file: a
    platform state other than connected, written by the running gateway (a process of the launchd job)."""
    since = None
    start = last_bad = None
    for t, kind in events:
        if kind == "bad":
            if last_bad is None or t - last_bad > SLACK_QUIET:
                start = t
            last_bad = t
    if events and events[-1][1] == "bad" and now - last_bad <= SLACK_QUIET:
        since = start
    if isinstance(gateway_state, dict) and gateway_state.get("gateway_state") == "running" \
            and gateway_state.get("start_time") is not None and pid_alive(gateway_state.get("pid")) \
            and job_pid is not None and descends(gateway_state.get("pid"), job_pid):
        slack = (gateway_state.get("platforms") or {}).get("slack") or {}
        # Only the running gateway's own record counts (not one left by an earlier process).
        if slack.get("state") in BAD_STATES and slack.get("writer_pid") == gateway_state.get("pid") \
                and slack.get("writer_start_time") == gateway_state.get("start_time"):
            t = now
            for key in ("retrying_since", "updated_at"):
                try:  # python 3.9's fromisoformat doesn't take a trailing Z
                    t = datetime.datetime.fromisoformat(re.sub(r"Z$", "+00:00", slack[key])).timestamp()
                    break
                except (KeyError, TypeError, ValueError):
                    pass
            since = t if since is None else min(since, t)
    return since


def descends(pid, ancestor):
    """True if `pid` is `ancestor` or one of its descendants (the job's pid is Hermes' osascript wrapper)."""
    try:
        out = subprocess.run(["/bin/ps", "-axo", "pid=,ppid="], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        return False
    parent = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) == 2 and f[0].isdigit() and f[1].isdigit():
            parent[int(f[0])] = int(f[1])
    seen = set()
    while isinstance(pid, int) and pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        pid = parent.get(pid)
    return False


def read_tail(path, size=LOG_TAIL):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            end = f.tell()
            f.seek(max(0, end - size))
            data = f.read()
    except OSError:
        return ""
    text = data.decode("utf-8", "replace")
    return text if end <= size else text.split("\n", 1)[-1]


def gateway_job_pid():
    """pid of the ai.hermes.gateway launchd job, or None when it isn't loaded or running."""
    try:
        p = subprocess.run(["/bin/launchctl", "print", f"gui/{os.getuid()}/{GATEWAY_LABEL}"],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    m = re.search(r"^\tpid = (\d+)$", p.stdout, re.M) if p.returncode == 0 else None
    return int(m.group(1)) if m else None


clock = time.time  # tests replace it


def slack_check(now, st, save):
    """One step of the Slack safeguard; `st` is its persisted state (changed in place), `save()` writes it.

    State: since (outage start), last_run, restarted_at (our restart awaiting its verdict), last_restart,
    healthy_since (start of the current healthy stretch), suppressed (no more restarts until Slack recovers), alerted (that alert was delivered), alert_text,
    pending (restart notices not delivered yet)."""
    last_run, st["last_run"] = st.get("last_run"), now
    job_pid = gateway_job_pid()

    # Notices that failed (Slack down, network out) are retried; stop at the first failure this run.
    pending = [m for m in (st.get("pending") if isinstance(st.get("pending"), list) else []) if isinstance(m, str)]
    while pending and send(pending[0]):
        pending.pop(0)
    st["pending"] = pending

    def notify(text):
        if not (st["pending"] == [] and send(text)):
            st["pending"].append(text)

    def suppress(text):
        st["suppressed"], st["alert_text"] = True, text
        st["alerted"] = send(text)

    if job_pid is None:
        # Stopped (on purpose, or during an update): not ours to start. config-check reports a gateway
        # that stays down.
        st["since"] = None
        st.pop("restarted_at", None)
        st.pop("healthy_since", None)
        return
    try:
        with open(os.path.join(HERMES_HOME, "gateway_state.json")) as f:
            gw = json.load(f)
    except (OSError, ValueError):
        gw = None
    since = slack_unhealthy_since(now, slack_events(read_tail(os.path.join(HERMES_HOME, "logs", "agent.log"))),
                                  gw, job_pid)
    # The log restarts at each gateway start; keep the episode's start across runs, unless the last run
    # is too long ago to know the outage went on in between.
    if since is not None and isinstance(st.get("since"), (int, float)) \
            and isinstance(last_run, (int, float)) and now - last_run <= SLACK_QUIET:
        since = min(since, st["since"])
    st["since"] = since

    stamp = lambda t: time.strftime("%H:%M", time.localtime(t))
    if since is None:
        st.pop("restarted_at", None)  # healed; a relapse within RESTART_GAP still only alerts
        if not isinstance(st.get("healthy_since"), (int, float)):
            st["healthy_since"] = now
        # Lift the suppression only after SLACK_QUIET of continuous health, so a flapping connection
        # gets one alert and one "connected again", not one pair per flap.
        if st.get("suppressed") and now - st["healthy_since"] >= SLACK_QUIET:
            if st.get("alerted"):
                notify("Slack: July is connected again.")
            st["suppressed"] = st["alerted"] = False
            st.pop("alert_text", None)
        return
    st.pop("healthy_since", None)
    if st.get("suppressed"):
        if not st.get("alerted") and isinstance(st.get("alert_text"), str):
            st["alerted"] = send(st["alert_text"])  # retried until delivered; never a restart
        return
    restarted = st.get("restarted_at")
    if isinstance(restarted, (int, float)):
        if now - restarted >= SLACK_HEAL:
            suppress(f"Slack: July is still not connected {SLACK_HEAL // 60} min after the automatic gateway "
                     f"restart (unhealthy since {stamp(since)}). Not restarting again until it recovers; "
                     "check ~/.hermes/logs/agent.log on garage-hq.")
        return
    if now - since < SLACK_DOWN:
        return
    if now - st.get("last_restart", 0) < RESTART_GAP:
        suppress(f"Slack: July's connection is unhealthy again (since {stamp(since)}), within an hour of the "
                 "last automatic gateway restart. Not restarting again until it recovers; "
                 "check ~/.hermes/logs/agent.log on garage-hq.")
        return
    # Saved before the restart, so a crash or kill afterwards can't lead to a second one.
    st["restarted_at"] = st["last_restart"] = now
    save()
    try:
        r = subprocess.run([HERMES_BIN, "gateway", "restart"], capture_output=True, text=True, timeout=900)
        ok = r.returncode == 0
        if not ok:
            tail = (r.stderr or r.stdout or "").strip().splitlines()[-1:] or [""]
            print(f"deadman: hermes gateway restart exited {r.returncode}: {tail[0][:200]}")
    except (OSError, subprocess.TimeoutExpired) as e:
        ok = False
        print(f"deadman: hermes gateway restart failed: {e.__class__.__name__}")
    # The drain can take minutes: the verdict window starts when the restart is done.
    done = clock()
    st["last_run"] = done
    if ok:
        st["restarted_at"] = done
    notify(f"Slack: July's connection was unhealthy since {stamp(since)}, so I "
           + ("restarted the gateway (`hermes gateway restart`)." if ok else
              "tried `hermes gateway restart`, which FAILED.")
           + f" I'll DM again if it isn't healthy within {SLACK_HEAL // 60} min.")


def main():
    now = time.time()
    try:
        mine = json.load(open(MINE))
    except (OSError, ValueError):
        mine = None
    if not isinstance(mine, dict) or not isinstance(mine.get("alerted", False), bool) \
            or not isinstance(mine.get("enabled_since"), (int, float, type(None))):
        mine = {"alerted": False, "enabled_since": None}
    if not isinstance(mine.get("slack"), dict):
        mine["slack"] = {}
    slack = mine["slack"]
    try:
        slack_check(now, slack, lambda: save(mine))
        slack["errors"], slack["error_alerted"] = 0, False
    except Exception as e:  # never let the Slack check stop the monitor check
        print(f"deadman: Slack check failed: {e.__class__.__name__}: {e}")
        slack["errors"] = (slack.get("errors") if isinstance(slack.get("errors"), int) else 0) + 1
        if slack["errors"] >= SLACK_ERRORS and not slack.get("error_alerted"):
            slack["error_alerted"] = send(
                f"Slack safeguard on garage-hq has failed {slack['errors']} times in a row ({e.__class__.__name__}); "
                "it can't restart the gateway until that's fixed. See ~/Library/Logs/inbox-monitor-deadman.log.")
    save(mine)

    # Only a confirmed pause (or a job that was never set up) is quiet; an unreadable jobs.json or a job
    # that disappeared after it was enabled counts as a problem.
    problem = None
    try:
        doc = json.load(open(os.path.join(HERMES_HOME, "cron", "jobs.json")))
        jobs = doc.get("jobs") if isinstance(doc, dict) else doc
        if not isinstance(jobs, list):
            raise ValueError("jobs.json has an unexpected shape")
        job = next((j for j in jobs if isinstance(j, dict) and j.get("name") == "inbox-monitor"), None)
        if job is None:
            enabled = None
        else:
            enabled = bool(job.get("enabled", True)) and job.get("state") != "paused"
    except FileNotFoundError:
        enabled = None  # Hermes has no cron jobs yet; "gone" below if it was enabled before
    except (OSError, ValueError):
        enabled, problem = None, "Hermes' cron/jobs.json can't be read"
    if enabled is None and (problem or mine.get("enabled_since")):
        problem = problem or "its Hermes cron job is gone"
        enabled = True
    if not enabled:
        mine["enabled_since"] = None
    else:
        mine["enabled_since"] = mine.get("enabled_since") or now

        last = 0
        try:
            st = json.load(open(os.path.join(STATE_DIR, "state.json")))
            last = st.get("last_ok_at") if isinstance(st, dict) else None
            if last is None:
                last = 0
            elif not isinstance(last, (int, float)):
                raise ValueError("bad last_ok_at")
            if not isinstance(st, dict):
                raise ValueError("state.json has an unexpected shape")
        except (OSError, ValueError):
            last, problem = 0, problem or "its state.json can't be read"
        baseline = max(last, mine["enabled_since"])
        late = problem is not None or now - baseline > LATE

        if late and not mine.get("alerted"):
            why = problem or ("no successful cycle since "
                              + (time.strftime("%d %b %H:%M", time.localtime(last)) if last else "it was enabled"))
            if send(f"Inbox monitor: {why}. Check `hermes cron status` on garage-hq."):
                mine["alerted"] = True
        elif not late and mine.get("alerted"):
            if send("Inbox monitor recovered."):
                mine["alerted"] = False

    save(mine)


def save(mine):
    tmp = MINE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(mine, f)
    os.replace(tmp, MINE)


if __name__ == "__main__":
    main()
