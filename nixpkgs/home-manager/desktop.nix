# Desktop session: apps started at login and default browser/PDF handlers.
{ lib, pkgs, ... }:
let
  # Apps that start at login. `open -g` keeps them in the background, and the
  # pgrep guard skips apps already running (e.g. via their own login item), so
  # they don't get a reopen event. A missing app just makes that agent exit.
  loginApps = {
    cloudflare-warp = "Cloudflare WARP";
    openvpn-connect = "OpenVPN Connect";
    claude = "Claude";
    vorssaint = "Vorssaint";
    hammerspoon = "Hammerspoon";
  };
in {
  launchd.agents = lib.mapAttrs' (name: app: lib.nameValuePair "login-${name}" {
    enable = true;
    config = {
      ProgramArguments = [ "/bin/sh" "-c" ''/usr/bin/pgrep -xq "$1" || /usr/bin/open -g -a "$2"'' "login-${name}" (lib.removeSuffix ".app" (baseNameOf app)) app ];
      RunAtLoad = true;
    };
  }) loginApps;

  # Chrome for web and mail, Preview for PDFs. Only touches a handler that
  # differs; macOS asks once to confirm a browser change.
  home.activation.default-apps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
