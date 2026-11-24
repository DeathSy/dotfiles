#!/usr/bin/env python3
"""Collect Claude (CLIProxyAPI), Codex and Antigravity (agy) quota usage into a node_exporter textfile.

Writes atomically via <output>.tmp + fsync + os.replace. Never logs secrets,
tokens, management keys, full email addresses, or exception messages.
"""

import argparse
import base64
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ANTHROPIC_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
HTTP_TIMEOUT = 10.0

METRICS = [
    ("ai_usage_utilization_percent", "AI subscription quota utilization percentage (0-100)."),
    ("ai_usage_resets_at_seconds", "Unix timestamp when the AI subscription quota window resets."),
    ("ai_usage_observed_at_seconds", "Unix timestamp when the usage values were observed."),
    ("ai_usage_up", "Whether fetching AI usage metrics for this account succeeded (1) or failed (0)."),
    ("ai_usage_collector_last_run_seconds", "Unix timestamp of the last AI usage collector run."),
]


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if fp is not None:
            fp.close()
        raise urllib.error.HTTPError(req.full_url, code, "redirect refused", headers, None)


HTTP_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())


def log(msg):
    sys.stderr.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} ai-usage-exporter: {msg}\n")


def is_number(val):
    return isinstance(val, (int, float)) and not isinstance(val, bool) and math.isfinite(val)


def parse_timestamp(val):
    if is_number(val):
        return float(val)
    if not isinstance(val, str) or not val.strip():
        return None
    s = val.strip()
    if s.endswith(("Z", "z")):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        return None
    return (dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)).timestamp()


def fmt_num(val):
    rounded = round(val)
    return str(int(rounded)) if abs(val - rounded) < 1e-6 else f"{val:.3f}".rstrip("0").rstrip(".")


def fmt_labels(labels):
    esc = lambda v: v.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')
    return "{" + ",".join(f'{k}="{esc(v)}"' for k, v in labels.items()) + "}"


def read_keychain_secret(service, account):
    try:
        res = subprocess.run(
            ["/usr/bin/security", "find-generic-password", "-w", "-s", service, "-a", account],
            capture_output=True, text=True, timeout=5,
        )
    except Exception as exc:
        log(f"Keychain lookup failed ({type(exc).__name__})")
        return None
    if res.returncode != 0:
        log(f"management key not found in Keychain ({service}/{account}); run ai-usage-keychain-sync")
        return None
    secret = res.stdout.rstrip("\r\n")
    if not secret:
        log(f"management key in Keychain ({service}/{account}) is empty")
        return None
    if not secret.isascii() or not secret.isprintable():
        log("management key has unexpected characters")
        return None
    return secret


def http_json(url, *, method="GET", headers=None, body=None):
    req_headers = dict(headers or {})
    data = json.dumps(body).encode("utf-8") if body is not None else None
    if data is not None:
        req_headers.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    with HTTP_OPENER.open(req, timeout=HTTP_TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))


def claude_account_label(entry):
    name = str(entry.get("name") or "").removeprefix("claude-").removesuffix(".json")
    name = re.sub(r"^[0-9a-f]{8}-", "", name)  # auth files are named claude-<hex8>-<email>.json
    return name.split("@", 1)[0].strip() or str(entry.get("auth_index") or "")[:8] or "unknown"


def dedupe_labels(raw_labels):
    used, out = set(), []
    for base in raw_labels:
        label, n = base, 2
        while label in used:
            label, n = f"{base}_{n}", n + 1
        used.add(label)
        out.append(label)
    return out


