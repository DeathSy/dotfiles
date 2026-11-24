#!/usr/bin/python3 -I
"""hc-worker: start an hc worker in the current Herdr app tab and tidy its layout."""
import copy, json, math, os, re, secrets, shutil, subprocess, sys, time

PROG, APP_DOC = "hc-worker", "herdr-app"
DOC_RETRIES, DOC_CALL_TIMEOUT, MAX_ANCESTOR_DEPTH = 5, 10, 4
POLL_INTERVAL, POLL_TIMEOUT, TIDY_BUDGET, WEIGHT_TOL = 0.25, 4.0, 20.0, 1e-3
ID_RE = re.compile(r"^[A-Za-z0-9_.-]{1,80}$")
RPC_KINDS = {"conflict", "invalid_params", "machine_unknown", "unavailable",
             "needs_update", "internal", "not_found"}
RESERVED_LABELS, REQUIRED_FLAGS = {"herdr.space", "herdr.tab"}, ("--bg", "--json", "--no-notify")
VALUE_OPTS, REFUSED_OPTS = {"--name", "--cwd", "--timeout"}, {"--parent", "--no-parent", "--on"}
USAGE = f"usage: {PROG} [hc run options...] -- <program> [args...]\n       {PROG} --tidy\n       {PROG} --help\n"

class Fail(Exception): pass
class DocConflict(Fail): pass

def hc_path():
    return shutil.which("hc") or os.path.join(os.path.expanduser("~"), ".local", "bin", "hc")

def hc_connect(stdin_text, hc=None):
    env = {k: v for k, v in os.environ.items() if not k.startswith("HC_")}
    try:
        p = subprocess.run([hc or hc_path(), "connect"], input=stdin_text, capture_output=True,
                           encoding="utf-8", errors="replace", timeout=DOC_CALL_TIMEOUT, env=env)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Fail(f"hc connect: {e.__class__.__name__}")
    return p.returncode, p.stdout

def doc_call(method, params, *, connect=None):
    """One JSON-RPC call over `hc connect` (hello first). Never leaks server error text."""
    payload = "\n".join([
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "hello", "params": {}}),
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": method, "params": params}),
    ]) + "\n"
    rc, stdout = (connect or hc_connect)(payload)
    for line in stdout.splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if isinstance(d, dict) and d.get("id") == 2:
            if d.get("error"):
                err = d["error"]
                data = err.get("data") if isinstance(err, dict) else None
                kind = data.get("kind") if isinstance(data, dict) else None
                if kind == "conflict":
                    raise DocConflict(f"{method}: conflict")
                raise Fail(f"{method}: {kind if kind in RPC_KINDS else 'rpc error'}")
            return d["result"] if isinstance(d.get("result"), dict) else {}
    raise Fail(f"hc connect: no answer to {method} (exit {rc})")

def hc_get(addr, hc=None, *, timeout=DOC_CALL_TIMEOUT):
    if not isinstance(addr, str) or not addr or addr.startswith("-"):
        return None
    try:
        p = subprocess.run([hc or hc_path(), "get", addr, "--json"], capture_output=True,
                           encoding="utf-8", errors="replace", timeout=timeout)
        d = json.loads(p.stdout) if p.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    return d if isinstance(d, dict) else None

def hc_run(args, hc=None):
    try:
        p = subprocess.run([hc or hc_path(), "run", *args], capture_output=True,
                           encoding="utf-8", errors="replace")
    except OSError as e:
        return 127, "", f"{PROG}: hc run: {e.__class__.__name__}\n"
    return p.returncode, p.stdout, p.stderr

def doc_shape_ok(value):
    return (isinstance(value, dict) and isinstance(value.get("spaces"), list) and all(
        isinstance(sp, dict) and isinstance(sp.get("id"), str) and isinstance(sp.get("tabs"), list)
        and all(isinstance(tb, dict) and isinstance(tb.get("id"), str) and isinstance(tb.get("root"), dict)
                for tb in sp["tabs"])
        for sp in value["spaces"]
    ))

def blocks(node):
    if not isinstance(node, dict):
        return []
    if node.get("type") == "block":
        return [node]
    kids = node.get("children")
    return [b for c in kids for b in blocks(c)] if isinstance(kids, list) else []

