# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## System Setup & Installation

This is a Nix-based dotfiles repository for macOS (Darwin) systems using nix-darwin and home-manager.

### Initial Setup
```bash
# Install Nix and configure the system
./init.sh
```

### System Rebuild
```bash
# Rebuild the system configuration
nix run nix-darwin -- switch --flake $(pwd)/nixpkgs

# Or rebuild a specific host: garage (main Mac), garage-server or garage-hq
darwin-rebuild switch --flake .#garage
```

## Architecture Overview

This dotfiles repository uses a modular Nix flake configuration to manage:

- **System packages and settings** via nix-darwin (`nixpkgs/nix-darwin/`)
- **User environment and applications** via home-manager (`nixpkgs/home-manager/`)
- **Terminal environment** via WezTerm + Neovim + Zsh

### Key Configuration Modules

- `flake.nix` - Main flake configuration: the shared (global) module list in `mkHost`, plus the hosts "garage", "garage-server" and "garage-hq"
- `nixpkgs/hosts/<host>.nix` - Per-device layer, added on top of the global one: the host's computerName and its own Homebrew casks/brews (`garage.nix`: main Mac, also the only one with Raycast and JankyBorders; `garage-server.nix`: server Mac, a gateway client that never sleeps and runs without the desktop extras; `garage-hq.nix`: Mac Studio, the AI hub, see `docs/ai-setup.md`, and a server without the desktop extras, trialling the `herdr` multiplexer alongside tmux). Homebrew lists merge, so a host module only lists its extras. To add a device type, add a file here and its name to `darwinConfigurations` in `flake.nix`
- `nixpkgs/nix-darwin/desktop-extras.nix` - The `dotfiles.desktopExtras` flag (default on; `garage-hq.nix` and `garage-server.nix` turn it off). Off leaves out Vorssaint (cask, login item, `vorssaint.nix`), Hammerspoon (cask, login item, updater settings, `hammerspoon.nix` with `space` and the init.lua link), WezTerm (cask and config link), desktoppr and the wallpaper, sf-symbols, `hotkeys.nix`, Obsidian, LibreOffice, Upscayl and TablePlus. Each item stays in its own file behind the flag; zsh, tmux, sesh and the Tailscale SSH terminfo are kept
- `nixpkgs/nix-darwin/configuration.nix` - System-level packages and the Homebrew brews/casks every machine gets
- `nixpkgs/nix-darwin/macos.nix` - macOS settings (defaults, Dock, keyboard, trackpad, firewall, power; the host names come from `flake.nix` and `nixpkgs/hosts/`) and Hammerspoon's updater settings, captured from the live machine
- `nixpkgs/nix-darwin/vorssaint.nix` - Vorssaint menu bar app settings, captured from the live app
- `nixpkgs/nix-darwin/hotkeys.nix` - System keyboard shortcuts, captured from the live machine, plus ⌃1…⌃9 and ⌃⌥⌘1…7 to switch to Desktop 1–16
- `nixpkgs/nix-darwin/ai-hub.nix` - The AI hub role, imported by a host file: the CLIProxyAPI gateway for every Mac and `never-sleep.nix` (the Mac never sleeps). Headroom (`nixpkgs/home-manager/ai/headroom.nix`) is a separate import in the host file
- `nixpkgs/nix-darwin/jankyborders.nix` - JankyBorders, a border around the focused window (imported by `garage.nix` only)
- `nixpkgs/home-manager/home.nix` - User packages, dotfile linking, services
- `nixpkgs/home-manager/desktop.nix` - Login items (`dotfiles.desktop.loginApps`: the shared ones here, host-only ones in `nixpkgs/hosts/<host>.nix`) and default browser/mail/PDF handlers (`dotfiles.desktop.browser` is Safari unless the host sets it; garage uses Chrome)
- `nixpkgs/home-manager/raycast.nix` - Raycast's login item and one-shot settings import (imported by `garage.nix` only)
- `nixpkgs/home-manager/hammerspoon.nix` - Hammerspoon config link and the `space` CLI
- `nixpkgs/home-manager/herdr.nix` - herdr config and agent-popup script links (imported by `garage-hq.nix` only)
- `nixpkgs/home-manager/ai-usage-exporter.nix` - Periodic (5 min) collector writing Claude (CLIProxyAPI) and Codex quota metrics to `~/.local/state/node-exporter/textfile/ai_usage.prom`, with `ai-usage-keychain-sync` for the management key (imported by `garage-hq.nix` only; see `docs/monitoring.md`)
- `nixpkgs/home-manager/token-usage-exporter.nix` - Every 60 s counts Claude Code, Codex and agy tokens from their local session logs into `ai_tokens_total` in node_exporter's textfile directory (imported by `garage-hq.nix` only; see `docs/monitoring.md`)
- `nixpkgs/home-manager/node-exporter.nix` - Prometheus `node_exporter` on `127.0.0.1:9100` with textfile collector in `~/.local/state/node-exporter/textfile` (imported by `garage-server.nix` and `garage-hq.nix`, not `garage.nix`; see `docs/monitoring.md`)
- `nixpkgs/home-manager/podman-exporter.nix` - Container counts and per-container state, uptime, CPU time and memory from garage-server's Podman VM (`podman_*`, script `podman-exporter.py`) into node_exporter's textfile directory every 60 s (imported by `garage-server.nix` only; see `docs/monitoring.md`)
- `nixpkgs/home-manager/network-probe.nix` - LAN router, 5G internet, router DNS and HTTPS reachability probes (`network_probe_*`, script `network-probe.py`) into node_exporter's textfile directory every 30 s (imported by `garage-server.nix` only; see `docs/monitoring.md`)
- `nixpkgs/home-manager/node-exporter-tunnel.nix` - SSH reverse forward from garage-hq's `127.0.0.1:9100` to garage-server's `127.0.0.1:9102` through the `garage-server` alias, Thunderbolt bridge only (imported by `garage-hq.nix` only; see `docs/monitoring.md`)
- `nixpkgs/home-manager/rpa-tunnel.nix` - SSH forward `127.0.0.1:18080` → garage-server's RPA/Steel app (`127.0.0.1:8080`) through the `garage-server` alias, Thunderbolt bridge only, never the network (imported by `garage-hq.nix` only); agents on garage-hq use `http://localhost:18080`, humans the tailnet URL
- `nixpkgs/home-manager/node-globals.nix` - Global npm tools installed into nvm's default Node
- Individual service configs: `git.nix`, `zsh.nix`, `tmux.nix`, `starship.nix`, etc.

