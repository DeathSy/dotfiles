#!/bin/sh

# Exit on any error
set -e

# Host to set up, as named in flake.nix: garage (default) or garage-server
HOST="${1:-garage}"

echo "🚀 Starting macOS device setup with Nix and nix-darwin..."
echo "This script will install and configure your complete development environment."
echo "Note: This script is idempotent - safe to run multiple times."
echo ""

# Check if we're on macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ Error: This script is designed for macOS only."
    exit 1
fi

# Check for Command Line Tools
echo "📋 Checking for Xcode Command Line Tools..."
if ! xcode-select -p &> /dev/null; then
    echo "Installing Xcode Command Line Tools..."
    echo "Please complete the installation when prompted, then re-run this script."
    xcode-select --install
    exit 1
else
    echo "✅ Xcode Command Line Tools found"
fi

# Check if we're in the right directory
if [ ! -f "flake.nix" ] || [ ! -d "nixpkgs" ]; then
    echo "❌ Error: Please run this script from the dotfiles repository root."
    echo "Expected files: flake.nix and nixpkgs/ directory"
    echo "Current directory contents:"
    ls -la
    exit 1
fi

# Install Homebrew if not present (needed for some GUI apps)
echo "🍺 Checking for Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for current session
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "✅ Homebrew found"
fi

# Clean up any leftover Nix backup files that might cause installation issues
echo "🧹 Cleaning up any leftover Nix backup files..."
if [ -f "/etc/bashrc.backup-before-nix" ] || [ -f "/etc/zshrc.backup-before-nix" ]; then
    echo "Found leftover Nix backup files that could cause installation issues."
    echo "Cleaning them up..."
    sudo rm -f "/etc/bashrc.backup-before-nix" 2>/dev/null || true
    sudo rm -f "/etc/zshrc.backup-before-nix" 2>/dev/null || true
    sudo rm -f "/etc/bash.bashrc.backup-before-nix" 2>/dev/null || true
    rm -f "$HOME/.bash_profile.backup-before-nix" 2>/dev/null || true
    rm -f "$HOME/.bashrc.backup-before-nix" 2>/dev/null || true
    rm -f "$HOME/.zshrc.backup-before-nix" 2>/dev/null || true
    rm -f "$HOME/.profile.backup-before-nix" 2>/dev/null || true
    echo "✅ Backup files cleaned"
fi

# Install Nix if not present
echo "❄️  Checking for Nix..."
if ! command -v nix >/dev/null 2>&1; then
    echo "Installing Nix..."
    curl -L https://nixos.org/nix/install | sh
    echo "✅ Nix installed"
elif [ -d "/nix" ] && [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
    echo "✅ Nix found (complete installation)"
else
    echo "⚠️  Nix command found but installation may be incomplete"
    echo "   Continuing with setup..."
fi

# Source nix profile to make nix available in current session
echo "🔧 Sourcing Nix profile..."
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
elif [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Verify nix is available
if ! command -v nix >/dev/null 2>&1; then
    echo "❌ Error: Nix installation failed or is not in PATH."
    echo "Please restart your terminal and try again."
    exit 1
fi

# Set experimental features
echo "⚙️  Configuring Nix experimental features..."
# sudo drops NIX_CONFIG and may not have nix on its PATH, so the first switch
# below calls nix by absolute path and passes the flag itself.
export NIX_CONFIG="experimental-features = nix-command flakes"

# Check if nix-darwin is already configured
echo "🔧 Checking nix-darwin status..."
if command -v darwin-rebuild >/dev/null 2>&1; then
    echo "✅ nix-darwin already configured"
    echo "🔄 Updating existing configuration..."
    echo "This may take a few minutes as packages are updated..."
    echo "Note: You may be prompted for your password (sudo access required)"
    sudo "$(command -v darwin-rebuild)" switch --flake "$(pwd)#$HOST"
else
    echo "🏗️  Running initial nix-darwin setup..."
    echo "This may take several minutes as packages are downloaded and built..."
    echo "Note: You may be prompted for your password (sudo access required)"
    # The Nix installer edits these; nix-darwin replaces them (its versions
    # load Nix too) but refuses to overwrite files it doesn't recognize.
    for f in /etc/bashrc /etc/zshrc; do
        if [ -f "$f" ] && [ ! -L "$f" ] && [ ! -e "$f.before-nix-darwin" ]; then
            echo "Moving $f to $f.before-nix-darwin"
            sudo mv "$f" "$f.before-nix-darwin"
        fi
    done
    sudo "$(command -v nix)" --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake "$(pwd)#$HOST"
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "📝 Next steps:"
echo "1. Restart your terminal to load the new shell configuration"
echo "2. Log out and back in so the menu bar, input source and screenshot settings apply"
echo "3. On garage: open Raycast once, then run 'rebuild' to import its settings"
echo "4. Confirm Chrome as the default browser when macOS asks"
echo "5. Start Tailscale's daemon once: 'sudo brew services start tailscale', then 'tailscale up'"
echo "6. Some GUI applications may require manual permission grants"
echo "7. Run 'darwin-rebuild switch --flake .#$HOST' for future updates"
echo ""
echo "🔧 Useful commands:"
echo "  - sudo darwin-rebuild switch --flake .#$HOST  # Update system configuration"
echo "  - nix flake update                      # Update flake inputs"
echo "  - home-manager switch                   # Update user configuration only"
echo ""

