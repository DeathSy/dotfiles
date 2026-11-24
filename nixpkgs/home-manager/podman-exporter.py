#!/usr/bin/env python3
"""Write per-container metrics from the local Podman VM to a node_exporter textfile.

Usage: podman-exporter <podman binary> <output.prom>
Metrics: podman_up, podman_containers{state}, and per container (label name):
podman_container_info{name,state,image}, podman_container_started_seconds,
podman_container_cpu_seconds_total (rate() it for CPU use), podman_container_memory_bytes,
podman_container_pids.
"""

import json
import os
import subprocess
import sys


def run(podman, *args):
    return subprocess.run([podman, *args], capture_output=True, text=True, timeout=30, check=True).stdout


def esc(value):
    return str(value).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def labels(**kv):
    return "{" + ",".join(f'{k}="{esc(v)}"' for k, v in kv.items()) + "}"


def failure(what, exc):
    detail = ""
    if isinstance(exc, subprocess.CalledProcessError):
        first = (exc.stderr or "").strip().splitlines()[:1]
        detail = f" rc={exc.returncode}" + (f": {first[0][:200]}" if first else "")
    print(f"podman-exporter: {what} failed ({type(exc).__name__}{detail})", file=sys.stderr)


def collect(podman):
    # Pod infra containers are podman plumbing, not workloads.
    containers = [c for c in (json.loads(run(podman, "ps", "-a", "--format", "json") or "[]") or [])
                  if not c.get("IsInfra")]
    stats = {}
    if any(c.get("State") == "running" for c in containers):
        fmt = "{{.Name}}|{{.ContainerStats.CPUNano}}|{{.ContainerStats.MemUsage}}|{{.ContainerStats.PIDs}}"
        try:
            lines = run(podman, "stats", "--no-stream", "--format", fmt).splitlines()
        except Exception as exc:  # the VM answered ps; keep the container list without stats
            failure("podman stats", exc)
            lines = []
        for line in lines:
            try:
                name, cpu_ns, mem, pids = line.split("|")
                stats[name] = (int(cpu_ns) / 1e9, int(mem), int(pids))
            except ValueError:
                continue
    return containers, stats


def render(containers, stats, up):
    counts = {"running": 0, "exited": 0, "other": 0}
    info, started, cpu, mem, pids = [], [], [], [], []
    for c in containers:
        name = (c.get("Names") or [c.get("Id") or "unknown"])[0]
        state = c.get("State") or "unknown"
        counts[state if state in counts else "other"] += 1
        info.append(f"podman_container_info{labels(name=name, state=state, image=c.get('Image') or '')} 1")
        if state == "running" and (c.get("StartedAt") or 0) > 0:
            started.append(f"podman_container_started_seconds{labels(name=name)} {int(c['StartedAt'])}")
        if name in stats:
            cpu_s, mem_b, n = stats[name]
            cpu.append(f"podman_container_cpu_seconds_total{labels(name=name)} {cpu_s:.3f}")
            mem.append(f"podman_container_memory_bytes{labels(name=name)} {mem_b}")
            pids.append(f"podman_container_pids{labels(name=name)} {n}")
    families = [
        ("podman_up", "gauge", "1 if the Podman VM answered.", [f"podman_up {up}"]),
        ("podman_containers", "gauge", "Containers by state.",
         [f"podman_containers{labels(state=s)} {n}" for s, n in counts.items()] if up else []),
        ("podman_container_info", "gauge", "One series per container.", info),
        ("podman_container_started_seconds", "gauge", "Start time of running containers.", started),
        ("podman_container_cpu_seconds_total", "counter", "CPU time used by the container.", cpu),
        ("podman_container_memory_bytes", "gauge", "Memory used by the container.", mem),
        ("podman_container_pids", "gauge", "Processes in the container.", pids),
    ]
    out = []
    for name, kind, help_text, samples in families:
        if samples:
            out += [f"# HELP {name} {help_text}", f"# TYPE {name} {kind}", *samples]
    return "\n".join(out) + "\n"


def main():
    podman, output = sys.argv[1], sys.argv[2]
    try:
        containers, stats = collect(podman)
        text = render(containers, stats, 1)
    except Exception as exc:
        failure("podman ps", exc)
        text = render([], {}, 0)
    tmp = f"{output}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, output)


if __name__ == "__main__":
    main()
