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
- `nixpkgs/nix-darwin/macos.nix` - macOS settings (defaults, Dock, keyboard, trackpad, firewall, hostname, power), captured from the live machine
- `nixpkgs/home-manager/home.nix` - User packages, dotfile linking, services
- Individual service configs: `git.nix`, `zsh.nix`, `tmux.nix`, `starship.nix`, etc.

### Dotfile Symlinks

Configuration files are symlinked from this repo to `~/.config/` via home-manager:
- `nvim/` → `~/.config/nvim/`
- `wezterm.lua` → `~/.config/wezterm/wezterm.lua`
- `sesh.toml` → `~/.config/sesh/sesh.toml`
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
