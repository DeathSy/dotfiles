#!/usr/bin/env python3
"""Probe LAN router, internet link, router DNS, and HTTPS into a node_exporter textfile.

Usage: network-probe [--dry-run] [<output.prom>]
Metrics: network_probe_success{probe}, network_probe_duration_seconds{probe},
network_probe_last_run_seconds (probes: router, internet, dns, https).
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import subprocess
import sys
import time

PING = "/sbin/ping"
ROUTE = "/sbin/route"
DIG = "/usr/bin/dig"
CURL = "/usr/bin/curl"

PROBES = ("router", "internet", "dns", "https")
INTERNET_TARGETS = ("1.1.1.1", "8.8.8.8")
DNS_QUERY_HOST = "www.google.com"
HTTPS_URL = "https://www.google.com/generate_204"


def log(msg):
    sys.stderr.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} network-probe: {msg}\n")


def first_line(text):
    lines = (text or "").strip().splitlines()
    return lines[0][:160] if lines else ""


def get_default_route():
    """Return (gateway, interface, error) from `/sbin/route -n get default`."""
    try:
        res = subprocess.run(
            [ROUTE, "-n", "get", "default"],
            capture_output=True, text=True, timeout=2,
        )
    except Exception as exc:
        return None, None, f"route lookup failed ({type(exc).__name__})"
    if res.returncode != 0:
        detail = first_line(res.stderr or res.stdout)
        return None, None, f"route lookup rc={res.returncode}" + (f": {detail}" if detail else "")
    gateway = interface = None
    for line in res.stdout.splitlines():
        if ":" not in line:
            continue
        key, val = (part.strip() for part in line.split(":", 1))
        if key == "gateway" and val:
            gateway = val
        elif key == "interface" and val:
            interface = val
    if not gateway or not interface:
        return gateway, interface, f"route missing gateway={gateway!r} interface={interface!r}"
    return gateway, interface, None


def run_ping(interface, target):
    t0 = time.monotonic()
    try:
        res = subprocess.run(
            [PING, "-c", "1", "-t", "2", "-b", interface, target],
            capture_output=True, text=True, timeout=3,
        )
        dur = time.monotonic() - t0
    except Exception as exc:
        return False, time.monotonic() - t0, f"ping {target} ({type(exc).__name__})"
    if res.returncode == 0:
        return True, dur, None
    detail = first_line(res.stderr)
    return False, dur, f"ping {target} rc={res.returncode}" + (f": {detail}" if detail else "")


def probe_router(gateway, interface):
    if not gateway or not interface:
        return False, 0.0, "no default gateway/interface"
    return run_ping(interface, gateway)


def probe_internet(interface):
    if not interface:
        return False, 0.0, "no default interface"
    t_total = time.monotonic()
    errors = []
    for target in INTERNET_TARGETS:
        ok, dur, err = run_ping(interface, target)
        if ok:
            return True, dur, None
        errors.append(err)
    return False, time.monotonic() - t_total, "; ".join(errors)


def probe_dns(gateway):
    if not gateway:
        return False, 0.0, "no default gateway"
    t0 = time.monotonic()
    try:
        res = subprocess.run(
            [DIG, f"@{gateway}", "+time=2", "+tries=1", DNS_QUERY_HOST, "A"],
            capture_output=True, text=True, timeout=3,
        )
        dur = time.monotonic() - t0
    except Exception as exc:
        return False, time.monotonic() - t0, f"dig @{gateway} ({type(exc).__name__})"
    if res.returncode != 0:
        detail = first_line(res.stderr or res.stdout)
        return False, dur, f"dig @{gateway} rc={res.returncode}" + (f": {detail}" if detail else "")
    status_match = re.search(r"\bstatus:\s*([A-Z0-9]+)\b", res.stdout)
    answer_match = re.search(r"\bANSWER:\s*(\d+)\b", res.stdout)
    status = status_match.group(1) if status_match else "UNKNOWN"
    answers = int(answer_match.group(1)) if answer_match else 0
    if status == "NOERROR" and answers >= 1:
        return True, dur, None
    return False, dur, f"dig @{gateway} status={status} answers={answers}"


def probe_https():
    t0 = time.monotonic()
    try:
        res = subprocess.run(
            [CURL, "-sS", "-o", "/dev/null", "-m", "5", "-w", "%{http_code}", HTTPS_URL],
            capture_output=True, text=True, timeout=6,
        )
        dur = time.monotonic() - t0
    except Exception as exc:
        return False, time.monotonic() - t0, f"curl ({type(exc).__name__})"
    code = res.stdout.strip()
    if res.returncode == 0 and code == "204":
        return True, dur, None
    detail = first_line(res.stderr)
    return False, dur, f"curl rc={res.returncode} http={code or 'none'}" + (f": {detail}" if detail else "")


def safe_run(fn, *args):
    t0 = time.monotonic()
    try:
        return fn(*args)
    except Exception as exc:
        return False, time.monotonic() - t0, f"unexpected error ({type(exc).__name__})"


def render(results, last_run):
    success_lines = [
        f'network_probe_success{{probe="{name}"}} {1 if results[name][0] else 0}'
        for name in PROBES
    ]
    duration_lines = [
        f'network_probe_duration_seconds{{probe="{name}"}} {results[name][1]:.4f}'
        for name in PROBES
    ]
    families = [
        ("network_probe_success", "Whether the network probe succeeded (1) or failed (0).", success_lines),
        ("network_probe_duration_seconds", "Wall-clock duration of the network probe in seconds.", duration_lines),
        ("network_probe_last_run_seconds", "Unix timestamp of the last network probe run.",
         [f"network_probe_last_run_seconds {int(last_run)}"]),
    ]
    out = []
    for name, help_text, samples in families:
        out += [f"# HELP {name} {help_text}", f"# TYPE {name} gauge", *samples]
    return "\n".join(out) + "\n"


def write_atomic(output_path, content):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = output_path.parent / f"{output_path.name}.tmp"
    with tmp_path.open("w", encoding="utf-8") as fh:
        fh.write(content)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp_path, output_path)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Export LAN/WAN/DNS/HTTPS probe metrics to node_exporter textfile.")
    parser.add_argument("output", nargs="?", help="Destination .prom file path (required unless --dry-run).")
    parser.add_argument("--dry-run", action="store_true", help="Print Prometheus metrics to stdout instead of writing.")
    args = parser.parse_args(argv)
    if not args.dry_run and not args.output:
        parser.error("output path is required unless --dry-run is set")

    gateway, interface, route_err = get_default_route()
    if route_err:
        log(route_err)

    tasks = {
        "router": (probe_router, gateway, interface),
        "internet": (probe_internet, interface),
        "dns": (probe_dns, gateway),
        "https": (probe_https,),
    }
    results = {}
    with ThreadPoolExecutor(max_workers=len(PROBES)) as pool:
        futures = {name: pool.submit(safe_run, *spec) for name, spec in tasks.items()}
        for name in PROBES:
            ok, dur, err = futures[name].result()
            results[name] = (ok, dur)
            if not ok:
                log(f"{name} failed: {err}")

    text = render(results, time.time())
    if args.dry_run:
        sys.stdout.write(text)
    else:
        write_atomic(Path(args.output).expanduser(), text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
