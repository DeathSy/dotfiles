# garage-server: the server Mac. Added on top of the shared config in flake.nix;
# it needs nothing beyond it yet.
{ ... }: {
  networking.computerName = "ksotis-server";
}