def valid_node(node):
    if not isinstance(node, dict) or not isinstance(node.get("id"), str) or not node["id"]:
        return False
    if "size" in node:
        sz = node["size"]
        w = sz.get("weight") if isinstance(sz, dict) else None
        if not (isinstance(sz, dict) and set(sz) == {"weight"}
                and isinstance(w, (int, float)) and not isinstance(w, bool) and math.isfinite(w) and w > 0):
            return False
    t = node.get("type")
    if t in ("row", "column"):
        kids = node.get("children")
        return (set(node) <= {"type", "id", "children", "size"}
                and isinstance(kids, list) and bool(kids) and all(valid_node(c) for c in kids))
    if t == "block":
        c = node.get("content")
        return (set(node) <= {"type", "id", "content", "size"} and isinstance(c, dict)
                and set(c) == {"terminal"} and isinstance(c["terminal"], str) and bool(c["terminal"]))
    return False

def nodes_equal(a, b, tol=WEIGHT_TOL):
    if set(a) != set(b):
        return False
    for k in a:
        if k == "size":
            if abs(a["size"]["weight"] - b["size"]["weight"]) > tol:
                return False
        elif k == "children":
            if len(a["children"]) != len(b["children"]) or not all(
                nodes_equal(x, y, tol) for x, y in zip(a["children"], b["children"])
            ):
                return False
        elif a[k] != b[k]:
            return False
    return True

def find_tab(value, space_id, tab_id):
    if len(value["spaces"]) != len({sp["id"] for sp in value["spaces"]}):
        return None, None, None
    found = (None, None, None)
    for si, sp in enumerate(value["spaces"]):
        if len(sp["tabs"]) != len({tb["id"] for tb in sp["tabs"]}):
            return None, None, None
        if sp["id"] == space_id:
            found = next(((si, ti, tb) for ti, tb in enumerate(sp["tabs"]) if tb["id"] == tab_id), found)
    return found

def tidy(value, space_id, tab_id, candidates, is_descendant):
    """Return (new_value, 'tidied') or (None, 'already_tidy'|'refused')."""
    if not doc_shape_ok(value):
        return None, "refused"
    si, ti, tb = find_tab(value, space_id, tab_id)
    if tb is None:
        return None, "refused"
    root = tb["root"]
    if not valid_node(root) or root["type"] != "row" or root["id"] != tab_id:
        return None, "refused"
    chain = [candidates] if isinstance(candidates, str) else list(candidates)
    all_b = blocks(root)
    counts = {}
    for b in all_b:
        t = b["content"]["terminal"]
        counts[t] = counts.get(t, 0) + 1
    anchor = next((c for c in reversed(chain) if counts.get(c) == 1), None)
    if anchor is None:
        return None, "refused"
    ablocks = [b for b in all_b if b["content"]["terminal"] == anchor]
    wblocks = [b for b in all_b if b["content"]["terminal"] != anchor]
    if not wblocks:
        return None, "already_tidy"
    waddrs = [b["content"]["terminal"] for b in wblocks]
    if len(waddrs) != len(set(waddrs)) or not all(is_descendant(a, anchor) for a in waddrs):
        return None, "refused"
    existing = root["children"][1] if len(root["children"]) >= 2 else None
    col_id = existing["id"] if existing and existing["type"] == "column" else "s" + secrets.token_hex(16)
    w = 1.0 / len(wblocks)
    new_root = {"type": "row", "id": root["id"], "children": [
        {"type": "block", "id": ablocks[0]["id"], "content": {"terminal": anchor}, "size": {"weight": 0.7}},
        {"type": "column", "id": col_id, "size": {"weight": 0.3}, "children": [
            {"type": "block", "id": b["id"], "content": {"terminal": b["content"]["terminal"]}, "size": {"weight": w}}
            for b in wblocks
        ]},
    ]}
    if "size" in root:
        new_root["size"] = copy.deepcopy(root["size"])
    if nodes_equal(root, new_root):
        return None, "already_tidy"
    new_value = copy.deepcopy(value)
    new_value["spaces"][si]["tabs"][ti]["root"] = new_root
    check = copy.deepcopy(new_value)
    check["spaces"][si]["tabs"][ti]["root"] = root
    if check != value:
        raise Fail("tidy invariant failed; leaving document unchanged")
    return new_value, "tidied"

