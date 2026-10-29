# garage: the main Mac. Added on top of the shared config in flake.nix.
# Raycast and JankyBorders run only here.
{ ... }: {
  imports = [ ../nix-darwin/jankyborders.nix ];

  networking.computerName = "ksotis";

  homebrew.casks = [
    "anydesk"
    "bruno"
    "chatgpt"
    "claude"
    "discord"
    "drawio"
    "figma"
    "raspberry-pi-imager"
    "raycast"
    "slack"
    "the-unarchiver"
    "webex"
    "wispr-flow"

    # .pkg casks: reinstall over an app installed by hand instead of adopting it.
    "microsoft-teams"
    "openvpn-connect"
  ];

  home-manager.users.ksotis.imports = [ ../home-manager/raycast.nix ];
}
