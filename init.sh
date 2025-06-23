#!/bin/sh

# Exit on any error
set -e

echo "Starting fresh device setup with Nix and nix-darwin..."

# Install Nix
echo "Installing Nix..."
curl -L https://nixos.org/nix/install | sh

# Source nix profile to make nix available in current session
echo "Sourcing Nix profile..."
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
elif [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Set experimental features
echo "Configuring Nix experimental features..."
export NIX_CONFIG="experimental-features = nix-command flakes"

# Create nixpkgs directory if it doesn't exist
if [ ! -d "nixpkgs" ]; then
    echo "nixpkgs directory not found. Please ensure your flake configuration is in a 'nixpkgs' directory."
    echo "Current directory contents:"
    ls -la
    exit 1
fi

# Run nix-darwin
echo "Running nix-darwin setup..."
nix run nix-darwin -- switch --flake $(pwd)/nixpkgs

echo "Setup complete!"