def _check_deadline(deadline, clock):
    if deadline is not None and clock() >= deadline:
        raise Fail("out of time for the Herdr app document")

def edit_doc(change, *, rpc=doc_call, deadline=None, clock=time.monotonic):
    for _ in range(DOC_RETRIES):
        _check_deadline(deadline, clock)
        cur = rpc("doc.get", {"name": APP_DOC})
        value = cur.get("value")
        if value is None:
            raise Fail("no Herdr app document yet")
        if not doc_shape_ok(value):
            raise Fail("the Herdr app document has an unexpected shape")
        new = change(copy.deepcopy(value))
        if new is None:
            return None
        _check_deadline(deadline, clock)
        try:
            rpc("doc.set", {"name": APP_DOC, "value": new, "version": cur.get("version", 0)})
            return new
        except DocConflict:
            continue
    raise Fail(f"the Herdr app document kept changing; gave up after {DOC_RETRIES} tries")

def wait_for_block(space_id, tab_id, addr, *, rpc=doc_call, clock=time.monotonic, sleep=time.sleep, deadline=None):
    end = min(clock() + POLL_TIMEOUT, deadline) if deadline is not None else clock() + POLL_TIMEOUT
    while True:
        _check_deadline(deadline, clock)
        value = rpc("doc.get", {"name": APP_DOC}).get("value")
        if value is not None and doc_shape_ok(value):
            _, _, tb = find_tab(value, space_id, tab_id)
            if tb is not None and any(
                isinstance(b.get("content"), dict) and b["content"].get("terminal") == addr for b in blocks(tb["root"])
            ):
                return True
        _check_deadline(deadline, clock)
        rem = end - clock()
        if rem <= 0:
            return False
        sleep(min(POLL_INTERVAL, rem))

def tab_labels(info):
    labels = info.get("labels") if isinstance(info, dict) else None
    sp, tb = (labels.get("herdr.space"), labels.get("herdr.tab")) if isinstance(labels, dict) else (None, None)
    return (sp, tb) if isinstance(sp, str) and isinstance(tb, str) and ID_RE.fullmatch(sp) and ID_RE.fullmatch(tb) else (None, None)

def ancestors(start, get_term):
    cur, seen = start, {start}
    for _ in range(MAX_ANCESTOR_DEPTH):
        info = get_term(cur)
        p = info.get("parent") if isinstance(info, dict) else None
        if not isinstance(p, str) or not p or p in seen:
            return
        seen.add(p)
        yield p
        cur = p

def anchor_chain(start, space_id, tab_id, get_term):
    chain = [start]
    for p in ancestors(start, get_term):
        if tab_labels(get_term(p)) != (space_id, tab_id):
            break
        chain.append(p)
    return chain

def is_descendant_of(addr, anchor, get_term):
    return anchor in ancestors(addr, get_term)

def parse_options(opts):
    seen, i = set(), 0
    while i < len(opts):
        opt, val = opts[i], None
        if opt in ("--label", "-l"):
            val, i = (opts[i + 1] if i + 1 < len(opts) else ""), i + 2
        elif opt.startswith("--label="):
            val, i = opt.split("=", 1)[1], i + 1
        elif opt.startswith("-l") and len(opt) > 2:
            val, i = (opt[3:] if opt.startswith("-l=") else opt[2:]), i + 1
        elif opt in VALUE_OPTS:
            i += 2
        elif opt in REFUSED_OPTS or opt.startswith(("--parent=", "--no-parent=", "--on=")):
            raise ValueError(f"cannot pass {opt.split('=', 1)[0]}")
        elif opt == "--tidy":
            raise ValueError("--tidy cannot be combined with a command")
        elif opt.startswith("-"):
            if opt in REQUIRED_FLAGS:
                seen.add(opt)
            i += 1
        else:
            break
        if val is not None and val.split("=", 1)[0] in RESERVED_LABELS:
            raise ValueError(f"cannot pass {val.split('=', 1)[0]} label")
    return [f for f in REQUIRED_FLAGS if f not in seen]

def parse_address(stdout):
    for text in [stdout] + list(reversed(stdout.splitlines())):
        try:
            d = json.loads(text) if text.strip() else None
        except ValueError:
            continue
        if isinstance(d, dict) and isinstance(d.get("address"), str) and d["address"]:
            return d["address"]
    return None

