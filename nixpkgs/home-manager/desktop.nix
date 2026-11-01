# Desktop session: apps started at login and default browser/PDF handlers.
{ config, lib, pkgs, ... }: {
  # Apps that start at login (agent name -> app). Every Mac gets these; a host
  # module (nixpkgs/hosts/<host>.nix) adds its own apps, like its casks.
  options.dotfiles.desktop.loginApps = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
  };

  config.dotfiles.desktop.loginApps = {
    cloudflare-warp = "Cloudflare WARP";
    vorssaint = "Vorssaint";
    hammerspoon = "Hammerspoon";
  };

  # `open -g` keeps them in the background, and the pgrep guard skips apps
  # already running (e.g. via their own login item), so they don't get a
  # reopen event. A missing app just makes that agent exit.
  config.launchd.agents = lib.mapAttrs' (name: app: lib.nameValuePair "login-${name}" {
    enable = true;
    config = {
      ProgramArguments = [ "/bin/sh" "-c" ''/usr/bin/pgrep -xq "$1" || /usr/bin/open -g -a "$2"'' "login-${name}" (lib.removeSuffix ".app" (baseNameOf app)) app ];
      RunAtLoad = true;
    };
  }) config.dotfiles.desktop.loginApps;

  # Chrome for web and mail, Preview for PDFs. Only touches a handler that
  # differs; macOS asks once to confirm a browser change.
  config.home.activation.default-apps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # duti: `-s app scheme` sets a URL scheme; `-s app uti role` a file type.
    set_handler() {
      if [ "$(${pkgs.duti}/bin/duti -d "$2" 2>/dev/null)" != "$1" ]; then
        run ${pkgs.duti}/bin/duti -s "$@" || true
      fi
    }
    set_handler com.google.Chrome http
    set_handler com.google.Chrome https
    set_handler com.google.Chrome mailto
    set_handler com.google.Chrome public.html all
    set_handler com.apple.Preview com.adobe.pdf all
  '';
}
