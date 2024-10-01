#!/bin/sh

curl -L https://nixos.org/nix/install | sh

nix run nix-darwin -- switch --flake $(pwd)/nixpkgs

