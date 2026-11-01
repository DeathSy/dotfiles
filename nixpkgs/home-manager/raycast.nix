# Raycast on the hosts that import it (nixpkgs/hosts/garage.nix, which also
# lists the cask): started at login through desktop.nix, and its settings
# imported once (see raycast/README.md).
{ config, lib, ... }: {
  dotfiles.desktop.loginApps.raycast = "Raycast";

  # One-shot import, on the first rebuild after Raycast has been opened once.
  home.activation.raycast-import = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rayconfig=${config.home.homeDirectory}/studio/personal/dotfiles/raycast/settings.rayconfig
    marker=${config.xdg.stateHome}/dotfiles/raycast-imported
    if [ -f "$rayconfig" ] && [ ! -e "$marker" ] && [ -d /Applications/Raycast.app ] && [ "$(/usr/bin/defaults read com.raycast.macos raycast_OnboardingCompleted 2>/dev/null)" = 1 ]; then
      run /usr/bin/open -a Raycast "$rayconfig"
      run mkdir -p "$(dirname "$marker")"
      run touch "$marker"
    fi
  '';
}
