# AI setup

What the `nixpkgs/home-manager/ai/` modules manage, and the manual steps on a
new Mac.

## Layers

- **Public (this repo): everything that installs or runs.** Claude Code
  instructions, agents, hooks and own skills (`claude/`), generic Claude Code
  settings (`claude/settings.base.json`), generic Codex settings
  (`codex/config.base.toml`), the CLIProxyAPI config template
  (`cliproxyapi/config.yaml`), the merge and activation steps, the Headroom
  LaunchAgent and plugin build, Homebrew packages, and the `ai-bootstrap` and
  `ai-mcp-add` commands.
- **Private (`~/workspace/dotfiles-private`, a separate private repo): data
  only.** One home-manager module that sets the `dotfiles.ai.*` options
  (`nixpkgs/home-manager/ai/default.nix`, `gateway.nix`):
  `gateway.enable`, `claude.settingsOverlay` (gateway model id, internal
  plugin config), `claude.projectPlugins`, `mcp.projectServers`,
  `codex.trustedProjects`. All options default to empty, so the public repo
  works without it.
- **Secrets** stay in `pass` and are read at activation.

The flake's `private` input defaults to the empty `private-stub/`, so the
public repo evaluates on its own. `rebuild` (zsh function) overrides it with
the private checkout when it exists:

```sh
sudo darwin-rebuild switch --flake ~/workspace/dotfiles \
  --override-input private path:$HOME/workspace/dotfiles-private
```

## What a rebuild does

**Before the first rebuild, merge `ai-setup` into `main` and pull it into
`~/workspace/dotfiles`.** The `~/.claude` links point at that checkout. If
`claude/CLAUDE.md` isn't there, activation stops before touching `~/.claude`.

- Links `~/.claude/{CLAUDE.md,onboarding.md}`, `~/.claude/agents/*.md`,
  `~/.claude/hooks/*` and `~/.claude/skills/<own skill>/SKILL.md` to the files
  in the checkout at `~/workspace/dotfiles/claude/` (not the Nix store), so
  editing them in place edits the repo. Live files that were real files are
  moved to `~/.claude/backups/dotfiles-<timestamp>/` first, with a warning
  naming each one. That also happens when an editor that saves by renaming
  has replaced a link with a real file: diff the backup against the repo.
- Links `~/.claude/skills/agent-browser/SKILL.md` to the skill that ships with
  the Homebrew `agent-browser` CLI.
- Merges `~/.claude/settings.json`: live file ← `claude/settings.base.json` ←
  `dotfiles.ai.claude.settingsOverlay` ← secrets from `pass`. Keys from the repo win; anything else
  Claude Code wrote stays. The file is kept at mode 600 (it holds the token);
  the previous version is copied to
  `~/.claude/backups/settings.json.dotfiles-<timestamp>` (private, latest 5
  kept) when it changes. If
  `jq` or `pass` fails, the file is left alone with a warning. Run
  `claude-settings-merge` to redo it by hand. Removing a key from the base
  JSON does not remove it from the live file.
- Merges `~/.codex/config.toml` the same way (`codex/config.base.toml` ←
  `codex.settings` and `codex.trustedProjects`), backing up to `~/.codex/backups/`. `codex-config-sync`
  redoes it by hand.
- With `dotfiles.ai.gateway.enable`: points Claude Code at the local
  CLIProxyAPI (`ANTHROPIC_BASE_URL`, gateway model discovery, and
  `ANTHROPIC_AUTH_TOKEN` from `pass`), and writes
  `/opt/homebrew/etc/cliproxyapi.conf` from `cliproxyapi/config.yaml`, only if
  the file doesn't exist yet (CLIProxyAPI rewrites it itself). The template
  binds the proxy to `127.0.0.1`; an existing config keeps its own `host`.
- Installs `agent-browser`, `googleworkspace-cli` (`gws`) and `cliproxyapi`
  (started as a brew service) with Homebrew, and runs the Headroom proxy as
  the `ai.headroom.proxy` LaunchAgent. To drop Headroom, remove the
  `ai/headroom.nix` line from `flake.nix` (and the `plugins.configs.headroom`
  block from the CLIProxyAPI config).

`settings.json` keys the public layer manages: `$schema`, `env.*` (agent
teams, function hooks, timeouts, context and autocompact limits, telemetry
off, claude.ai MCP servers off), `permissions.deny`, `skillOverrides`,
`hooks`, `enabledPlugins`, `extraKnownMarketplaces`, `effortLevel`,
`modelSettings`, `tui`, `editorMode`, `skipDangerousModePermissionPrompt`,
`skipAutoPermissionPrompt`, `skipWorkflowUsageWarning`,
`agentPushNotifEnabled`.

With the gateway enabled it also manages `env.ANTHROPIC_BASE_URL`,
`env.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` and
`env.ANTHROPIC_AUTH_TOKEN`; the private overlay adds `model` and
`pluginConfigs`.

The `sol`, `luna` and `astra` agents use model ids that only resolve through
the CLIProxyAPI gateway.

## New machine

1. Run `./init.sh` from this repo (installs Nix, Homebrew, nix-darwin).
2. Restore GPG and `pass`: import the GPG key named in
   `nixpkgs/home-manager/password-store.nix`, then clone the password store to
   `~/.password-store`. Entries used:
   - `ai/cliproxyapi-key`: the CLIProxyAPI client key (also Claude Code's
     `ANTHROPIC_AUTH_TOKEN`)
   - `ai/cliproxyapi-management-secret`: the CLIProxyAPI management key
     (plain text; CLIProxyAPI hashes it on load)
   - `github/personal`: GitHub token (shadcn-ui MCP server, registry token)
3. Clone the private repo to `~/workspace/dotfiles-private`, open a new shell
   and run `rebuild`.
4. Log in:
   - `claude` (first run), and `codex login`
   - CLIProxyAPI OAuth accounts: `cliproxyapi --claude-login`,
     `cliproxyapi --codex-login` (and any other providers you use). The login
     files land in `~/.cli-proxy-api/*.json`; never commit them.
   - `gws auth login`. `gws` comes from the Homebrew `googleworkspace-cli`
     formula; if an older npm-global copy exists, remove it
     (`npm uninstall -g @googleworkspace/cli`) so the Homebrew one wins on
     `PATH`.
5. Run `ai-bootstrap`. It installs what Nix and Homebrew don't cover (the
   `claude` native installer, `graphify`, the Headroom server), skills from
   their sources (find-skills, frontend-design, graphify), Claude Code
   marketplaces and plugins, and MCP servers (`ai-mcp-add`: the user-scope
   ones plus `mcp.projectServers`; it never rewrites `~/.claude.json`). It skips anything already present and can be
   re-run.
6. Build the Headroom plugin for CLIProxyAPI: `cliproxyapi-headroom-build`,
   then `brew services restart cliproxyapi`.
7. Authenticate the HTTP MCP servers (figma, monday, and per-project ones)
   from `/mcp` inside Claude Code, and run `/slack` once to log in to the Slack
   plugin.
