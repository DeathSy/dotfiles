#!/bin/sh

# Don't exit on error immediately - we want to handle errors gracefully
# set -e

echo "🗑️  macOS Dotfiles Uninstallation Script"
echo "This script will remove Nix, nix-darwin, and all associated configurations."
echo "⚠️  WARNING: This is a destructive operation that cannot be undone!"
echo ""

# Safety check
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ Error: This script is designed for macOS only."
    exit 1
fi

# Homebrew packages the dotfiles declare: nixpkgs/nix-darwin/configuration.nix
# (every machine) plus nixpkgs/hosts/<host>.nix. Keep in sync with those files.
BREWS="trivy pinentry ghostscript nvm sleepwatcher helm k6 doctl caddy terminal-notifier tailscale agent-browser googleworkspace-cli actionlint git-filter-repo semgrep sevenzip openjdk@17 pandoc poppler verapdf"
CASKS="sf-symbols desktoppr wezterm codex gcloud-cli android-platform-tools hammerspoon libreoffice upscayl android-commandlinetools cloudflare-warp google-chrome obsidian vorssaint"
# nixpkgs/hosts/garage.nix
GARAGE_CASKS="anydesk bruno chatgpt claude discord drawio figma raspberry-pi-imager raycast slack the-unarchiver webex wispr-flow microsoft-teams openvpn-connect"
# nixpkgs/hosts/garage-server.nix
GARAGE_SERVER_BREWS="cliproxyapi"
HOST="$(scutil --get LocalHostName 2>/dev/null)"
case "$HOST" in
    garage) CASKS="$CASKS $GARAGE_CASKS" ;;
    garage-server) BREWS="$BREWS $GARAGE_SERVER_BREWS" ;;
esac

# Function to check if file/directory exists and report
check_exists() {
    local path="$1"
    local description="$2"
    if [ -e "$path" ]; then
        echo "  ✓ Found: $path ($description)"
        return 0
    else
        echo "  - Not found: $path ($description)"
        return 1
    fi
}

# Function to find and list all relevant files
scan_system() {
    echo "🔍 Scanning system for Nix and dotfiles installations..."
    echo ""
    
    echo "📁 Nix Installation Files:"
    check_exists "/nix" "Main Nix store"
    check_exists "/etc/nix" "Nix system configuration"
    check_exists "/var/root/.nix-profile" "Root Nix profile"
    check_exists "/var/root/.nix-defexpr" "Root Nix expressions"
    check_exists "/var/root/.nix-channels" "Root Nix channels"
    check_exists "$HOME/.nix-profile" "User Nix profile"
    check_exists "$HOME/.nix-defexpr" "User Nix expressions"
    check_exists "$HOME/.nix-channels" "User Nix channels"
    check_exists "$HOME/.config/nix" "User Nix config"
    check_exists "$HOME/.config/nix-darwin" "nix-darwin config"
    
    echo ""
    echo "🔄 Nix Backup Files (can cause reinstall issues):"
    check_exists "/etc/bashrc.backup-before-nix" "System bashrc backup"
    check_exists "/etc/zshrc.backup-before-nix" "System zshrc backup"
    check_exists "/etc/bash.bashrc.backup-before-nix" "System bash.bashrc backup"
    check_exists "$HOME/.bash_profile.backup-before-nix" "User bash_profile backup"
    check_exists "$HOME/.bashrc.backup-before-nix" "User bashrc backup"
    check_exists "$HOME/.zshrc.backup-before-nix" "User zshrc backup"
    check_exists "$HOME/.profile.backup-before-nix" "User profile backup"
    
    echo ""
    echo "🚀 System Services:"
    check_exists "/Library/LaunchDaemons/org.nixos.nix-daemon.plist" "Nix daemon service"
    check_exists "$HOME/Library/LaunchAgents/org.nixos.nix-darwin.auto-upgrade.plist" "nix-darwin auto-upgrade"
    if launchctl list | grep -q "sleepwatcher" 2>/dev/null; then
        echo "  ✓ Found: sleepwatcher service (running)"
    else
        echo "  - Not found: sleepwatcher service"
    fi
    
    echo ""
    echo "🔗 Dotfiles Symlinks:"
    check_exists "$HOME/.config/nvim" "Neovim config"
    check_exists "$HOME/.config/sketchybar" "Sketchybar config"
    check_exists "$HOME/.config/wezterm" "WezTerm config"
    check_exists "$HOME/.config/sesh" "Sesh config"
    check_exists "$HOME/.config/ascii_arts" "ASCII arts"
    check_exists "$HOME/.config/neofetch" "Neofetch config"
    check_exists "$HOME/.claude" "Claude config"
    check_exists "$HOME/.sleep" "Sleep script"
    check_exists "$HOME/.wakeup" "Wakeup script"
    
    echo ""
    echo "🍺 Homebrew Packages (from dotfiles config):"
    if command -v brew >/dev/null 2>&1; then
        echo "  ✓ Homebrew is installed"
        # Check for specific packages from our config
        for pkg in $BREWS; do
            if brew list "$pkg" >/dev/null 2>&1; then
                echo "  ✓ Found brew package: $pkg"
            else
                echo "  - Not found brew package: $pkg"
            fi
        done
        for cask in $CASKS; do
            if brew list --cask "$cask" >/dev/null 2>&1; then
                echo "  ✓ Found brew cask: $cask"
            else
                echo "  - Not found brew cask: $cask"
            fi
        done
    else
        echo "  - Homebrew not installed"
    fi
    
    echo ""
}

