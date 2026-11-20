"""hermes-inbox-jobs: create the inbox-monitor cron job (paused) and the daily prune job, idempotently.

Run once after the first switch (docs/ai-setup.md). `hermes cron create` has no toolset flag, so the job's
enabled_toolsets are set through Hermes' own cron API (which takes the jobs.json lock) and checked.
"""
import argparse, json, os, re, shutil, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("--hermes", required=True)
ap.add_argument("--hermes-home", required=True)
ap.add_argument("--state-dir", required=True)
ap.add_argument("--prune-script", required=True)
ap.add_argument("--model", required=True)
ap.add_argument("--no-monitor", action="store_true")
a = ap.parse_args()

env = dict(os.environ, HERMES_HOME=a.hermes_home)
wrapper = open(a.hermes).read()
m = re.search(r'^exec "(.+)/hermes" ', wrapper, re.M)
if not m:
    sys.exit("hermes-inbox-jobs: can't find Hermes' Python next to " + a.hermes)
hermes_py = os.path.join(m.group(1), "python3")


def api(code):
    out = subprocess.run([hermes_py, "-c", "import json\nfrom cron.jobs import list_jobs, update_job\n" + code],
                         env=env, capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def jobs():
    return {j["name"]: j for j in api("print(json.dumps(list_jobs(include_disabled=True)))")}


def hermes(*args):
    subprocess.run([a.hermes, *args], env=env, check=True)


# The prune script must sit in $HERMES_HOME/scripts and be named relatively.
scripts = os.path.join(a.hermes_home, "scripts")
os.makedirs(scripts, exist_ok=True)
dest = os.path.join(scripts, "hermes-prune.sh")
tmp = dest + ".tmp"
shutil.copyfile(a.prune_script, tmp)
os.chmod(tmp, 0o500)
os.replace(tmp, dest)

have = jobs()
if "hermes-prune" not in have:
    hermes("cron", "create", "0 4 * * *", "--name", "hermes-prune", "--no-agent",
           "--script", "hermes-prune.sh", "--deliver", "local", "--failure-deliver", "local")

if not a.no_monitor:
    owner = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", "hermes-agent",
                            "-a", "slack-owner-id", "-w"], capture_output=True, text=True).stdout.strip()
    deliver = f"slack:{owner}" if re.fullmatch(r"U[A-Z0-9]{6,}", owner) else "local"
    if "inbox-monitor" not in have:
        hermes("cron", "create", "every 5m", "Run one inbox-monitor cycle.", "--name", "inbox-monitor",
               "--skill", "inbox-monitor", "--workdir", a.state_dir,
               "--provider", "cliproxy", "--model", a.model,
               "--deliver", deliver, "--failure-deliver", "local", "--no-wrap-response", "--catch-up", "off",
               "--paused", "--paused-reason", "enable with: hermes cron resume inbox-monitor")
    job = jobs()["inbox-monitor"]
    if job.get("enabled_toolsets") != ["mcp-inbox"]:
        api(f"print(json.dumps(update_job({job['id']!r}, {{'enabled_toolsets': ['mcp-inbox']}})))")
    job = jobs()["inbox-monitor"]
    want = {"enabled_toolsets": ["mcp-inbox"], "skills": ["inbox-monitor"], "model": a.model,
            "provider": "cliproxy", "failure_deliver": "local"}
    bad = {k: job.get(k) for k, v in want.items() if job.get(k) != v}
    if bad:
        sys.exit(f"hermes-inbox-jobs: inbox-monitor job is not as expected: {bad}")
    print(f"inbox-monitor: {job['state']}, delivers to {job.get('deliver')}, toolsets {job['enabled_toolsets']}")

hermes("cron", "list", "--all")
