"""hermes-inbox-jobs: create the inbox-monitor cron job (paused) and the daily prune job, idempotently.

Run once after the first switch (docs/ai-setup.md). `hermes cron create` has no toolset flag, so the job's
enabled_toolsets are set through Hermes' own cron API (which takes the jobs.json lock) and checked.
"""
import argparse, json, os, re, shutil, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("--hermes", required=True)
ap.add_argument("--hermes-home", required=True)
ap.add_argument("--hermes-root", required=True, help="Hermes' checkout (cron.jobs lives there)")
ap.add_argument("--state-dir", required=True)
ap.add_argument("--prune-script", required=True)
ap.add_argument("--model", required=True)
a = ap.parse_args()

env = dict(os.environ, HERMES_HOME=a.hermes_home)
def hermes_python(launcher):
    """The interpreter behind Hermes' command: follow `exec <program> …` lines through the shell launchers
    (~/.local/bin/hermes -> <checkout>/.hermes/bin/hermes -> `exec <python> -I -c <bootstrap> "$@"`)."""
    import shlex
    path = launcher
    for _ in range(4):
        path = os.path.realpath(path)
        if re.fullmatch(r"python[0-9.]*", os.path.basename(path)):
            return path
        try:
            with open(path, "rb") as f:
                head = f.read(65536)
            if not head.startswith(b"#!"):
                return None
            line = next(l for l in head.decode("utf-8", "replace").splitlines() if l.startswith("exec "))
            path = shlex.split(line)[1]
        except (OSError, StopIteration, ValueError, IndexError):
            return None
    return None


hermes_py = hermes_python(a.hermes)
if not hermes_py:
    sys.exit("hermes-inbox-jobs: can't find Hermes' Python behind " + a.hermes)


def api(code):
    p = subprocess.run([hermes_py, "-I", "-c", f"import json, sys\nsys.path.insert(0, {a.hermes_root!r})\n"
                        "from cron.jobs import list_jobs, update_job\n" + code],
                       env=env, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit("hermes-inbox-jobs: Hermes cron API failed:\n" + p.stderr.strip()[-2000:])
    return json.loads(p.stdout)


def jobs():
    return {j["name"]: j for j in api("print(json.dumps(list_jobs(include_disabled=True)))")}


def hermes(*args):
    subprocess.run([a.hermes, *args], env=env, check=True)


# No-agent scripts must sit in $HERMES_HOME/scripts and be named relatively.
scripts = os.path.join(a.hermes_home, "scripts")
os.makedirs(scripts, exist_ok=True)
for src, name in ((a.prune_script, "hermes-prune.sh"),):
    dest = os.path.join(scripts, name)
    shutil.copyfile(src, dest + ".tmp")
    os.chmod(dest + ".tmp", 0o500)
    os.replace(dest + ".tmp", dest)

have = jobs()
if "hermes-prune" not in have:
    hermes("cron", "create", "0 4 * * *", "--name", "hermes-prune", "--no-agent",
           "--script", "hermes-prune.sh", "--deliver", "local", "--failure-deliver", "local")

# The retired Slack digest: Reminders are the only output now.
if "inbox-digest" in have:
    hermes("cron", "remove", have["inbox-digest"]["id"])
old = os.path.join(scripts, "hermes-inbox-digest.sh")
if os.path.exists(old):
    os.remove(old)

deliver = "local"
if "inbox-monitor" not in have:
    hermes("cron", "create", "every 5m", "Run one inbox-monitor cycle.", "--name", "inbox-monitor",
           "--skill", "inbox-monitor", "--workdir", a.state_dir,
           "--provider", "cliproxy", "--model", a.model,
           "--deliver", deliver, "--failure-deliver", "local", "--no-wrap-response", "--catch-up", "off",
           "--paused", "--paused-reason", "enable with: hermes cron resume inbox-monitor")
job = jobs()["inbox-monitor"]
fix = {k: v for k, v in {"enabled_toolsets": ["mcp-inbox"], "deliver": deliver}.items() if job.get(k) != v}
if fix:
    api(f"print(json.dumps(update_job({job['id']!r}, {fix!r})))")
job = jobs()["inbox-monitor"]
want = {"enabled_toolsets": ["mcp-inbox"], "skills": ["inbox-monitor"], "model": a.model,
        "provider": "cliproxy", "failure_deliver": "local", "deliver": deliver}
bad = {k: job.get(k) for k, v in want.items() if job.get(k) != v}
if bad:
    sys.exit(f"hermes-inbox-jobs: inbox-monitor job is not as expected: {bad}")
print(f"inbox-monitor: {job['state']}, delivers to {job.get('deliver')}, toolsets {job['enabled_toolsets']}")

hermes("cron", "list", "--all")