def parse_claude_usage(body):
    windows = {}
    limits = body.get("limits")
    if isinstance(limits, list) and limits:
        for item in limits:
            if not isinstance(item, dict):
                continue
            kind = item.get("kind")
            window = {"session": "5h", "weekly_all": "7d"}.get(kind)
            if kind == "weekly_scoped":
                scope = item.get("scope") if isinstance(item.get("scope"), dict) else {}
                model = scope.get("model") if isinstance(scope.get("model"), dict) else {}
                display = model.get("display_name")
                if isinstance(display, str):
                    slug = re.sub(r"[^a-z0-9]+", "_", display.strip().lower()).strip("_")
                    window = f"7d_{slug}" if slug else None
            if window and is_number(item.get("percent")):
                windows[window] = (float(item["percent"]), parse_timestamp(item.get("resets_at")))
    else:
        for field, window in (("five_hour", "5h"), ("seven_day", "7d")):
            entry = body.get(field)
            if isinstance(entry, dict) and is_number(entry.get("utilization")):
                windows[window] = (float(entry["utilization"]), parse_timestamp(entry.get("resets_at")))
    return windows


def fetch_claude_account(base, auth_headers, auth_index, label):
    down = {"provider": "claude", "account": label, "up": 0}
    if not auth_index:
        log(f"claude account {label!r}: missing auth_index")
        return down
    payload = {
        "authIndex": auth_index, "method": "GET", "url": ANTHROPIC_USAGE_URL,
        "header": {"Authorization": "Bearer $TOKEN$", "anthropic-beta": "oauth-2025-04-20", "Accept": "application/json"},
    }
    try:
        resp = http_json(f"{base}/v0/management/api-call", method="POST", headers=auth_headers, body=payload)
        if not isinstance(resp, dict):
            raise ValueError
        if resp.get("status_code") != 200:
            log(f"claude account {label!r}: upstream returned HTTP {resp.get('status_code')}")
            return down
        body = json.loads(resp["body"]) if isinstance(resp.get("body"), str) else resp.get("body")
        if not isinstance(body, dict):
            raise ValueError
        windows = parse_claude_usage(body)
        if not windows:
            log(f"claude account {label!r}: no usage windows found")
            return down
        return {"provider": "claude", "account": label, "up": 1, "observed_at": time.time(), "windows": windows}
    except urllib.error.HTTPError as exc:
        log(f"claude account {label!r}: gateway api-call failed (HTTP {exc.code})")
        return down
    except Exception as exc:
        log(f"claude account {label!r}: fetch/parse failed ({type(exc).__name__})")
        return down


def collect_claude(gateway_url, mgmt_key):
    base = gateway_url.rstrip("/")
    auth_headers = {"Authorization": f"Bearer {mgmt_key}", "Accept": "application/json"}
    gateway_down = [{"provider": "claude", "account": "gateway", "up": 0}]
    try:
        listing = http_json(f"{base}/v0/management/auth-files", method="GET", headers=auth_headers)
    except urllib.error.HTTPError as exc:
        log(f"GET /v0/management/auth-files failed (HTTP {exc.code})")
        return gateway_down
    except Exception as exc:
        log(f"GET /v0/management/auth-files failed ({type(exc).__name__})")
        return gateway_down

    files = listing.get("files") if isinstance(listing, dict) else None
    if not isinstance(files, list):
        log("GET /v0/management/auth-files returned unexpected structure")
        return gateway_down

    enabled = [f for f in files if isinstance(f, dict) and f.get("type") == "claude" and not f.get("disabled")]
    labels = dedupe_labels([claude_account_label(f) for f in enabled])
    return [
        fetch_claude_account(base, auth_headers, str(e.get("auth_index") or "").strip(), lbl)
        for e, lbl in zip(enabled, labels)
    ]


def extract_codex_rate_limits(obj):
    payload = obj.get("payload") if isinstance(obj, dict) else None
    rl = payload.get("rate_limits") if isinstance(payload, dict) else None
    if not isinstance(rl, dict):
        return None
    windows = {}
    for slot in ("primary", "secondary"):
        entry = rl.get(slot)
        if not isinstance(entry, dict):
            continue
        wm, used = entry.get("window_minutes"), entry.get("used_percent")
        if is_number(wm) and is_number(used) and int(round(float(wm))) > 0:
            mins = int(round(float(wm)))
            windows[{300: "5h", 10080: "7d"}.get(mins, f"{mins}m")] = (float(used), parse_timestamp(entry.get("resets_at")))
    return (windows, parse_timestamp(obj.get("timestamp"))) if windows else None