# Run system scan first
scan_system

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

if [ "$REMOVE_HOMEBREW" = true ]; then
    echo ""
    echo "🍺 These Homebrew packages will be removed if installed:"
    echo "  Brews: $BREWS"
    echo "  Casks: $CASKS"
fi

echo ""
read -p "Are you sure you want to proceed? Type 'YES' to confirm: " confirm
if [ "$confirm" != "YES" ]; then
    echo "❌ Uninstallation cancelled."
    exit 0
fi

echo ""
echo "🚀 Starting uninstallation process..."

# Function to safely remove files/directories with better error handling
safe_remove() {
    local path="$1"
    if [ -e "$path" ]; then
        echo "Removing: $path"
        
        # Special handling for /nix directory
        if [ "$path" = "/nix" ]; then
            # First, try to remove the Nix store contents
            if [ -d "/nix/store" ]; then
                echo "  Clearing Nix store..."
                sudo find /nix/store -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
            fi
            
            # Handle .Trashes directory with special permissions
            if [ -d "/nix/.Trashes" ]; then
                echo "  Removing .Trashes directory..."
                sudo chmod -R 777 "/nix/.Trashes" 2>/dev/null || true
                sudo rm -rf "/nix/.Trashes" 2>/dev/null || true
            fi
            
            # Remove other directories
            for subdir in /nix/*; do
                if [ -d "$subdir" ] && [ "$(basename "$subdir")" != ".Trashes" ]; then
                    echo "  Removing $(basename "$subdir")..."
                    sudo rm -rf "$subdir" 2>/dev/null || true
                fi
            done
            
            # Finally remove the /nix directory itself
            sudo rmdir /nix 2>/dev/null || {
                echo "  ⚠️  Could not remove /nix directory completely"
                echo "     Run 'sudo rm -rf /nix' manually if needed"
            }
        else
            # Regular removal for other paths
            if sudo rm -rf "$path" 2>/dev/null; then
                echo "  ✅ Successfully removed: $path"
            else
                echo "  ⚠️  Could not remove: $path (may require manual cleanup)"
            fi
        fi
    else
        echo "  - Already removed: $path"
    fi
}

# Function to safely remove files without sudo
user_remove() {
    local path="$1"
    if [ -e "$path" ]; then
        echo "Removing: $path"
        if rm -rf "$path" 2>/dev/null; then
            echo "  ✅ Successfully removed: $path"
        else
            echo "  ⚠️  Could not remove: $path"
        fi
    else
        echo "  - Already removed: $path"
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
    echo "Checking for sleepwatcher service..."
    if launchctl list | grep -q "sleepwatcher" 2>/dev/null; then
        echo "  Stopping sleepwatcher service..."
        launchctl unload "$HOME/Library/LaunchAgents/sleepwatcher.plist" 2>/dev/null || true
    fi
    user_remove "$HOME/Library/LaunchAgents/sleepwatcher.plist"

    # home-manager LaunchAgents that don't need Nix and would keep running
    for agent in org.nix-community.home.cliproxyapi-tunnel ai.headroom.proxy; do
        launchctl bootout "gui/$(id -u)/$agent" 2>/dev/null || true
        user_remove "$HOME/Library/LaunchAgents/$agent.plist"
    done

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
    
    # Clean shell profiles and remove Nix backup files
    echo "Cleaning shell profiles and backup files..."
    for profile in "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -f "$profile" ]; then
            sed -i '' '/nix/d' "$profile" 2>/dev/null || true
        fi
    done
    
    # Remove Nix backup files that cause reinstallation issues
    echo "Removing Nix backup files..."
    safe_remove "/etc/bashrc.backup-before-nix"
    safe_remove "/etc/zshrc.backup-before-nix"
    safe_remove "/etc/bash.bashrc.backup-before-nix"
    user_remove "$HOME/.bash_profile.backup-before-nix"
    user_remove "$HOME/.bashrc.backup-before-nix"
    user_remove "$HOME/.zshrc.backup-before-nix"
    user_remove "$HOME/.profile.backup-before-nix"
    
    echo "✅ Nix and nix-darwin removed"
fi

if [ "$REMOVE_HOMEBREW" = true ]; then
    echo "🍺 Removing Homebrew packages installed by dotfiles..."
    
    if command -v brew >/dev/null 2>&1; then
        # Remove specific packages from our configuration
        echo "Removing Homebrew packages..."
        # Stop brew services first so their launchd plists don't stay behind
        if [ "$HOST" = "garage-server" ] && brew list cliproxyapi >/dev/null 2>&1; then
            echo "  Stopping brew service: cliproxyapi"
            brew services stop cliproxyapi 2>/dev/null || true
        fi
        if brew list tailscale >/dev/null 2>&1; then
            echo "  Stopping brew service: tailscale (runs as root)"
            sudo brew services stop tailscale 2>/dev/null || true
        fi

        for pkg in $BREWS; do
            if brew list "$pkg" >/dev/null 2>&1; then
                echo "  Removing brew package: $pkg"
                brew uninstall --ignore-dependencies "$pkg" 2>/dev/null || echo "    ⚠️  Could not remove $pkg"
            fi
        done
        
        for cask in $CASKS; do
            if brew list --cask "$cask" >/dev/null 2>&1; then
                echo "  Removing brew cask: $cask"
                brew uninstall --cask "$cask" 2>/dev/null || echo "    ⚠️  Could not remove $cask"
            fi
        done
        
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