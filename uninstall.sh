#!/bin/sh

# Exit on any error
set -e

echo "🗑️  macOS Dotfiles Uninstallation Script"
echo "This script will remove Nix, nix-darwin, and all associated configurations."
echo "⚠️  WARNING: This is a destructive operation that cannot be undone!"
echo ""

# Safety check
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ Error: This script is designed for macOS only."
    exit 1
fi

# Confirmation prompt
echo "What would you like to uninstall?"
echo "1) Complete removal (Nix + nix-darwin + Homebrew packages)"
echo "2) Nix and nix-darwin only (keep Homebrew)"
echo "3) Dotfiles symlinks only (keep Nix and Homebrew)"
echo "4) Cancel"
echo ""
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        REMOVE_NIX=true
        REMOVE_HOMEBREW=true
        REMOVE_SYMLINKS=true
        ;;
    2)
        REMOVE_NIX=true
        REMOVE_HOMEBREW=false
        REMOVE_SYMLINKS=true
        ;;
    3)
        REMOVE_NIX=false
        REMOVE_HOMEBREW=false
        REMOVE_SYMLINKS=true
        ;;
    4)
        echo "❌ Uninstallation cancelled."
        exit 0
        ;;
    *)
        echo "❌ Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
read -p "Are you sure you want to proceed? Type 'YES' to confirm: " confirm
if [ "$confirm" != "YES" ]; then
    echo "❌ Uninstallation cancelled."
    exit 0
fi

echo ""
echo "🚀 Starting uninstallation process..."

# Function to safely remove files/directories
safe_remove() {
    if [ -e "$1" ]; then
        echo "Removing: $1"
        sudo rm -rf "$1"
    fi
}

# Function to safely remove files without sudo
user_remove() {
    if [ -e "$1" ]; then
        echo "Removing: $1"
        rm -rf "$1"
    fi
}

if [ "$REMOVE_SYMLINKS" = true ]; then
    echo "🔗 Removing dotfiles symlinks and configurations..."
    
    # Remove home-manager managed symlinks
    user_remove "$HOME/.config/nvim"
    user_remove "$HOME/.config/sketchybar"
    user_remove "$HOME/.config/wezterm"
    user_remove "$HOME/.config/sesh"
    user_remove "$HOME/.config/ascii_arts"
    user_remove "$HOME/.config/neofetch"
    user_remove "$HOME/.claude"
    user_remove "$HOME/.sleep"
    user_remove "$HOME/.wakeup"
    
    # Stop and remove launchd services
    if launchctl list | grep -q "sleepwatcher"; then
        echo "Stopping sleepwatcher service..."
        launchctl unload "$HOME/Library/LaunchAgents/sleepwatcher.plist" 2>/dev/null || true
        user_remove "$HOME/Library/LaunchAgents/sleepwatcher.plist"
    fi
    
    echo "✅ Dotfiles symlinks removed"
fi