def collect_codex(sessions_dir):
    down = {"provider": "codex", "account": "codex", "up": 0}
    if not sessions_dir.is_dir():
        log(f"codex sessions directory not found: {sessions_dir}")
        return down
    files = []
    for path in sessions_dir.rglob("*.jsonl"):
        try:
            files.append((path.stat().st_mtime, path))
        except OSError:
            continue
    # Newest file with a rate_limits line: a just-started session has none yet.
    last_found = None
    for mtime, path in sorted(files, key=lambda f: f[0], reverse=True)[:20]:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if '"rate_limits"' not in line:
                    continue
                try:
                    extracted = extract_codex_rate_limits(json.loads(line))
                except json.JSONDecodeError:
                    continue
                if extracted is not None:
                    last_found = extracted
        if last_found is not None:
            break
    if last_found is None:
        log("codex: no rate_limits in the newest session files")
        return down
    windows, line_ts = last_found
    return {"provider": "codex", "account": "codex", "up": 1, "observed_at": line_ts if line_ts is not None else mtime, "windows": windows}

AGY_BIN = "/opt/homebrew/bin/agy"
AGY_KEYCHAIN = ("gemini", "antigravity")  # agy's own login (go-keyring item: service, account), refreshed by agy
AGY_REFRESH_STAMP = Path.home() / ".local/state/ai-usage-exporter/agy-refresh"
CLOUDCODE_URL = "https://daily-cloudcode-pa.googleapis.com/v1internal:"


def read_agy_token():
    """Returns (access_token, expiry_seconds) from agy's Keychain login, or None.
    Only the short-lived access token is used; the refresh token is never used."""
    service, account = AGY_KEYCHAIN
    res = subprocess.run(["/usr/bin/security", "find-generic-password", "-w", "-s", service, "-a", account],
                         capture_output=True, text=True, timeout=5)
    raw = res.stdout.strip()
    prefix = "go-keyring-base64:"
    if res.returncode != 0 or not raw.startswith(prefix):
        return None
    tok = json.loads(base64.b64decode(raw[len(prefix):])).get("token") or {}
    access = tok.get("access_token")
    if not isinstance(access, str) or not access.strip() or not access.isascii() or not access.isprintable():
        return None
    return access, parse_timestamp(tok.get("expiry"))


