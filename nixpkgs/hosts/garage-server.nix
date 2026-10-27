# garage-server: the server Mac. Added on top of the shared config in flake.nix;
# only its name differs so far, it has no apps of its own.
{ ... }: {
  networking.computerName = "ksotis-server";
}
