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


def collect(podman):
    containers = json.loads(run(podman, "ps", "-a", "--format", "json") or "[]")
    stats = {}
    if any(c.get("State") == "running" for c in containers):
        fmt = "{{.Name}}|{{.ContainerStats.CPUNano}}|{{.ContainerStats.MemUsage}}|{{.ContainerStats.PIDs}}"
        for line in run(podman, "stats", "--no-stream", "--format", fmt).splitlines():
            name, cpu_ns, mem, pids = line.split("|")
            stats[name] = (int(cpu_ns) / 1e9, int(mem), int(pids))
    return containers, stats


def render(containers, stats, up):
    counts = {"running": 0, "exited": 0, "other": 0}
    info, started, cpu, mem, pids = [], [], [], [], []
    for c in containers:
        name = (c.get("Names") or ["?"])[0]
        state = c.get("State") or "unknown"
        counts[state if state in counts else "other"] += 1
        info.append(f"podman_container_info{labels(name=name, state=state, image=c.get('Image') or '')} 1")
        if state == "running" and c.get("StartedAt"):
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
        print(f"podman-exporter: {type(exc).__name__}", file=sys.stderr)
        text = render([], {}, 0)
    tmp = f"{output}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, output)


if __name__ == "__main__":
    main()