def tidy_tab(space_id, tab_id, caller, *, caller_info=None, rpc=doc_call, get_term=hc_get, err=None,
             deadline=None, clock=time.monotonic, report_refusal=False):
    cache, status = ({caller: caller_info} if caller_info is not None else {}), [None]
    def cached_get(addr):
        if addr not in cache:
            _check_deadline(deadline, clock)
            if get_term is hc_get and deadline is not None:
                cache[addr] = hc_get(addr, timeout=max(1.0, min(DOC_CALL_TIMEOUT, deadline - clock())))
            else:
                cache[addr] = get_term(addr)
        return cache[addr]
    try:
        candidates = anchor_chain(caller, space_id, tab_id, cached_get)
        def change(v):
            new, st = tidy(v, space_id, tab_id, candidates, lambda a, anc: is_descendant_of(a, anc, cached_get))
            status[0] = st
            return new
        edit_doc(change, rpc=rpc, deadline=deadline, clock=clock)
    except Fail as e:
        (err or sys.stderr).write(f"{PROG}: {e}\n")
        return False
    if report_refusal and status[0] == "refused":
        (err or sys.stderr).write(f"{PROG}: tab left unchanged (missing tab, unexpected tree, or foreign terminal)\n")
    return True

def read_caller_tab(caller, get_term):
    info = get_term(caller)
    return (info, *tab_labels(info)) if info is not None else (None, None, None)

def main(argv=None, *, env=None, run_hc=hc_run, get_term=hc_get, rpc=doc_call,
         clock=time.monotonic, sleep=time.sleep, out=None, err=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    env = os.environ if env is None else env
    out, err = (sys.stdout if out is None else out), (sys.stderr if err is None else err)
    if not argv:
        err.write(USAGE); return 2
    if argv in (["--help"], ["-h"]):
        out.write(USAGE); return 0
    caller = (env.get("HC_TERMINAL_ID") or "").strip()
    if argv[0] == "--tidy":
        if len(argv) != 1:
            err.write(USAGE); return 2
        if not caller:
            err.write(f"{PROG}: HC_TERMINAL_ID is not set\n"); return 2
        info, space_id, tab_id = read_caller_tab(caller, get_term)
        if not space_id:
            msg = "could not read parent terminal" if info is None else "parent has no valid Herdr tab labels"
            err.write(f"{PROG}: {msg}; nothing to tidy\n"); return 1
        ok = tidy_tab(space_id, tab_id, caller, caller_info=info, rpc=rpc, get_term=get_term, err=err,
                      deadline=clock() + TIDY_BUDGET, clock=clock, report_refusal=True)
        return 0 if ok else 1
    if "--" not in argv:
        err.write(USAGE); return 2
    sep = argv.index("--")
    opts, cmd = argv[:sep], argv[sep + 1:]
    if not cmd:
        err.write(USAGE); return 2
    try:
        missing = parse_options(opts)
    except ValueError as e:
        err.write(f"{PROG}: {e}\n"); return 2
    if not caller:
        err.write(f"{PROG}: HC_TERMINAL_ID is not set\n"); return 2
    info, space_id, tab_id = read_caller_tab(caller, get_term)
    if info is None:
        err.write(f"{PROG}: could not read parent terminal; starting worker without Herdr tab labels\n")
    labels = [f"--label=herdr.space={space_id}", f"--label=herdr.tab={tab_id}"] if space_id else []
    rc, stdout, stderr = run_hc([*missing, *labels, *opts, "--", *cmd])
    if rc < 0:
        rc = 128 + (-rc)
    out.write(stdout); out.flush()
    if stderr:
        err.write(stderr)
    addr = parse_address(stdout) if rc == 0 else None
    if rc != 0 or not addr or not space_id:
        return rc
    deadline = clock() + TIDY_BUDGET
    try:
        if not wait_for_block(space_id, tab_id, addr, rpc=rpc, clock=clock, sleep=sleep, deadline=deadline):
            err.write(f"{PROG}: new pane did not appear in Herdr app; tab not tidied\n"); return rc
    except Fail as e:
        err.write(f"{PROG}: {e}\n"); return rc
    tidy_tab(space_id, tab_id, caller, caller_info=info, rpc=rpc, get_term=get_term,
             err=err, deadline=deadline, clock=clock)
    return rc

if __name__ == "__main__":
    sys.exit(main())
