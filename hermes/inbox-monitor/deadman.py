#!/usr/bin/python3 -I
"""Dead-man check for the inbox monitor, run by launchd every 30 min outside Hermes.

While the inbox-monitor cron job is enabled, DM the owner once when there has been no successful cycle
for an hour (or state.json can't be read), and once when it recovers. The hour counts from the later of
the last success and the moment the job was first seen enabled, so resuming a long-paused job doesn't
alert at once. The bot token and owner id come from the login Keychain; the token only travels in an
HTTP header, never on a command line.
"""
import json, os, subprocess, time, urllib.request

STATE_DIR = os.environ.get("INBOX_STATE_DIR") or os.path.expanduser("~/.local/state/inbox-monitor")
HERMES_HOME = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
MINE = os.path.join(STATE_DIR, ".deadman.json")
LATE = 3600


def keychain(account):
    p = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", "hermes-agent", "-a", account, "-w"],
                       capture_output=True, text=True, timeout=10)
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
    except (OSError, ValueError) as e:
        print(f"deadman: Slack request failed: {e.__class__.__name__}")
        return False
    if not body.get("ok"):
        print(f"deadman: Slack refused the DM: {body.get('error')}")
        return False
    return True


def main():
    now = time.time()
    try:
        mine = json.load(open(MINE))
    except (OSError, ValueError):
        mine = None
    if not isinstance(mine, dict) or not isinstance(mine.get("alerted", False), bool) \
            or not isinstance(mine.get("enabled_since"), (int, float, type(None))):
        mine = {"alerted": False, "enabled_since": None}

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

    tmp = MINE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(mine, f)
    os.replace(tmp, MINE)


if __name__ == "__main__":
    main()
