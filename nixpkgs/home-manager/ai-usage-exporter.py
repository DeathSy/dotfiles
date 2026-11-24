#!/usr/bin/env python3
"""Collect Claude (via CLIProxyAPI) and Codex quota usage into a node_exporter textfile.

Writes metrics atomically to <output>.tmp then renames to <output>.
Never logs secrets, tokens, management keys, or full email addresses.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple
import urllib.error
import urllib.request


DEFAULT_GATEWAY_URL = "http://127.0.0.1:8317"
DEFAULT_KEYCHAIN_SERVICE = "ai-usage-exporter"
DEFAULT_KEYCHAIN_ACCOUNT = "cliproxy-management-secret"
DEFAULT_OUTPUT = "~/.local/state/node-exporter/textfile/ai_usage.prom"
DEFAULT_CODEX_SESSIONS = "~/.codex/sessions"
ANTHROPIC_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
MAX_CODEX_FILES_TO_SCAN = 20


def log(msg: str) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    sys.stderr.write(f"{ts} ai-usage-exporter: {msg}\n")


def is_number(val: Any) -> bool:
    return isinstance(val, (int, float)) and not isinstance(val, bool) and math.isfinite(val)


def parse_timestamp(val: Any) -> Optional[float]:
    if val is None:
        return None
    if is_number(val):
        return float(val)
    if isinstance(val, str):
        s = val.strip()
        if not s:
            return None
        try:
            num = float(s)
            if math.isfinite(num):
                return num
        except ValueError:
            pass
        if s.endswith(("Z", "z")):
            s = s[:-1] + "+00:00"
        try:
            dt = datetime.fromisoformat(s)
        except ValueError:
            return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    return None


def fmt_num(val: float) -> str:
    if not math.isfinite(val):
        raise ValueError(f"non-finite value: {val}")
    if val == int(val):
        return str(int(val))
    return f"{val:.4f}".rstrip("0").rstrip(".")


def fmt_ts(val: float) -> str:
    if not math.isfinite(val):
        raise ValueError(f"non-finite timestamp: {val}")
    # Preserve whole seconds cleanly without scientific notation.
    rounded = round(val)
    if abs(val - rounded) < 1e-6:
        return str(int(rounded))
    return f"{val:.3f}".rstrip("0").rstrip(".")


def escape_label(val: str) -> str:
    return val.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def format_labels(labels: Dict[str, str]) -> str:
    if not labels:
        return ""
    parts = [f'{k}="{escape_label(v)}"' for k, v in labels.items()]
    return "{" + ",".join(parts) + "}"


def read_keychain_secret(service: str, account: str) -> Optional[str]:
    try:
        res = subprocess.run(
            ["/usr/bin/security", "find-generic-password", "-w", "-s", service, "-a", account],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        log(f"failed to run security for Keychain lookup ({type(exc).__name__})")
        return None
    if res.returncode != 0:
        log(
            f"management key not found in Keychain ({service}/{account}); "
            "run ai-usage-keychain-sync at the console"
        )
        return None
    secret = res.stdout.rstrip("\r\n")
    if not secret:
        log(f"management key in Keychain ({service}/{account}) is empty")
        return None
    return secret


def http_json(
    url: str,
    *,
    method: str = "GET",
    headers: Optional[Dict[str, str]] = None,
    body: Optional[Dict[str, Any]] = None,
    timeout: float = 10.0,
) -> Any:
    req_headers = dict(headers or {})
    data: Optional[bytes] = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        req_headers.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8"))


def claude_account_label(entry: Dict[str, Any]) -> str:
    name = str(entry.get("name") or "")
    if name.startswith("claude-"):
        name = name[len("claude-") :]
    if name.endswith(".json"):
        name = name[: -len(".json")]
    if "@" in name:
        name = name.split("@", 1)[0]
    name = name.strip()
    if name:
        return name
    auth_index = str(entry.get("auth_index") or "")
    return auth_index[:8] or "unknown"


def slugify_scope_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.strip().lower()).strip("_")


def parse_claude_usage(body: Dict[str, Any]) -> Dict[str, Tuple[float, Optional[float]]]:
    """Return {window: (utilization_percent, resets_at_unix_or_none)}."""
    windows: Dict[str, Tuple[float, Optional[float]]] = {}

    limits = body.get("limits")
    if isinstance(limits, list) and limits:
        for item in limits:
            if not isinstance(item, dict):
                continue
            kind = item.get("kind")
            window: Optional[str] = None
            if kind == "session":
                window = "5h"
            elif kind == "weekly_all":
                window = "7d"
            elif kind == "weekly_scoped":
                scope = item.get("scope") if isinstance(item.get("scope"), dict) else {}
                model = scope.get("model") if isinstance(scope.get("model"), dict) else {}
                display = model.get("display_name") or model.get("name") or model.get("id")
                if isinstance(display, str) and display.strip():
                    slug = slugify_scope_name(display)
                    if slug:
                        window = f"7d_{slug}"
            if not window:
                continue
            pct = item.get("percent")
            if pct is None:
                pct = item.get("utilization")
            if not is_number(pct):
                continue
            resets_at = parse_timestamp(item.get("resets_at"))
            windows[window] = (float(pct), resets_at)

    if not windows:
        for field, window in (("five_hour", "5h"), ("seven_day", "7d")):
            entry = body.get(field)
            if not isinstance(entry, dict):
                continue
            pct = entry.get("utilization")
            if pct is None:
                pct = entry.get("percent")
            if not is_number(pct):
                continue
            resets_at = parse_timestamp(entry.get("resets_at"))
            windows[window] = (float(pct), resets_at)

    return windows


def collect_claude(
    gateway_url: str,
    mgmt_key: str,
    timeout: float,
    deadline: float,
) -> List[Dict[str, Any]]:
    """Return per-account result dicts: {provider, account, up, observed_at, windows}."""
    base = gateway_url.rstrip("/")
    auth_headers = {
        "Authorization": f"Bearer {mgmt_key}",
        "Accept": "application/json",
    }

    remaining = deadline - time.monotonic()
    if remaining <= 0.5:
        log("time budget exhausted before listing Claude accounts")
        return []

    try:
        listing = http_json(
            f"{base}/v0/management/auth-files",
            method="GET",
            headers=auth_headers,
            timeout=min(timeout, remaining),
        )
    except urllib.error.HTTPError as exc:
        log(f"GET /v0/management/auth-files failed with HTTP {exc.code}")
        return []
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        log(f"GET /v0/management/auth-files failed ({type(exc).__name__})")
        return []

    files = listing.get("files") if isinstance(listing, dict) else None
    if not isinstance(files, list):
        log("GET /v0/management/auth-files returned unexpected structure")
        return []

    enabled = [
        f for f in files if isinstance(f, dict) and f.get("type") == "claude" and not f.get("disabled")
    ]
    raw_labels = [claude_account_label(f) for f in enabled]
    label_counts: Dict[str, int] = {}
    for lbl in raw_labels:
        label_counts[lbl] = label_counts.get(lbl, 0) + 1

    results: List[Dict[str, Any]] = []
    seen_labels: set[str] = set()
    for entry, raw_label in zip(enabled, raw_labels):
        auth_index = str(entry.get("auth_index") or "").strip()
        label = raw_label
        if label_counts[raw_label] > 1 and auth_index:
            label = f"{raw_label}_{auth_index[:4]}"
        if label in seen_labels:
            continue
        seen_labels.add(label)

        if not auth_index:
            log(f"claude account {label!r}: missing auth_index")
            results.append({"provider": "claude", "account": label, "up": 0})
            continue

        remaining = deadline - time.monotonic()
        if remaining <= 0.5:
            log(f"claude account {label!r}: skipped (time budget exhausted)")
            results.append({"provider": "claude", "account": label, "up": 0})
            continue

        payload = {
            "authIndex": auth_index,
            "method": "GET",
            "url": ANTHROPIC_USAGE_URL,
            "header": {
                "Authorization": "Bearer $TOKEN$",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
            },
        }
        try:
            resp = http_json(
                f"{base}/v0/management/api-call",
                method="POST",
                headers=auth_headers,
                body=payload,
                timeout=min(timeout, remaining),
            )
            if not isinstance(resp, dict):
                raise ValueError("non-object api-call response")
            status_code = resp.get("status_code")
            if status_code != 200:
                log(f"claude account {label!r}: upstream returned HTTP {status_code}")
                results.append({"provider": "claude", "account": label, "up": 0})
                continue
            body = resp.get("body")
            if isinstance(body, str):
                body = json.loads(body)
            if not isinstance(body, dict):
                raise ValueError("non-object usage body")
            windows = parse_claude_usage(body)
            if not windows:
                log(f"claude account {label!r}: no usage windows found in response")
                results.append({"provider": "claude", "account": label, "up": 0})
                continue
            results.append(
                {
                    "provider": "claude",
                    "account": label,
                    "up": 1,
                    "observed_at": time.time(),
                    "windows": windows,
                }
            )
        except urllib.error.HTTPError as exc:
            log(f"claude account {label!r}: gateway api-call failed with HTTP {exc.code}")
            results.append({"provider": "claude", "account": label, "up": 0})
        except (urllib.error.URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError) as exc:
            log(f"claude account {label!r}: fetch/parse failed ({type(exc).__name__})")
            results.append({"provider": "claude", "account": label, "up": 0})

    return results


def codex_window_label(window_minutes: Any) -> Optional[str]:
    if not is_number(window_minutes):
        return None
    mins = int(round(float(window_minutes)))
    if mins <= 0:
        return None
    if mins == 300:
        return "5h"
    if mins == 10080:
        return "7d"
    return f"{mins}m"


def extract_codex_rate_limits(obj: Any) -> Optional[Tuple[Dict[str, Tuple[float, Optional[float]]], Optional[float]]]:
    if not isinstance(obj, dict):
        return None

    rl: Any = None
    ts_candidate: Any = obj.get("timestamp")
    if isinstance(obj.get("rate_limits"), dict):
        rl = obj["rate_limits"]
    elif isinstance(obj.get("payload"), dict) and isinstance(obj["payload"].get("rate_limits"), dict):
        rl = obj["payload"]["rate_limits"]
        if ts_candidate is None:
            ts_candidate = obj["payload"].get("timestamp")
    elif isinstance(obj.get("msg"), dict) and isinstance(obj["msg"].get("rate_limits"), dict):
        rl = obj["msg"]["rate_limits"]
        if ts_candidate is None:
            ts_candidate = obj["msg"].get("timestamp")
    if not isinstance(rl, dict):
        return None

    windows: Dict[str, Tuple[float, Optional[float]]] = {}
    for slot in ("primary", "secondary"):
        entry = rl.get(slot)
        if not isinstance(entry, dict):
            continue
        used = entry.get("used_percent")
        window = codex_window_label(entry.get("window_minutes"))
        if not window or not is_number(used):
            continue
        resets_at = parse_timestamp(entry.get("resets_at"))
        windows[window] = (float(used), resets_at)

    if not windows:
        return None
    return windows, parse_timestamp(ts_candidate)


def parse_codex_session_file(path: Path, mtime: float) -> Optional[Tuple[Dict[str, Tuple[float, Optional[float]]], float]]:
    last_found: Optional[Tuple[Dict[str, Tuple[float, Optional[float]]], Optional[float]]] = None
    try:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if '"rate_limits"' not in line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                extracted = extract_codex_rate_limits(obj)
                if extracted is not None:
                    last_found = extracted
    except OSError:
        return None

    if last_found is None:
        return None
    windows, line_ts = last_found
    observed = line_ts if line_ts is not None else mtime
    return windows, observed


def collect_codex(sessions_dir: Path) -> Dict[str, Any]:
    if not sessions_dir.is_dir():
        log(f"codex sessions directory not found: {sessions_dir}")
        return {"provider": "codex", "account": "codex", "up": 0}

    candidates: List[Tuple[float, Path]] = []
    for root, _dirs, filenames in os.walk(sessions_dir):
        for fname in filenames:
            if not fname.endswith(".jsonl"):
                continue
            p = Path(root) / fname
            try:
                st = p.stat()
            except OSError:
                continue
            candidates.append((st.st_mtime, p))

    candidates.sort(key=lambda item: item[0], reverse=True)
    for mtime, path in candidates[:MAX_CODEX_FILES_TO_SCAN]:
        parsed = parse_codex_session_file(path, mtime)
        if parsed is not None:
            windows, observed = parsed
            return {
                "provider": "codex",
                "account": "codex",
                "up": 1,
                "observed_at": observed,
                "windows": windows,
            }

    log("codex: no session file with rate_limits found")
    return {"provider": "codex", "account": "codex", "up": 0}


def render_prometheus(accounts: List[Dict[str, Any]], last_run_seconds: float) -> str:
    util_lines: List[str] = []
    reset_lines: List[str] = []
    observed_lines: List[str] = []
    up_lines: List[str] = []

    for acc in accounts:
        provider = str(acc["provider"])
        account = str(acc["account"])
        up = 1 if acc.get("up") else 0
        up_lines.append(
            f"ai_usage_up{format_labels({'provider': provider, 'account': account})} {up}"
        )
        if not up:
            continue
        obs = acc.get("observed_at")
        if is_number(obs):
            observed_lines.append(
                f"ai_usage_observed_at_seconds{format_labels({'provider': provider, 'account': account})} {fmt_ts(float(obs))}"
            )
        windows: Dict[str, Tuple[float, Optional[float]]] = acc.get("windows") or {}
        for window in sorted(windows):
            pct, resets_at = windows[window]
            lbls = format_labels({"provider": provider, "account": account, "window": window})
            util_lines.append(f"ai_usage_utilization_percent{lbls} {fmt_num(pct)}")
            if is_number(resets_at):
                reset_lines.append(f"ai_usage_resets_at_seconds{lbls} {fmt_ts(float(resets_at))}")

    blocks: List[str] = []
    if util_lines:
        blocks.append(
            "\n".join(
                [
                    "# HELP ai_usage_utilization_percent AI subscription quota utilization percentage (0-100).",
                    "# TYPE ai_usage_utilization_percent gauge",
                    *util_lines,
                ]
            )
        )
    if reset_lines:
        blocks.append(
            "\n".join(
                [
                    "# HELP ai_usage_resets_at_seconds Unix timestamp when the AI subscription quota window resets.",
                    "# TYPE ai_usage_resets_at_seconds gauge",
                    *reset_lines,
                ]
            )
        )
    if observed_lines:
        blocks.append(
            "\n".join(
                [
                    "# HELP ai_usage_observed_at_seconds Unix timestamp when the usage values were observed.",
                    "# TYPE ai_usage_observed_at_seconds gauge",
                    *observed_lines,
                ]
            )
        )
    if up_lines:
        blocks.append(
            "\n".join(
                [
                    "# HELP ai_usage_up Whether fetching AI usage metrics for this account succeeded (1) or failed (0).",
                    "# TYPE ai_usage_up gauge",
                    *up_lines,
                ]
            )
        )
    blocks.append(
        "\n".join(
            [
                "# HELP ai_usage_collector_last_run_seconds Unix timestamp of the last AI usage collector run.",
                "# TYPE ai_usage_collector_last_run_seconds gauge",
                f"ai_usage_collector_last_run_seconds {fmt_ts(last_run_seconds)}",
            ]
        )
    )
    return "\n".join(blocks) + "\n"


def write_atomic(output_path: Path, content: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = output_path.parent / f"{output_path.name}.tmp"
    with tmp_path.open("w", encoding="utf-8") as fh:
        fh.write(content)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp_path, output_path)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Export AI subscription usage to node_exporter textfile.")
    parser.add_argument("--gateway-url", default=DEFAULT_GATEWAY_URL)
    parser.add_argument("--keychain-service", default=DEFAULT_KEYCHAIN_SERVICE)
    parser.add_argument("--keychain-account", default=DEFAULT_KEYCHAIN_ACCOUNT)
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--codex-sessions-dir", default=DEFAULT_CODEX_SESSIONS)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--max-runtime", type=float, default=50.0)
    parser.add_argument("--dry-run", action="store_true", help="Print metrics to stdout instead of writing output file.")
    args = parser.parse_args(argv)

    deadline = time.monotonic() + max(5.0, args.max_runtime)
    accounts: List[Dict[str, Any]] = []

    mgmt_key = read_keychain_secret(args.keychain_service, args.keychain_account)
    if mgmt_key is not None:
        accounts.extend(collect_claude(args.gateway_url, mgmt_key, args.timeout, deadline))

    codex_dir = Path(args.codex_sessions_dir).expanduser()
    accounts.append(collect_codex(codex_dir))

    text = render_prometheus(accounts, time.time())
    if args.dry_run:
        sys.stdout.write(text)
    else:
        output_path = Path(args.output).expanduser()
        write_atomic(output_path, text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
