#!/bin/sh

curl -L https://nixos.org/nix/install | sh

export NIX_CONFIG="experimental-features = nix-command flakes"
nix run nix-darwin -- switch --flake $(pwd)/nixpkgs

