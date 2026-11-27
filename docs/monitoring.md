# Monitoring exporters

Prometheus runs in a container inside **garage-server**'s Podman VM and scrapes
host metrics from both always-on Macs without opening any network port.
**garage** (the laptop) runs neither agent.

## LaunchAgents

- **`org.nix-community.home.node-exporter`** (`nixpkgs/home-manager/node-exporter.nix`,
  imported by `garage-server` and `garage-hq`): runs `prometheus-node-exporter`
  bound to `127.0.0.1:9100` (loopback only, never `0.0.0.0`), with the default
  unprivileged Darwin collectors and the textfile collector enabled on
  `~/.local/state/node-exporter/textfile` (created at activation before launchd
  starts the agent; custom `.prom` files such as AI-usage metrics can be dropped
  there). Kept alive by launchd (30 s restart throttle).
  Log: `~/Library/Logs/node-exporter.log`.
- **`org.nix-community.home.mac-temp-exporter`** (also in `node-exporter.nix`,
  both Macs): every 30 s writes `mac_cpu_temp_celsius` (hottest `PMU tdie*`
  CPU die sensor, read through the IOHIDEventSystem API like Stats does, no
  root) to `mac_temp.prom` in the textfile directory, because node_exporter's
  thermal collector can't read Apple silicon temperatures.
  Log: `~/Library/Logs/mac-temp-exporter.log`.
- **`org.nix-community.home.podman-exporter`** (`nixpkgs/home-manager/podman-exporter.nix`
  and `.py`, `garage-server` only): every 60 s runs `podman ps -a` and
  `podman stats --no-stream` against the local Podman VM and writes
  `podman_up` (0 when the VM is unreachable), `podman_containers{state}`, and
  per container (`name` label) `podman_container_info{name,state,image}`,
  `podman_container_started_seconds`, `podman_container_cpu_seconds_total`
  (rate it for CPU use), `podman_container_memory_bytes` and
  `podman_container_pids` to `podman.prom` in the textfile directory.
  Log: `~/Library/Logs/podman-exporter.log`.
- **`org.nix-community.home.network-probe`** (`nixpkgs/home-manager/network-probe.nix`
  and `.py`, `garage-server` only): every 30 s runs four parallel probes —
  `router` (ping the `en0` default gateway via `route -n get -ifscope en0 default`),
  `internet` (ping `1.1.1.1` then `8.8.8.8`, bypassing WARP), `dns` (`dig` against
  that gateway's DNS forwarder), and `https` (`curl` to
  `www.google.com/generate_204` over the normal system path) — and writes
  `network_probe_success{probe}`, `network_probe_duration_seconds{probe}` (ping
  RTT for `router`/`internet`, wall time for `dns`/`https`; emitted only on
  success), and `network_probe_last_run_seconds` to `network.prom` in the
  textfile directory. The gateway lookup and pings bind to `en0` (never a WARP
  `utun`), and pings use `-c 3 -o -t 2` to retry on single-packet loss while
  exiting on the first reply. Runs on `garage-server` because it is always on
  and scraped locally by Prometheus, so samples survive an internet outage. It
  reaches the Deco over Wi-Fi (`en0`), so a failed `router` probe can also mean
  its own Wi-Fi dropped; `dns` can still pass for up to the record's TTL from
  the Deco's cache, making `internet` the primary outage signal.
  Log: `~/Library/Logs/network-probe.log`.
- **`org.nix-community.home.node-exporter-tunnel`**
  (`nixpkgs/home-manager/node-exporter-tunnel.nix`, imported by `garage-hq`
  only): runs Apple's
  `/usr/bin/ssh -N -T -R 127.0.0.1:9102:127.0.0.1:9100 garage-server` so
  `garage-hq`'s exporter is exposed on `garage-server`'s `127.0.0.1:9102` only.
  Uses the `garage-server` SSH alias (which points at the Thunderbolt bridge,
  `10.0.99.1`, never the network), with `BatchMode=yes`,
  `StrictHostKeyChecking=yes`, `ExitOnForwardFailure=yes`, `ConnectTimeout=10`,
  15 s keepalives (`ServerAliveInterval=15`, `ServerAliveCountMax=3`) and no
  connection sharing (`ControlMaster=no`, `ControlPath=none`); launchd restarts
  it at most every 30 s.
  Log: `~/Library/Logs/node-exporter-tunnel.log`.