### Where installs go

- Homebrew formulas and casks for every Mac: `nixpkgs/nix-darwin/configuration.nix`; for one Mac: `nixpkgs/hosts/<host>.nix` (lists merge)
- Global CLI tools: `home.packages` in `nixpkgs/home-manager/home.nix` (nixpkgs); global npm tools in `nixpkgs/home-manager/node-globals.nix`
- Launch agents: a home-manager module with `launchd.agents` (e.g. `rpa-tunnel.nix`). nix-darwin daemons (`launchd.daemons`, like `never-sleep.nix`) are rare
- Wiring a home-manager module: shared modules go in `users.ksotis.imports` in `mkHost` in `flake.nix`; host-only modules go in that host file's `home-manager.users.ksotis.imports`. A module that isn't imported does nothing

### Dotfile Symlinks

Configuration files are symlinked from this repo to `~/.config/` via home-manager:
- `nvim/` → `~/.config/nvim/`
- `wezterm.lua` → `~/.config/wezterm/wezterm.lua`
- `sesh.toml` → `~/.config/sesh/sesh.toml`
- `hammerspoon/init.lua` → `~/.hammerspoon/init.lua`, linked to the checkout at `~/studio/personal/dotfiles`; Hammerspoon reloads it on save
- `herdr/config.toml` and `herdr/agent.sh` → `~/.config/herdr/config.toml` and `~/.config/herdr/scripts/agent.sh` (garage-hq only, `nixpkgs/home-manager/herdr.nix`), linked to the checkout so herdr's settings screen can write the config; `prefix+r` reloads it. The keybindings are ported from `tmux.nix`, without sesh and session management
- `raycast/settings.rayconfig` → imported once on garage on the first rebuild after Raycast has been opened (see `raycast/README.md`)

AI tooling (`nixpkgs/home-manager/ai/`, guide in `docs/ai-setup.md`):
- `claude/` → `~/.claude/` (CLAUDE.md, onboarding.md, agents, hooks, own skills), linked to the checkout at `~/studio/personal/dotfiles` so edits land in the repo
- `claude/hooks/`: `global-manager-intro.sh` (SessionStart: points sessions at the claude-config manager), `block-pattern-kill.py` (PreToolUse: refuses pattern kills), `herdr-agent-record.sh` (SessionStart/SessionEnd: records the conversation in each herdr terminal for `agents-resurrect`, see `docs/ai-setup.md`)
- `claude/settings.base.json` and `codex/config.base.toml` are merged into the live `~/.claude/settings.json` / `~/.codex/config.toml` at activation (those stay real files)
- Open Design, the local LLM tunnel and Auto Browser (workstation services) were retired on 2026-11-20 in favour of the `agent-browser` CLI
- All install and merge logic lives here; the private repo `~/studio/personal/dotfiles-private` only sets `dotfiles.ai.*` options (project paths, internal URLs) through the `private` flake input. Secrets come from `pass`. Rebuild with `rebuild`

