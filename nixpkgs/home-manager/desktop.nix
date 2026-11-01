# Desktop session: apps started at login and default browser/mail/PDF handlers.
{ config, lib, pkgs, ... }: {
  options.dotfiles.desktop.loginApps = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = { claude = "Claude"; };
    description = "Apps started at login (launchd agent name -> app). Every Mac gets the ones below; a host module (nixpkgs/hosts/<host>.nix) adds its own, like its casks.";
  };

  options.dotfiles.desktop.browser = lib.mkOption {
    type = lib.types.str;
    default = "com.apple.Safari";
    description = "Bundle id of the default handler for web links and HTML files. A host that installs another browser sets it.";
  };

  options.dotfiles.desktop.mailClient = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Bundle id of the default mailto: handler, or null to leave it alone.";
  };

  config = {
    dotfiles.desktop.loginApps = {
      cloudflare-warp = "Cloudflare WARP";
      vorssaint = "Vorssaint";
      hammerspoon = "Hammerspoon";
    };

    # `open -g` keeps them in the background, and the pgrep guard skips apps
    # already running (e.g. via their own login item), so they don't get a
    # reopen event. A missing app just makes that agent exit.
    launchd.agents = lib.mapAttrs' (name: app: lib.nameValuePair "login-${name}" {
      enable = true;
      config = {
        ProgramArguments = [ "/bin/sh" "-c" ''/usr/bin/pgrep -xq "$1" || /usr/bin/open -g -a "$2"'' "login-${name}" (lib.removeSuffix ".app" (baseNameOf app)) app ];
        RunAtLoad = true;
      };
    }) config.dotfiles.desktop.loginApps;

    # The host's browser for web links and HTML, its mail client for mailto:,
    # Preview for PDFs. Only touches a handler that differs; macOS asks once to
    # confirm a browser change.
    home.activation.default-apps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # duti: `-s app scheme` sets a URL scheme; `-s app uti role` a file type.
      set_handler() {
        if [ "$(${pkgs.duti}/bin/duti -d "$2" 2>/dev/null)" != "$1" ]; then
          run ${pkgs.duti}/bin/duti -s "$@" || true
        fi
      }
      set_handler ${config.dotfiles.desktop.browser} http
      set_handler ${config.dotfiles.desktop.browser} https
      ${lib.optionalString (config.dotfiles.desktop.mailClient != null) "set_handler ${config.dotfiles.desktop.mailClient} mailto"}
      set_handler ${config.dotfiles.desktop.browser} public.html all
      set_handler com.apple.Preview com.adobe.pdf all
    '';
  };
}