def refresh_agy_login():
    """Runs `agy models` so agy refreshes its own login; at most once per 10 minutes."""
    try:
        if time.time() - AGY_REFRESH_STAMP.stat().st_mtime < 600:
            return
    except OSError:
        pass
    AGY_REFRESH_STAMP.parent.mkdir(parents=True, exist_ok=True)
    AGY_REFRESH_STAMP.touch()
    env = dict(os.environ, PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    proc = subprocess.Popen([AGY_BIN, "models"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, env=env, start_new_session=True)
    try:
        proc.wait(timeout=60)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, 9)
        proc.wait()
        log("agy: login refresh timed out")


def agy_pool(model_id):
    mid = model_id.lower()
    if mid.startswith("gemini"):
        return "gemini"
    if mid.startswith(("claude", "gpt")):
        return "claude+gpt"
    return None  # internal tab/autocomplete models


def collect_agy():
    """agy's per-model quota from Google, grouped into its pools (Gemini models, and the Claude/GPT-OSS models)."""
    down = [{"provider": "agy", "account": "agy", "up": 0}]
    got = read_agy_token()
    if got is None:
        log("agy: no usable login in Keychain (run agy once to log in)")
        return down
    if got[1] is None or got[1] < time.time() + 60:
        try:
            refresh_agy_login()
        except OSError as exc:
            log(f"agy: login refresh failed ({type(exc).__name__})")
        got = read_agy_token() or got
    headers = {"Authorization": f"Bearer {got[0]}", "User-Agent": "antigravity"}
    project = http_json(CLOUDCODE_URL + "loadCodeAssist", method="POST", headers=headers,
                        body={"metadata": {"ideType": "ANTIGRAVITY"}}).get("cloudaicompanionProject")
    models = http_json(CLOUDCODE_URL + "fetchAvailableModels", method="POST", headers=headers,
                       body={"project": project}).get("models") or {}
    pools = {}
    for model_id, model in models.items():
        pool, quota = agy_pool(model_id), model.get("quotaInfo")
        if pool is None or not isinstance(quota, dict):
            continue
        remaining = quota.get("remainingFraction")
        if not is_number(remaining):
            if "resetTime" not in quota:
                continue
            remaining = 0  # proto3 JSON omits zero values: an exhausted model has only resetTime
        pct = round((1 - min(max(float(remaining), 0.0), 1.0)) * 100, 1)
        resets_at = parse_timestamp(quota.get("resetTime"))
        if pool not in pools or pct > pools[pool][0]:
            pools[pool] = (pct, resets_at)
    if not pools:
        log("agy: no quota info in the model list")
        return down
    now = time.time()
    # Google reports one rolling window per pool (about 5 hours on the Ultra plan, 2026-11-24).
    return [{"provider": "agy", "account": pool, "up": 1, "observed_at": now, "windows": {"5h": value}}
            for pool, value in sorted(pools.items())]


def render_prometheus(accounts, last_run_seconds):
    samples = {name: [] for name, _ in METRICS}
    for acc in accounts:
        provider, account = str(acc["provider"]), str(acc["account"])
        up = 1 if acc.get("up") else 0
        acct_lbls = fmt_labels({"provider": provider, "account": account})
        samples["ai_usage_up"].append(f"ai_usage_up{acct_lbls} {up}")
        if not up:
            continue
        if is_number(acc.get("observed_at")):
            samples["ai_usage_observed_at_seconds"].append(f"ai_usage_observed_at_seconds{acct_lbls} {fmt_num(float(acc['observed_at']))}")
        for window, (pct, resets_at) in sorted((acc.get("windows") or {}).items()):
            lbls = fmt_labels({"provider": provider, "account": account, "window": window})
            samples["ai_usage_utilization_percent"].append(f"ai_usage_utilization_percent{lbls} {fmt_num(pct)}")
            if is_number(resets_at):
                samples["ai_usage_resets_at_seconds"].append(f"ai_usage_resets_at_seconds{lbls} {fmt_num(float(resets_at))}")

    samples["ai_usage_collector_last_run_seconds"].append(f"ai_usage_collector_last_run_seconds {fmt_num(last_run_seconds)}")
    blocks = [
        "\n".join([f"# HELP {name} {help_text}", f"# TYPE {name} gauge", *samples[name]])
        for name, help_text in METRICS if samples[name]
    ]
    return "\n".join(blocks) + "\n"


def write_atomic(output_path, content):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = output_path.parent / f"{output_path.name}.tmp"
    with tmp_path.open("w", encoding="utf-8") as fh:
        fh.write(content)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp_path, output_path)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Export AI subscription usage to node_exporter textfile.")
    for flag in ("--gateway-url", "--keychain-service", "--keychain-account", "--output", "--codex-sessions-dir"):
        parser.add_argument(flag, required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    accounts = []
    mgmt_key = read_keychain_secret(args.keychain_service, args.keychain_account)
    if mgmt_key is None:
        accounts.append({"provider": "claude", "account": "gateway", "up": 0})
    else:
        try:
            accounts.extend(collect_claude(args.gateway_url, mgmt_key))
        except Exception as exc:
            log(f"claude collection failed ({type(exc).__name__})")
            accounts.append({"provider": "claude", "account": "gateway", "up": 0})

    try:
        accounts.append(collect_codex(Path(args.codex_sessions_dir).expanduser()))
    except Exception as exc:
        log(f"codex collection failed ({type(exc).__name__})")
        accounts.append({"provider": "codex", "account": "codex", "up": 0})

    try:
        accounts.extend(collect_agy())
    except Exception as exc:
        log(f"agy collection failed ({type(exc).__name__})")
        accounts.append({"provider": "agy", "account": "agy", "up": 0})

    text = render_prometheus(accounts, time.time())
    if args.dry_run:
        sys.stdout.write(text)
    else:
        write_atomic(Path(args.output).expanduser(), text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
