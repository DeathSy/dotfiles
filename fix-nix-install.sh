#!/bin/sh

echo "🔧 Nix Installation Recovery Script"
echo "This script fixes common Nix installation issues."
echo ""

# Safety check
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ Error: This script is designed for macOS only."
    exit 1
fi

echo "🔍 Checking for common Nix installation issues..."
echo ""

# Check for backup file conflicts
echo "📋 Checking for backup file conflicts..."
backup_files_found=false

for file in "/etc/bashrc.backup-before-nix" "/etc/zshrc.backup-before-nix" "/etc/bash.bashrc.backup-before-nix"; do
    if [ -f "$file" ]; then
        echo "  ❌ Found conflicting backup: $file"
        backup_files_found=true
    fi
done

for file in "$HOME/.bash_profile.backup-before-nix" "$HOME/.bashrc.backup-before-nix" "$HOME/.zshrc.backup-before-nix" "$HOME/.profile.backup-before-nix"; do
    if [ -f "$file" ]; then
        echo "  ❌ Found conflicting backup: $file"
        backup_files_found=true
    fi
done

if [ "$backup_files_found" = true ]; then
    echo ""
    echo "🚨 Found backup files that prevent Nix installation!"
    echo ""
    read -p "Remove these backup files? (y/N): " remove_backups
    
    if [ "$remove_backups" = "y" ] || [ "$remove_backups" = "Y" ]; then
        echo "Removing backup files..."
        
        # Remove system backup files
        sudo rm -f "/etc/bashrc.backup-before-nix" 2>/dev/null || true
        sudo rm -f "/etc/zshrc.backup-before-nix" 2>/dev/null || true
        sudo rm -f "/etc/bash.bashrc.backup-before-nix" 2>/dev/null || true
        
        # Remove user backup files
        rm -f "$HOME/.bash_profile.backup-before-nix" 2>/dev/null || true
        rm -f "$HOME/.bashrc.backup-before-nix" 2>/dev/null || true
        rm -f "$HOME/.zshrc.backup-before-nix" 2>/dev/null || true
        rm -f "$HOME/.profile.backup-before-nix" 2>/dev/null || true
        
        echo "✅ Backup files removed"
    else
        echo "❌ Backup files not removed. Manual cleanup required."
        echo ""
        echo "To fix manually, run these commands:"
        echo "  sudo rm -f /etc/bashrc.backup-before-nix"
        echo "  sudo rm -f /etc/zshrc.backup-before-nix"
        echo "  rm -f ~/.*.backup-before-nix"
        exit 1
    fi
else
    echo "  ✅ No conflicting backup files found"
fi

# Check for leftover Nix directories
echo ""
echo "📁 Checking for leftover Nix directories..."
leftover_dirs_found=false

for dir in "/nix" "/etc/nix"; do
    if [ -d "$dir" ]; then
        echo "  ❌ Found leftover directory: $dir"
        leftover_dirs_found=true
    fi
done

if [ "$leftover_dirs_found" = true ]; then
    echo ""
    echo "🚨 Found leftover Nix directories!"
    echo ""
    read -p "Remove these directories? (y/N): " remove_dirs
    
    if [ "$remove_dirs" = "y" ] || [ "$remove_dirs" = "Y" ]; then
        echo "Removing leftover directories..."
        sudo rm -rf "/nix" 2>/dev/null || true
        sudo rm -rf "/etc/nix" 2>/dev/null || true
        echo "✅ Leftover directories removed"
    else
        echo "❌ Directories not removed. You may need to run the full uninstall script."
        exit 1
    fi
else
    echo "  ✅ No leftover Nix directories found"
fi

# Check for running Nix processes
echo ""
echo "🔄 Checking for running Nix processes..."
if pgrep -f "nix-daemon" >/dev/null 2>&1; then
    echo "  ❌ Found running nix-daemon process"
    echo "Stopping nix-daemon..."
    sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist 2>/dev/null || true
    sudo pkill -f "nix-daemon" 2>/dev/null || true
    echo "  ✅ nix-daemon stopped"
else
    echo "  ✅ No running Nix processes found"
fi

echo ""
echo "🎉 Recovery complete!"
echo ""
echo "📝 Next steps:"
echo "1. Try running ./init.sh again"
echo "2. If you still have issues, run ./uninstall.sh for complete removal"
echo "3. Check the Nix installation logs for any other errors"
echo ""