#!/usr/bin/python3 -I
"""A fake `hc` for test_july_task.py: terminals live in the JSON file $FAKE_HC_STATE.

Supports what july_task.py uses: run, get, ls, kill, rm, send, wait, read, keys. Exit 3 + not_found like
the real hc. FAKE_HC_DOWN=1 makes every command fail as if the core were unavailable. On `run` with
--session-id it writes a transcript under $FAKE_HC_TRANSCRIPTS (unless FAKE_HC_NO_TRANSCRIPT=1); on `wait`
it copies $FAKE_HC_SNAPSHOT_FROM to $FAKE_HC_SNAPSHOT_TO (to see the task state during a start).
"""
import json, os, shutil, sys, time

PATH = os.environ["FAKE_HC_STATE"]


def rj(path):
    with open(path) as f:
        return json.load(f)


def wj(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=1)


def load():
    return rj(PATH) if os.path.exists(PATH) else {"next": 1, "terminals": []}


def save(s):
    wj(PATH, s)


def out(v, code=0):
    print(json.dumps(v))
    sys.exit(code)


def find(s, ref):
    hits = [t for t in s["terminals"] if t["address"] == ref] or \
        [t for t in s["terminals"] if t.get("name") == ref and t["state"] == "live"]
    if not hits:
        out({"error": {"kind": "not_found", "message": f"no terminal {ref!r}"}}, 3)
    return hits[0]


def main():
    args = [a for a in sys.argv[1:] if a != "--json"]
    cmd, rest = args[0], args[1:]
    if os.environ.get("FAKE_HC_DOWN") == "1":
        out({"error": {"kind": "unavailable", "message": "core restarting"}}, 1)
    s = load()
    if cmd == "run":
        opts, i = {"labels": {}}, 0
        while i < len(rest) and rest[i] != "--":
            a = rest[i]
            if a in ("--name", "--cwd", "--parent", "--timeout", "--on"):
                opts[a[2:]] = rest[i + 1]
                i += 2
            elif a == "--label":
                k, v = rest[i + 1].split("=", 1)
                opts["labels"][k] = v
                i += 2
            else:
                i += 1
        argv = rest[i + 1:]
        t = {"address": f"t{s['next']}", "name": opts.get("name"), "state": "live", "parent": None,
             "labels": opts["labels"], "argv": argv, "cwd": opts.get("cwd"), "status": {"state": "idle"},
             "status_ms": int(time.time() * 1000), "created_ms": int(time.time() * 1000), "exit_code": None,
             "screen": "", "inbox": [], "keys": []}
        s["next"] += 1
        s["terminals"].append(t)
        save(s)
        if "--session-id" in argv and os.environ.get("FAKE_HC_TRANSCRIPTS") and \
                os.environ.get("FAKE_HC_NO_TRANSCRIPT") != "1":
            sid = argv[argv.index("--session-id") + 1]
            d = os.path.join(os.environ["FAKE_HC_TRANSCRIPTS"], "proj")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, sid + ".jsonl"), "w") as f:
                f.write(json.dumps({"type": "user", "message": {"content": argv[-1]},
                                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())}) + "\n")
        out({"address": t["address"], "name": t["name"], "state": "live"})
    if cmd == "get":
        out(find(s, rest[0]))
    if cmd == "ls":
        want = [r.split("=", 1) for j, r in enumerate(rest) if j and rest[j - 1] == "--label"]
        ts = [t for t in s["terminals"] if ("--all" in rest or t["state"] == "live")
              and all(t["labels"].get(k) == v for k, v in want)]
        out({"terminals": [{"address": t["address"]} for t in ts]})
    t = find(s, rest[0])
    if cmd == "kill":
        t.update(state="finished", exit_code=129)
    elif cmd == "rm":
        if t["state"] == "live":
            out({"error": {"kind": "live", "message": "still running"}}, 11)
        s["terminals"].remove(t)
    elif cmd == "send":
        t["inbox"].append(rest[-1])
    elif cmd == "keys":
        t["keys"].append(rest[1:])
    elif cmd == "read":
        save(s)
        print(t["screen"])
        sys.exit(0)
    elif cmd == "wait":
        if os.environ.get("FAKE_HC_SNAPSHOT_FROM"):
            shutil.copy(os.environ["FAKE_HC_SNAPSHOT_FROM"], os.environ["FAKE_HC_SNAPSHOT_TO"])
        out({"reason": "timeout", "status": t["status"]["state"]})
    save(s)
    out({"ok": True, "address": t["address"]})


main()