if [ "$REMOVE_NIX" = true ]; then
    echo "❄️  Removing nix-darwin configuration..."
    
    # Unload nix-darwin services
    if command -v darwin-rebuild >/dev/null 2>&1; then
        echo "Unloading nix-darwin services..."
        sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist 2>/dev/null || true
        launchctl unload "$HOME/Library/LaunchAgents/org.nixos.nix-darwin.auto-upgrade.plist" 2>/dev/null || true
    fi
    
    echo "🗑️  Removing Nix installation..."
    
    # Stop nix-daemon
    sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist 2>/dev/null || true
    
    # Remove Nix store and configuration
    safe_remove "/nix"
    safe_remove "/etc/nix"
    safe_remove "/var/root/.nix-profile"
    safe_remove "/var/root/.nix-defexpr"
    safe_remove "/var/root/.nix-channels"
    user_remove "$HOME/.nix-profile"
    user_remove "$HOME/.nix-defexpr"
    user_remove "$HOME/.nix-channels"
    user_remove "$HOME/.config/nix"
    user_remove "$HOME/.config/nix-darwin"
    
    # Remove nix-darwin launch daemons
    safe_remove "/Library/LaunchDaemons/org.nixos.nix-daemon.plist"
    user_remove "$HOME/Library/LaunchAgents/org.nixos.nix-darwin.auto-upgrade.plist"
    
    # Remove synthetic.conf entries
    if [ -f "/etc/synthetic.conf" ]; then
        echo "Cleaning /etc/synthetic.conf..."
        sudo sed -i '' '/^nix/d' /etc/synthetic.conf 2>/dev/null || true
    fi
    
    # Remove from /etc/bashrc and /etc/zshrc
    if [ -f "/etc/bashrc" ]; then
        echo "Cleaning /etc/bashrc..."
        sudo sed -i '' '/nix/d' /etc/bashrc 2>/dev/null || true
    fi
    
    if [ -f "/etc/zshrc" ]; then
        echo "Cleaning /etc/zshrc..."
        sudo sed -i '' '/nix/d' /etc/zshrc 2>/dev/null || true
    fi
    
    # Clean shell profiles
    echo "Cleaning shell profiles..."
    for profile in "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -f "$profile" ]; then
            sed -i '' '/nix/d' "$profile" 2>/dev/null || true
        fi
    done
    
    echo "✅ Nix and nix-darwin removed"
fi

if [ "$REMOVE_HOMEBREW" = true ]; then
    echo "🍺 Removing Homebrew packages installed by dotfiles..."
    
    if command -v brew >/dev/null 2>&1; then
        # Remove specific packages from our configuration
        echo "Removing Homebrew packages..."
        brew uninstall --ignore-dependencies trivy pinentry ghostscript goku nvm sleepwatcher act helm 2>/dev/null || true
        brew uninstall --cask sf-symbols desktoppr arc wezterm anydesk ngrok postman raycast karabiner-elements 2>/dev/null || true
        
        # Remove tap
        brew untap nikitabobko/tap 2>/dev/null || true
        
        echo "⚠️  Note: Homebrew itself is still installed. To remove it completely, run:"
        echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\""
    else
        echo "Homebrew not found, skipping..."
    fi
    
    echo "✅ Homebrew packages removed"
fi

# Reset macOS defaults that were changed
echo "🔧 Resetting macOS system defaults..."

# Reset dock settings
defaults delete com.apple.dock autohide 2>/dev/null || true
defaults delete com.apple.dock show-recents 2>/dev/null || true
defaults delete com.apple.dock tilesize 2>/dev/null || true

# Reset global settings
defaults delete NSGlobalDomain ApplePressAndHoldEnabled 2>/dev/null || true
defaults delete NSGlobalDomain InitialKeyRepeat 2>/dev/null || true
defaults delete NSGlobalDomain KeyRepeat 2>/dev/null || true
defaults delete NSGlobalDomain AppleInterfaceStyle 2>/dev/null || true
defaults delete NSGlobalDomain _HIHideMenuBar 2>/dev/null || true

# Reset finder settings
defaults delete com.apple.finder AppleShowAllExtensions 2>/dev/null || true
defaults delete com.apple.finder ShowPathbar 2>/dev/null || true
defaults delete com.apple.finder AppleShowAllFiles 2>/dev/null || true

# Reset keyboard settings
sudo defaults delete /Library/Preferences/com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null || true

# Restart affected services
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "✅ macOS defaults reset"

echo ""
echo "🎉 Uninstallation complete!"
echo ""
echo "📝 Additional cleanup you may want to do manually:"
echo "1. Remove any remaining GUI applications from /Applications/"
echo "2. Clear browser bookmarks and extensions"
echo "3. Remove any SSH keys or GPG keys if no longer needed"
echo "4. Check ~/Library/Application Support/ for app data"
echo ""
echo "💡 To complete the cleanup:"
echo "1. Restart your Mac to ensure all changes take effect"
echo "2. Check that /nix directory is completely removed"
echo "3. Verify your shell profiles no longer reference nix"
echo ""