## Token usage (`garage-hq` only)

`org.nix-community.home.token-usage-exporter` (`nixpkgs/home-manager/token-usage-exporter.{nix,py}`)
runs every 60 s and counts tokens appended to `~/.claude/projects/**/*.jsonl`
(Claude Code: `message.usage` per reply, deduplicated by `message.id`) and
`~/.codex/sessions/**/*.jsonl` (Codex: `last_token_usage` of each
`token_count` event, repeats with an unchanged `total_token_usage` skipped,
model from `turn_context`) since its last run, using a byte offset per file in
`~/.local/state/token-usage-exporter/state.json`. It writes the running totals
as `ai_tokens_total{client="claude-code|codex|agy|hermes",model,type="input|output|cache_read|cache_write"}`
(a counter; graph it with `increase()`) to `ai_tokens.prom` in the textfile
directory. On the first run every file starts at its end; later, files born
since the last scan are read from the start, skipping Claude records older than
the file (resumed and forked sessions copy earlier messages with the same ids).
agy (Antigravity) generations come from new `gen_metadata` rows in
`~/.gemini/antigravity-cli/conversations/*.db` (read-only SQLite, last row per
database kept in the state); their usage block was inferred from agy 1.5.14
to follow Codeium's ModelUsageStats layout (input, output, cache write, cache
read; missing counts are 0). agy history before 2026-11-24 16:10 was loaded
once into Prometheus by joining each generation to its step's timestamp.
Hermes (`client="hermes"`) reads `session_model_usage` in `~/.hermes/state.db`
(read-only SQLite, WAL mode) and tracks per-row running counters
(`input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`) in
the state file keyed by the table's primary key; each run adds the per-counter
delta (or the full value if a row is new or its counter dropped) and drops rows
pruned by Hermes without reducing totals. The first time Hermes is seen it
records the current rows as a baseline and adds nothing (no backfill).
If the state file is lost, counting restarts (a counter reset, which
`increase()` handles). History before 2026-11-24 was loaded once into
Prometheus as `instance="backfill"` series. Log: `~/Library/Logs/token-usage-exporter.log`.

## Scraping from the Podman VM

Containers in `garage-server`'s Podman VM reach the host loopback listeners via
`host.containers.internal`:

| Host | Target from Podman VM | Backing listener |
|---|---|---|
| `garage-server` | `host.containers.internal:9100` | local `node_exporter` (`127.0.0.1:9100`) |
| `garage-hq` | `host.containers.internal:9102` | SSH reverse forward from `garage-hq` (`127.0.0.1:9100`) over Thunderbolt |

While `garage-hq`'s exporter is down, `garage-server:9102` still accepts
connections (the tunnel log shows `connect_to 127.0.0.1 port 9100: failed`), so
a down `garage-hq` target can mean either the tunnel or the exporter. Every
container in the shared VM can read these ports, so put nothing sensitive in the
textfile directory.

## AI usage collector (`garage-hq` only)

- **`org.nix-community.home.ai-usage-exporter`**
  (`nixpkgs/home-manager/ai-usage-exporter.nix`, `ai-usage-exporter.py`,
  imported by `garage-hq` only): runs every 5 minutes (`StartInterval = 300`,
  `RunAtLoad = true`) and atomically writes
  `~/.local/state/node-exporter/textfile/ai_usage.prom` (via `ai_usage.prom.tmp`
  then rename) for `node_exporter`'s textfile collector.
  Log: `~/Library/Logs/ai-usage-exporter.log` (never logs keys, tokens, or full
  email addresses).
