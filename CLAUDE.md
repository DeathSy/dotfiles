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

# Or rebuild specifically for the "garage" configuration
darwin-rebuild switch --flake .#garage
```

## Architecture Overview

This dotfiles repository uses a modular Nix flake configuration to manage:

- **System packages and settings** via nix-darwin (`nixpkgs/nix-darwin/`)
- **User environment and applications** via home-manager (`nixpkgs/home-manager/`)
- **Terminal environment** via WezTerm + Neovim + Zsh

### Key Configuration Modules

- `flake.nix` - Main flake configuration defining the "garage" system
- `nixpkgs/nix-darwin/configuration.nix` - System-level packages, homebrew
- `nixpkgs/nix-darwin/macos.nix` - macOS settings (defaults, Dock, keyboard, trackpad, firewall, hostname, power) and Hammerspoon's updater settings, captured from the live machine
- `nixpkgs/nix-darwin/vorssaint.nix` - Vorssaint menu bar app settings, captured from the live app
- `nixpkgs/nix-darwin/hotkeys.nix` - System keyboard shortcuts, captured from the live machine, plus ⌃1…⌃9 and ⌃⌥⌘1…7 to switch to Desktop 1–16
- `nixpkgs/nix-darwin/jankyborders.nix` - JankyBorders, a border around the focused window
- `nixpkgs/home-manager/home.nix` - User packages, dotfile linking, services
- `nixpkgs/home-manager/desktop.nix` - Login items and default browser/PDF handlers
- `nixpkgs/home-manager/hammerspoon.nix` - Hammerspoon config link and the `space` CLI
- `nixpkgs/home-manager/node-globals.nix` - Global npm tools installed into nvm's default Node
- Individual service configs: `git.nix`, `zsh.nix`, `tmux.nix`, `starship.nix`, etc.

### Dotfile Symlinks

Configuration files are symlinked from this repo to `~/.config/` via home-manager:
- `nvim/` → `~/.config/nvim/`
- `wezterm.lua` → `~/.config/wezterm/wezterm.lua`
- `sesh.toml` → `~/.config/sesh/sesh.toml`
- `hammerspoon/init.lua` → `~/.hammerspoon/init.lua`, linked to the checkout at `~/studio/personal/dotfiles`; Hammerspoon reloads it on save
- `raycast/settings.rayconfig` → imported once per machine on the first rebuild after Raycast has been opened (see `raycast/README.md`)

AI tooling (`nixpkgs/home-manager/ai/`, guide in `docs/ai-setup.md`):
- `claude/` → `~/.claude/` (CLAUDE.md, onboarding.md, agents, hooks, own skills), linked to the checkout at `~/studio/personal/dotfiles` so edits land in the repo
- `claude/settings.base.json` and `codex/config.base.toml` are merged into the live `~/.claude/settings.json` / `~/.codex/config.toml` at activation (those stay real files)
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
- Podman with automatic start/stop on sleep/wake
- kubectl, kubectx, k9s, minikube
- Custom kubectl-forward script from GitHub

### Programming Languages & Runtimes
- **Node.js**: Managed via Bun and nvm (homebrew)
- **Python**: Python3 with pipx and uv
- **Go**: Enabled via home-manager
- **Ruby**: cocoapods and bundler

## System Services

### Automatic Sleep/Wake Management
- Sleepwatcher daemon stops/starts Podman machine on sleep/wake
- Scripts: `~/.sleep` and `~/.wakeup`

### Window Focus (no tiling)
Hammerspoon (`hammerspoon/init.lua`) moves focus and windows; JankyBorders marks the focused window:
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
System uses both Nix packages and Homebrew casks. Check `configuration.nix` for the current split.

### Service Restart
```bash
# Restart specific services after config changes
launchctl unload ~/Library/LaunchAgents/sleepwatcher.plist
launchctl load ~/Library/LaunchAgents/sleepwatcher.plist
```
