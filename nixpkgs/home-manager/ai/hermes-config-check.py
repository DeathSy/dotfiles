"""hermes-config-check: verify (and with --fix restore) the parts of the mutable Hermes install we rely on.

Hermes owns ~/.hermes (installed by its own installer, updated with `hermes update`, edited by the
dashboard and the apps). This checks only our invariants, from a spec that ai/hermes.nix generates:

  config.yaml  rules (equals / contains / excludes / absent) on the safety settings; --fix applies them.
               defaults are seeded only when missing (Hermes and the user own them afterwards).
  .env         our non-secret keys (loopback API server, cron timeout, home channel); --fix rewrites them.
  secrets      key NAMES that look secret in .env or config.yaml (values never read out or printed).
  runtime      one gateway, run by launchd job ai.hermes.gateway; no unmanaged runtime job
               (com.nousresearch.hermes.runtime.*); dashboard and API server listening on loopback only.

Modes: no flag changes nothing. --fix (activation, at every rebuild) applies every rule, the defaults,
.env and the file fixes, and restarts the gateway the same way when a changed setting needs it. --auto (the launchd agent: every 30 min and when config.yaml/.env change) applies
only the rules marked auto (the security subset) and .env, DMs the owner what it restored, and restarts
the gateway gracefully when a restored setting is read only at gateway start (slack.*, platforms.*,
mcp_servers.*, secrets.*, .env). --alert DMs the owner about problems unchanged for 20 minutes (over at least two runs), and once
when they clear. Output names settings, never values.

The resolved-toolset assertion uses Hermes' own resolver (hermes_cli.tools_config) from the installed
checkout: no chat platform may resolve to the monitor's inbox MCP server.
"""
import argparse, copy, fcntl, hashlib, importlib.util, json, os, re, stat, subprocess, sys, tempfile, time

import yaml

ap = argparse.ArgumentParser()
ap.add_argument("--spec", required=True)
ap.add_argument("--fix", action="store_true", help="apply the config/.env rules (runtime problems are only reported)")
ap.add_argument("--auto", action="store_true", help="apply the security rules and .env (launchd agent)")
ap.add_argument("--alert", action="store_true", help="DM the owner about persistent problems (launchd agent)")
ap.add_argument("--quiet", action="store_true", help="print only problems and changes")
a = ap.parse_args()
spec = json.load(open(a.spec))
home = spec["hermes_home"]
# One run at a time (activation's --fix and launchd's --auto can start together): they read, change and write
# the same files.
os.makedirs(os.path.dirname(spec["state_file"]), exist_ok=True)
_lock = open(os.path.join(os.path.dirname(spec["state_file"]), ".config-check.lock"), "a")
fcntl.flock(_lock, fcntl.LOCK_EX)
cfg_path, env_path = os.path.join(home, "config.yaml"), os.path.join(home, ".env")
problems, changes = [], []
restart = set()  # "gateway" / "dashboard": a restored setting is read at process start
PERSIST = 1200
START_READ = {"slack", "platforms", "mcp_servers", "secrets", "unauthorized_dm_behavior"}


def fixing(rule=None):
    return a.fix or (a.auto and (rule is None or rule.get("auto", False)))
SECRETISH = re.compile(r"(api_?key|token|secret|password|passwd|private_?key)$", re.I)  # config.yaml keys
ENV_SECRETISH = re.compile(r"(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIALS?)$", re.I)  # API_SERVER_KEY, *_TOKEN …


def say(msg):
    if not a.quiet:
        print(msg)


def get(doc, path):
    for key in path:
        if not isinstance(doc, dict) or key not in doc:
            return False, None
        doc = doc[key]
    return True, doc


def put(doc, path, value):
    for key in path[:-1]:
        if not isinstance(doc.get(key), dict):
            doc[key] = {}
        doc = doc[key]
    doc[path[-1]] = copy.deepcopy(value)


def drop(doc, path):
    found, parent = get(doc, path[:-1])
    if found and isinstance(parent, dict):
        parent.pop(path[-1], None)


