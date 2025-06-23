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
- **Window management** via AeroSpace + Sketchybar + JankyBorders
- **Terminal environment** via WezTerm + Neovim + Zsh
- **Keyboard customization** via Karabiner Elements

### Key Configuration Modules

- `flake.nix` - Main flake configuration defining the "garage" system
- `nixpkgs/nix-darwin/configuration.nix` - System-level packages, homebrew, macOS defaults
- `nixpkgs/home-manager/home.nix` - User packages, dotfile linking, services
- Individual service configs: `git.nix`, `zsh.nix`, `tmux.nix`, `starship.nix`, etc.

### Dotfile Symlinks

Configuration files are symlinked from this repo to `~/.config/` via home-manager:
- `nvim/` → `~/.config/nvim/`
- `sketchybar/` → `~/.config/sketchybar/`
- `wezterm.lua` → `~/.config/wezterm/wezterm.lua`
- `sesh.toml` → `~/.config/sesh/sesh.toml`

## Development Environment

### Primary Tools
- **Terminal**: WezTerm with Catppuccin theme
- **Shell**: Zsh with Starship prompt and antigen
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

### Window Management Stack
- **AeroSpace**: Tiling window manager (`nixpkgs/nix-darwin/aerospace.nix`)
- **Sketchybar**: Status bar (`nixpkgs/nix-darwin/sketchybar.nix`)  
- **JankyBorders**: Window borders (`nixpkgs/nix-darwin/jankyborders.nix`)

### macOS System Defaults
Comprehensive macOS customization in `configuration.nix`:
- Dock: autohide, small tiles, no recents
- Keyboard: fast repeat, caps→ctrl
- Trackpad: tap-to-click, right-click, three-finger drag
- Finder: show extensions, path bar, hidden files
- Global: dark mode, no autocorrect, hidden menu bar

## Key Keyboard Customizations

Karabiner Elements configuration in `karabiner/karabiner.edn` (currently empty - uses default Goku config)

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