- **Sources:**
  - **Claude:** queries the local CLIProxyAPI management API on
    `http://127.0.0.1:8317` (`GET /v0/management/auth-files`, filtering enabled
    `type == "claude"` entries, then `POST /v0/management/api-call` to
    `https://api.anthropic.com/api/oauth/usage` with `$TOKEN$` substitution so
    the script never sees OAuth tokens). Maps `limits` entries (`session` → `5h`,
    `weekly_all` → `7d`, `weekly_scoped` → `7d_<model display_name lowercased>`),
    falling back to `five_hour`/`seven_day` when `limits` is absent. Each
    account is fetched independently with a 10 s HTTP timeout (no proxy, no
    redirects). If the management key is missing/invalid or the account listing
    fails, emits `ai_usage_up{provider="claude",account="gateway"} 0`.
  - **Codex:** asks OpenAI live (`chatgpt.com/backend-api/wham/usage`, the
    undocumented endpoint Codex's `/status` uses) with Codex's own access
    token from `~/.codex/auth.json` (Codex refreshes it when it runs; the
    refresh token is never used); windows by `limit_window_seconds`
    (`18000` → `5h`, `604800` → `7d`). If that fails, falls back to the logs:
    reads the newest `~/.codex/sessions/**/*.jsonl` by mtime and
    extracts the last line with a non-null `payload.rate_limits` (`300` → `5h`,
    `10080` → `7d`, else `<n>m`; observed time from the line's `timestamp` or
    the file mtime; account label `codex`).
  - **Antigravity (agy):** reads agy's own login from the Keychain (service
    `gemini`, a go-keyring item agy writes) and uses only its short-lived
    access token; when that expires within a minute it runs `agy models`
    (at most every 10 minutes, killed after 60 s) so agy refreshes its own
    login (the refresh token is never used). Calls
    Google's undocumented `daily-cloudcode-pa.googleapis.com/v1internal:`
    `loadCodeAssist` (for the project id) and `fetchAvailableModels`, whose
    per-model `quotaInfo` (`remainingFraction`, `resetTime`) is reduced to one
    row, account `gemini` (the most-used Gemini model; Gemini models share one
    pool, assumed to include Gemini 4 Neon, which the list doesn't name). agy's
    Claude/GPT-OSS pool and internal models are ignored by choice, and a model
    with only `resetTime` counts as exhausted. Window label `5h` (Google resets each pool about every 5 hours on
    the Ultra plan, observed 2026-11-24). Breaks if agy changes its login
    storage or Google changes that internal API; then `ai_usage_up{provider="agy"} 0`.
- **Metrics:**
  - `ai_usage_utilization_percent{provider="claude|codex|agy",account="<label>",window="5h|7d|7d_fable|..."}` (`gauge`, 0–100; Claude `account` is the email local part only, never the domain)
  - `ai_usage_resets_at_seconds{provider,account,window}` (`gauge`, unix seconds)
  - `ai_usage_observed_at_seconds{provider,account}` (`gauge`, unix seconds)
  - `ai_usage_up{provider,account}` (`gauge`, `1` on fetch success, `0` on failure)
  - `ai_usage_collector_last_run_seconds` (`gauge`, unix seconds of the run)
- **Secret setup:** `pass` entry `ai/cliproxyapi-management-secret` (first line)
  is synced into the login Keychain as service `ai-usage-exporter`, account
  `cliproxy-management-secret` on every rebuild via `ai-usage-keychain-sync`
  (passing the value to `security -i` on stdin, hex-encoded, with
  `-T /usr/bin/security`, following `hermes.nix`). Rebuild from the console
  session, or run `ai-usage-keychain-sync` at the console after rebuilding over
  SSH (when the Keychain refuses writes). Manual one-time fallback at the
  console if needed:
  ```sh
  security add-generic-password -U -s ai-usage-exporter -a cliproxy-management-secret -T /usr/bin/security -w
  ```
  Run `ai-usage-exporter --dry-run` to preview the generated `.prom` output on
  stdout without writing the textfile.
