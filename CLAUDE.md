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
- `nixpkgs/nix-darwin/hotkeys.nix` - System keyboard shortcuts, captured from the live machine; "Switch to Desktop" ⌃1…⌃9 is off for Hammerspoon's workspaces
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
- `hammerspoon/init.lua` → `~/.hammerspoon/init.lua`, linked to the checkout at `~/studio/personal/dotfiles`; it loads `workspaces.lua` from the checkout, and Hammerspoon reloads on save of either
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
Hammerspoon (`hammerspoon/init.lua`, workspaces in `hammerspoon/workspaces.lua`) moves focus and windows; JankyBorders marks the focused window:
- Virtual workspaces 1–9, shared by all displays as in AeroSpace: each workspace lives on one display and each display shows one. Hidden workspaces' windows are parked off-screen in a corner of their display (bottom-right or bottom-left, whichever covers less of the other displays; macOS keeps title bars below the menu bar, so never a top corner), leaving a 1 px sliver. Windows come back to their saved position at their current size
- At start, displays ordered left to right, then top to bottom, show workspaces 1, 2, …, and their windows join them
- ⌃1…9: focus workspace N. If it's shown on some display, focus its last focused window there (if it's empty, the frontmost window still on that display, else the desktop). Pressing ⌃N for the workspace already shown refocuses it, so a parked window can't keep focus; if hidden, show it on its display, parking what was there. An unused workspace appears on the focused display (the focused window's, else the mouse's). Empty workspaces forget their display once hidden
- ⌥⇧1…9: move the focused window to workspace N and follow it. If N lives on another display the window moves there, keeping its offset from the display's corner, clamped to fit; this is the only time a window is shrunk, when it's bigger than the target display. Works for windows without a title bar too. ⌥⇧1…9 no longer types ⁄ € ‹ › ﬁ ﬂ ‡ ° ·
- New windows join the workspace shown on their display; a window dragged to another display joins the one shown there. Focusing a parked window shows its workspace, whoever focuses it: ⌘Tab or the Dock, but also macOS after you close a window, or an agent's `open <url>` activating an app whose window is parked. That is deliberate: a parked window never keeps the keyboard. A minimized or hidden (⌘H) window that comes back while its workspace is hidden is parked again. A window that's off every display without being parked (app relaunch, a crash mid-switch) is brought onto the focused display. Native full-screen and non-standard windows are left alone
- Display changes are handled 2.5 s after they settle, so sleep and wake don't shuffle anything. A display that moves or changes resolution takes its workspaces' saved frames along. Unplugging a display moves its workspaces to the main display, parked; they remember it, and when it comes back they return to it and it shows what it showed before
- State (window → workspace and saved frame, workspace → display) is saved with `hs.settings` on every change, with the boot time: after a reboot window ids are reused, so the state starts over. Reloading or quitting Hammerspoon puts every parked window back; loading parks them again
- Recovery: `space unpark` (or `open -g "hammerspoon://space?unpark=1"`) brings every window back on-screen, including off-screen ones it never parked, and starts over
- `space N`: same as ⌃N from a terminal, via `hammerspoon://space?n=N`
- ⌃⌥h/j/k/l: focus the nearest window west/south/north/east, skipping parked ones
- The mouse follows focus to the window centre unless already inside, a mouse button is held, Mission Control is open, the window is non-standard or parked, or a switch is in progress (the switch moves the mouse itself)
- Parked windows sit off-screen in a corner: screenshots and computer use by agents won't see them until their workspace is shown, and Mission Control shows them squeezed into corners
- Use one macOS Desktop per display (remove the others in Mission Control). Hammerspoon needs Accessibility permission, granted by hand in System Settings → Privacy & Security → Accessibility. Log out once if ⌃1…9 still switches Desktops after a rebuild
- Displays stacked vertically: a display with another one below it has its bottom corners on that display, so parked windows there pick the corner covering less of it and can show over it. Prefer side-by-side arrangements
- To check on real hardware: an empty workspace focuses the Finder desktop, which might make a parked Finder window key. After 0.5 s Hammerspoon focuses the desktop once more if a parked window has the keyboard; check whether that's enough
- Cases to test first after a change: ⌃N and ⌥⇧N across two displays, ⌘Tab to a parked window, unplugging a display, and reloading Hammerspoon with workspaces hidden

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