## Development Environment

### Primary Tools
- **Terminal**: WezTerm with Catppuccin theme
- **Shell**: Zsh with Starship prompt and oh-my-zsh
- **Editor**: Neovim with LazyVim configuration
- **Git**: Configured via `nixpkgs/home-manager/git.nix`
- **Session Manager**: Sesh for tmux session management
- **File Manager**: lf (terminal), Finder (GUI)

### Container & Kubernetes Tools
- Podman CLI (and `docker` wrapping it), the client for garage-server's Podman VM (connection `arm64`)
- kubectl, kubectx, k9s, minikube
- Custom kubectl-forward script from GitHub

### Programming Languages & Runtimes
- **Node.js**: Managed via Bun and nvm (homebrew)
- **Python**: Python3 with pipx and uv
- **Go**: Enabled via home-manager
- **Ruby**: cocoapods and bundler

## System Services

### Window Focus (no tiling)
Hammerspoon (`hammerspoon/init.lua`) moves focus and windows; JankyBorders marks the focused window on garage:
- ⌃⌥h/j/k/l: focus the nearest window west/south/north/east on the current Space
- The mouse follows focus to the window centre unless already inside, a mouse button is held, a throw is running, Mission Control is open, or the window is non-standard or has no frame; successful throws also centre the mouse
- ⌥⇧1…9: throw the focused window to Desktop N on the same display and follow it. It holds the title bar just right of the zoom button and presses the "Switch to Desktop" shortcut, so windows without one and full-screen windows can't be thrown. WezTerm shows a tab bar with the traffic lights for this. ⌥⇧1…9 no longer types ⁄ € ‹ › ﬁ ﬂ ‡ ° ·
- Displays have separate Spaces, but macOS numbers Desktops across all displays, so Desktop N of a later display is a higher number K. Hammerspoon counts Desktops (type 0) in `hs.spaces.data_managedDisplaySpaces()` order and sends K's shortcut: ⌃1…9 for 1–9, ⌃⌥⌘1…7 for 10–16 (not meant to be pressed by hand; the table in init.lua must match hotkeys.nix). It alerts if the display has no Desktop N or K is above 16; a 10–16 shortcut that isn't active yet (no logout since the rebuild) does nothing
- Unverified until tested on two displays with a full-screen app open: that the global numbering skips full-screen spaces, and that it follows `data_managedDisplaySpaces()` display order. To check, throw with ⌥⇧1/⌥⇧2 on each display; if a window lands on the wrong Desktop, compare `hs.inspect(hs.spaces.data_managedDisplaySpaces())` in the Hammerspoon console with the Desktop order in Mission Control
- `space N`: switch to Desktop N of the focused window's display (or the one under the mouse) from a terminal, via `hammerspoon://space?n=N`
- Hammerspoon needs Accessibility permission, granted by hand in System Settings → Privacy & Security → Accessibility. Desktop N must exist (add it in Mission Control). Log out once if ⌃1…9 or ⌃⌥⌘1…7 doesn't switch Desktops after a rebuild
- Throw cases to test first after a change: Chrome with many tabs, and WezTerm, on each display. If a throw is refused ("No title bar to grab"), print the Accessibility roles at the grab point in the Hammerspoon console (`p` = the point just right of the zoom button): `local p=…; local e=hs.axuielement.systemElementAtPosition(p); while e do print(e:attributeValue("AXRole")); e=e:attributeValue("AXParent") end`

### macOS System Defaults
Comprehensive macOS customization in `nixpkgs/nix-darwin/macos.nix`:
- Dock: autohide, small tiles, no recents
- Keyboard: fast repeat, caps→ctrl
- Trackpad: tap-to-click, right-click, three-finger drag
- Finder: show extensions, path bar, hidden files
- Global: dark mode, no autocorrect

## Troubleshooting

### Permission Issues
Some GUI applications may need manual permission grants after installation.

### Homebrew vs Nix Conflicts  
System uses both Nix packages and Homebrew casks. Check `configuration.nix` and `nixpkgs/hosts/` for the current split.