def private_tmp(path, data):
    """A unique 0600 temp file next to path holding data (str or bytes); returns its name."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix="." + os.path.basename(path) + ".")
    with os.fdopen(fd, "wb") as f:
        f.write(data.encode() if isinstance(data, str) else data)
    os.chmod(tmp, 0o600)
    return tmp


def write_private(path, text):
    os.replace(private_tmp(path, text), path)


def run(argv, timeout=20):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


# ── config.yaml ─────────────────────────────────────────────────────────────
if not os.path.isfile(cfg_path):
    problems.append("~/.hermes/config.yaml is missing (Hermes not installed?)")
    cfg = None
else:
    try:
        cfg = yaml.safe_load(open(cfg_path)) or {}
        if not isinstance(cfg, dict):
            raise ValueError("not a mapping")
    except (OSError, ValueError, yaml.YAMLError) as e:
        problems.append(f"config.yaml can't be read ({e.__class__.__name__})")
        cfg = None

if cfg is not None:
    before = copy.deepcopy(cfg)
    for rule in spec["rules"]:
        path, op, want = rule["path"], rule["op"], rule.get("value")
        name = ".".join(path)
        found, have = get(cfg, path)
        if op == "equals":
            ok = found and have == want
        elif op == "contains":
            # drop_prefix: entries we used to write (store paths) that should go once stale.
            stale = [x for x in have if isinstance(x, str) and rule.get("drop_prefix") and x.startswith(rule["drop_prefix"])
                     and x not in want] if found and isinstance(have, list) else []
            ok = found and isinstance(have, list) and all(x in have for x in want) and not stale
        elif op == "excludes":
            ok = not found or (isinstance(have, list) and not any(x in have for x in want))
        elif op == "absent":
            ok = not found
        else:
            raise SystemExit(f"unknown rule op {op}")
        if ok:
            continue
        if not fixing(rule):
            problems.append(f"config.yaml {name} differs from the dotfiles rule ({op})")
            continue
        elif op == "equals":
            put(cfg, path, want)
        elif op == "contains":
            keep = [x for x in have if x not in stale] if found and isinstance(have, list) else []
            put(cfg, path, keep + [x for x in want if x not in keep])
        elif op == "excludes":
            put(cfg, path, [x for x in have if x not in want])
        elif op == "absent":
            drop(cfg, path)
        changes.append(f"config.yaml {name} restored ({op})")
        if path[0] in START_READ:
            restart.add("gateway")
        elif path[0] == "dashboard":
            restart.add("dashboard")
    for item in spec["defaults"]:
        if not get(cfg, item["path"])[0]:
            if a.fix:
                put(cfg, item["path"], item["value"])
                changes.append(f"config.yaml {'.'.join(item['path'])} seeded")
            else:
                say(f"note: config.yaml {'.'.join(item['path'])} is unset (--fix seeds the default)")
    if cfg != before:
        try:
            with open(cfg_path) as f:
                write_private(cfg_path + ".bak", f.read())
            write_private(cfg_path, yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True))
        except OSError as e:
            problems.append(f"could not write config.yaml ({e.__class__.__name__})")

    allowed = set(spec.get("allowed_secret_paths", []))

    def scan(node, path):
        if isinstance(node, dict):
            for k, v in node.items():
                p = path + [str(k)]
                if isinstance(v, (dict, list)):
                    scan(v, p)
                elif SECRETISH.search(str(k)) and isinstance(v, str) and v.strip() and ".".join(p) not in allowed:
                    problems.append(f"config.yaml {'.'.join(p)} holds a literal secret; move it to pass + the Keychain")
        elif isinstance(node, list):
            for i, v in enumerate(node):
                scan(v, path + [str(i)])
    scan(cfg, [])

# ── .env ────────────────────────────────────────────────────────────────────
try:
    lines = open(env_path).read().splitlines()
except FileNotFoundError:
    lines = []
except OSError as e:
    lines = None
    problems.append(f".env can't be read ({e.__class__.__name__})")
if lines is not None:
    have = {}
    for line in lines:
        m = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if m:
            have[m.group(1)] = m.group(2).strip().strip("'\"")
    wrong = [k for k, v in spec["env"].items() if have.get(k) != v]
    for k in spec.get("env_absent", []):
        if k in have:
            wrong.append(k)
    if wrong and fixing():
        keep = [l for l in lines if not re.match(r"\s*(?:export\s+)?(" + "|".join(map(re.escape, list(spec["env"]) + spec.get("env_absent", []))) + r")=", l)]
        keep += [f"{k}={v}" for k, v in spec["env"].items()]
        try:
            write_private(env_path, "\n".join(keep) + "\n")
            changes.append(".env " + ", ".join(sorted(set(wrong))) + " restored")
            restart.add("gateway")
        except OSError as e:
            problems.append(f"could not write .env ({e.__class__.__name__})")
    elif wrong:
        problems.append(".env " + ", ".join(sorted(set(wrong))) + " differ from the dotfiles values")
    leaked = sorted(k for k, v in have.items() if v and ENV_SECRETISH.search(k) and k not in spec["env"])
    if leaked:
        problems.append(".env holds secret-looking keys " + ", ".join(leaked) + "; move them to pass + the Keychain (secrets helper)")

for path in (cfg_path, env_path):
    try:
        if stat.S_IMODE(os.stat(path).st_mode) & 0o077:
            if fixing():
                os.chmod(path, 0o600)
                changes.append(f"{os.path.basename(path)} made 0600")
            else:
                problems.append(f"{os.path.basename(path)} is readable by others (want 0600)")
    except FileNotFoundError:
        pass

# ── files ───────────────────────────────────────────────────────────────────
managed = os.path.join(home, ".managed")
if os.path.exists(managed):
    # The Nix install's marker makes Hermes refuse config edits; this install is not managed.
    if a.fix and open(managed).read().strip() == "home-manager":
        os.remove(managed)
        changes.append(".managed (Home Manager marker) removed")
    else:
        problems.append("~/.hermes/.managed exists: Hermes treats the install as read-only")
soul = spec.get("soul")
if soul:
    # The persona follows the overlay without clobbering local edits: --fix installs the overlay's SOUL.md
    # when the live file is missing, or is still exactly the copy it installed last (the sha256 of its bytes
    # is kept in .soul-installed next to the state file). A live file that matches neither has been edited
    # here: it is left alone, with a note to merge by hand. The live file is hashed again right before the
    # rename, so an edit saved during this run is not overwritten (only a save in the instant between that
    # check and the rename could still be), and a missing file is seeded with link(), which never replaces.
    live_soul, mark = os.path.join(home, "SOUL.md"), os.path.join(os.path.dirname(spec["state_file"]), ".soul-installed")
    sha = lambda data: hashlib.sha256(data).hexdigest()
    with open(soul, "rb") as f:
        want_soul = f.read()
    try:
        with open(mark) as f:
            installed = f.read().strip()
    except OSError:
        installed = ""

    def live_bytes():
        try:
            with open(live_soul, "rb") as f:
                return f.read()
        except FileNotFoundError:
            return None

    live_data = live_bytes()
    if live_data is None:
        if a.fix:
            tmp = private_tmp(live_soul, want_soul)
            try:
                os.link(tmp, live_soul)  # fails if a SOUL.md appeared meanwhile
                write_private(mark, sha(want_soul))
                changes.append("SOUL.md seeded")
            except FileExistsError:
                say("note: ~/.hermes/SOUL.md appeared during this run; left alone")
            finally:
                os.unlink(tmp)
        else:
            problems.append("~/.hermes/SOUL.md is missing (--fix seeds the persona)")
    elif live_data == want_soul:
        if a.fix and installed != sha(want_soul):
            write_private(mark, sha(want_soul))
    elif installed and sha(live_data) == installed:
        if a.fix:
            tmp = private_tmp(live_soul, want_soul)
            if live_bytes() == live_data:
                os.replace(tmp, live_soul)
                write_private(mark, sha(want_soul))
                changes.append("SOUL.md updated from the overlay")
            else:
                os.unlink(tmp)
                say("note: ~/.hermes/SOUL.md changed during this run; left alone")
        else:
            say("note: ~/.hermes/SOUL.md is an older overlay version (--fix updates it)")
    else:
        say(f"note: ~/.hermes/SOUL.md has local edits, so the overlay's version was not installed; "
            f"compare (diff ~/.hermes/SOUL.md {soul}) and merge by hand")

# ── resolved toolsets (Hermes' own resolver) ───────────────────────────────
RESOLVE = r"""
import json, os
from hermes_cli.config import load_config
from hermes_cli.tools_config import _get_platform_tools, _get_enabled_platforms
cfg = load_config()
plats = set(json.loads(os.environ["PLATFORMS"])) | set(cfg.get("platform_toolsets") or {}) | set(_get_enabled_platforms())
print(json.dumps({p: sorted(_get_platform_tools(cfg, p)) for p in sorted(plats)}))
"""


def hermes_run(code, extra_env=None, timeout=90):
    """Run Python code inside Hermes' own runtime (its launcher's --run-module, which builds the
    interpreter, sys.path and dependency environment): `hermes --run-module cProfile -o /dev/null
    /dev/stdin` executes stdin like a script. Returns the last stdout line, or None."""
    try:
        p = subprocess.run([spec["hermes_bin"], "--run-module", "cProfile", "-o", "/dev/null", "/dev/stdin"],
                           input=code, capture_output=True, text=True, timeout=timeout,
                           env=dict(os.environ, HERMES_HOME=home, **(extra_env or {})))
        lines = p.stdout.strip().splitlines()
        return lines[-1] if p.returncode == 0 and lines else None
    except (OSError, subprocess.TimeoutExpired):
        return None


if cfg is not None:
    try:
        resolved = json.loads(hermes_run(RESOLVE, {"PLATFORMS": json.dumps(spec["chat_platforms"])}) or "null")
    except ValueError:
        resolved = None
    if not isinstance(resolved, dict):
        problems.append("could not resolve the platform toolsets with Hermes' resolver (is Hermes installed?)")
    else:
        leaking = sorted(p for p, tools in resolved.items() if p != "cron" and spec["cron_only_server"] in tools)
        if leaking:
            problems.append(f"the {spec['cron_only_server']} MCP server resolves for chat platform(s) {', '.join(leaking)}")
        if spec["cron_only_server"] not in resolved.get("cron", []):
            problems.append(f"cron no longer resolves the {spec['cron_only_server']} MCP server (the monitor needs it)")

# ── runtime ─────────────────────────────────────────────────────────────────
uid = os.getuid()
label = spec["gateway_label"]
job_pid = None
out = run(["/bin/launchctl", "print", f"gui/{uid}/{label}"])
if out is None or out.returncode != 0:
    problems.append(f"launchd job {label} is not loaded (hermes gateway install)")
else:
    m = re.search(r"^\tpid = (\d+)$", out.stdout, re.M)
    job_pid = int(m.group(1)) if m else None
    if job_pid is None:
        problems.append(f"launchd job {label} is loaded but not running")

ps = run(["/bin/ps", "-axo", "pid=,ppid=,command="])
procs = {}
gateways = []
if ps is not None and ps.returncode == 0:
    for line in ps.stdout.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 3 or not parts[0].isdigit():
            continue
        pid, ppid, cmd = int(parts[0]), int(parts[1]), parts[2]
        procs[pid] = ppid
        if cmd.startswith(("/usr/bin/osascript", "/bin/sh ", "/bin/zsh ")):
            continue  # launch wrappers carry the command line as text
        tokens = cmd.split()
        if "hermes" in cmd and any(t == "gateway" and tokens[i + 1:i + 2] in (["run"], []) for i, t in enumerate(tokens)):
            gateways.append(pid)
    # A wrapper (Hermes' stderr-timestamp launcher) and its gateway child both carry `gateway run`:
    # count chains, i.e. matches without a matching ancestor.
    matched = set(gateways)

    def has_matched_ancestor(pid):
        seen = set()
        pid = procs.get(pid)
        while pid and pid not in seen and pid != 1:
            if pid in matched:
                return True
            seen.add(pid)
            pid = procs.get(pid)
        return False
    gateways = [p for p in gateways if not has_matched_ancestor(p)]
    if len(gateways) > 1:
        problems.append(f"{len(gateways)} Hermes gateway processes are running (want 1): pids {', '.join(map(str, gateways))}")
    elif not gateways:
        problems.append("no Hermes gateway process is running")


def descends(pid, ancestor):
    seen = set()
    while pid and pid not in seen and pid != 1:
        if pid == ancestor:
            return True
        seen.add(pid)
        pid = procs.get(pid)
    return False


if job_pid:
    stray = [p for p in gateways if not descends(p, job_pid)]
    if stray:
        problems.append(f"gateway pid {', '.join(map(str, stray))} is not under launchd job {label} (unmanaged)")

lst = run(["/bin/launchctl", "list"])
if lst is not None and lst.returncode == 0:
    runtime = sorted({l.split("\t")[-1] for l in lst.stdout.splitlines() if "com.nousresearch.hermes.runtime." in l})
    if runtime:
        problems.append("unmanaged gateway job(s) loaded: " + ", ".join(runtime))

for name, port, need in (("dashboard", spec.get("dashboard_port"), True), ("API server", spec.get("api_port"), True)):
    if not port:
        continue
    out = run(["/usr/sbin/lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-Fn"])
    addrs = [l[1:] for l in (out.stdout.splitlines() if out and out.returncode == 0 else []) if l.startswith("n")]
    if not addrs and need:
        problems.append(f"{name} is not listening on 127.0.0.1:{port}")
    bad = [x for x in addrs if not (x.startswith("127.0.0.1:") or x.startswith("[::1]:"))]
    if bad:
        problems.append(f"{name} listens beyond loopback on port {port} ({', '.join(sorted(set(bad)))})")

# ── report ──────────────────────────────────────────────────────────────────
if restart and (a.auto or a.fix):
    # Graceful: `hermes gateway restart` drains running turns, then launchd starts the job again. Also at
    # activation (--fix), or a rebuild that changes a start-read setting leaves the old one running.
    if "gateway" in restart and not job_pid:
        changes.append("gateway not restarted: its launchd job isn't running")
    elif "gateway" in restart:
        r = run([spec["hermes_bin"], "gateway", "restart"], timeout=900)
        changes.append("gateway restarted" if r is not None and r.returncode == 0 else "gateway restart FAILED (run: hermes gateway restart)")
    if "dashboard" in restart:
        r = run(["/bin/launchctl", "kickstart", "-k", f"gui/{os.getuid()}/{spec['dashboard_label']}"])
        changes.append("dashboard restarted" if r is not None and r.returncode == 0 else "dashboard restart FAILED")
elif restart:
    print("note: restart to load the restored settings: " + " and ".join(
        {"gateway": "hermes gateway restart (between monitor cycles)",
         "dashboard": f"launchctl kickstart -k gui/$UID/{spec['dashboard_label']}"}[x] for x in sorted(restart)))
if changes and a.auto:
    s_ = importlib.util.spec_from_file_location("deadman", spec["deadman"])
    dm = importlib.util.module_from_spec(s_)
    s_.loader.exec_module(dm)
    dm.send("Hermes config check on garage-hq restored our settings after a change:\n- " + "\n- ".join(changes))
for c in changes:
    print("fixed: " + c)
for p in problems:
    print("problem: " + p)
if not problems:
    say("hermes-config-check: OK")

if a.alert:
    mine_path = spec["state_file"]
    try:
        mine = json.load(open(mine_path))
        if not isinstance(mine, dict):
            raise ValueError
    except (OSError, ValueError):
        mine = {}
    key = sorted(problems)
    # Alert only on problems unchanged for PERSIST seconds (WatchPaths runs can come seconds apart,
    # e.g. while an install or update rewrites config.yaml).
    if key != mine.get("last"):
        mine["since"] = int(time.time())
    if key and key == mine.get("last") and key != mine.get("alerted") and time.time() - mine.get("since", 0) >= PERSIST:
        s = importlib.util.spec_from_file_location("deadman", spec["deadman"])
        dm = importlib.util.module_from_spec(s)
        s.loader.exec_module(dm)
        if dm.send("Hermes config check on garage-hq:\n- " + "\n- ".join(key)
                   + "\nRun `hermes-config-check` there (`--fix` restores the config rules)."):
            mine["alerted"] = key
    elif not key and mine.get("alerted"):
        s = importlib.util.spec_from_file_location("deadman", spec["deadman"])
        dm = importlib.util.module_from_spec(s)
        s.loader.exec_module(dm)
        if dm.send("Hermes config check: all clear again."):
            mine["alerted"] = None
    mine["last"], mine["at"] = key, int(time.time())
    write_private(mine_path, json.dumps(mine))

sys.exit(1 if problems else 0)
