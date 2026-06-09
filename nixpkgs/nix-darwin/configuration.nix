{ pkgs, config, lib, ... }: {
  environment.systemPackages = with pkgs; [
    # Terminal related
    vim
    neovim
    direnv
    fastfetch
    fzf
    bash
    bat
    fd
    mkalias
    lf
    jq
    tree
    ripgrep
    btop
    eza
    sketchybar
    jankyborders
    localstack
    ffmpeg
    gnupg
    pinentry_mac
    superfile

    # Git $ Github related
    git
    git-credential-manager
    gitflow
    git-lfs
  ];

  nix.settings.experimental-features = "nix-command flakes";

  nixpkgs = {
		hostPlatform = "aarch64-darwin";

		config = {
      # Suck it stallman
      allowUnfree = true;
      allowBroken = false;
      allowInsecure = false;
      allowUnsupportedSystem = false;
    };

    overlays = [
      # pipx 1.8.0's test suite fails on this nixpkgs snapshot (packaging
      # whitespace-normalization change); skip its checks so it still builds.
      (final: prev: {
        pipx = prev.pipx.overridePythonAttrs (_: { doCheck = false; });
      })
    ];
	};

  programs.zsh.enable = true;

	environment.shells = with pkgs; [ zsh ];

	fonts.packages = with pkgs; [
		recursive
    nerd-fonts.hack
    nerd-fonts.fira-code
	];

  homebrew = {
    enable = true;
    global = {
      autoUpdate = true;
    };

		onActivation = {
      # "uninstall"/"zap" make nix-darwin pass `brew bundle --cleanup`, which
      # Homebrew 5.x no longer accepts (cleanup is now its own subcommand) and
      # which aborts activation. Keep off until nix-darwin emits the new form;
      # run `brew bundle cleanup` manually to prune undeclared packages.
      cleanup = "none";
      upgrade = true;
    };

		taps = [
			"nikitabobko/tap"
		];

    brews = [
      "trivy"
      "pinentry"
      "ghostscript"
      "goku"
      "nvm"
      "sleepwatcher"
      "act"
      "helm"
      "k6"
      "claude-squad"
    ];

    casks = [
      "sf-symbols"
      "desktoppr"
      "wezterm"
      "ngrok"
      "raycast"
      "karabiner-elements"
      "claude"
      "gcloud-cli"
      "android-platform-tools"
    ];
  };

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  environment.etc."gnupg/gpg-agent.conf".text = ''
    pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
    default-cache-ttl 1800
    max-cache-ttl 7200
  '';

  system = {
    stateVersion = 5;

    primaryUser = "ksotis";

    defaults =  {
      dock = {
        autohide = true;
        mru-spaces = false;
        show-recents = false;
        tilesize = 32;
        expose-group-apps = true;
      };

      NSGlobalDomain = {
        ApplePressAndHoldEnabled = false;
        InitialKeyRepeat = 10;
        KeyRepeat = 2;
        AppleEnableSwipeNavigateWithScrolls = false;
        AppleInterfaceStyle = "Dark";
        AppleShowAllExtensions = true;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        _HIHideMenuBar = true;
      };

      WindowManager = {
        EnableStandardClickToShowDesktop = false;
        GloballyEnabled = false;
        AppWindowGroupingBehavior = true;
        HideDesktop = false;
        StageManagerHideWidgets = false;
      };

      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
        AppleShowAllFiles = true;
        FXEnableExtensionChangeWarning = false;
      };

      trackpad = {
        Clicking = true;
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = true;
      };

      screensaver.askForPasswordDelay = 10;
    };

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };
    activationScripts.applications.text = let
      env = pkgs.buildEnv {
        name = "system-applications";
        paths = config.environment.systemPackages;
        pathsToLink = [ "/Applications" ];
      };
    in
      pkgs.lib.mkForce ''
      # Set up applications.
      echo "setting up /Applications..." >&2
      rm -rf /Applications/Nix\ Apps
      mkdir -p /Applications/Nix\ Apps
      find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
      while read -r src; do
        app_name=$(basename "$src")
        echo "copying $src" >&2
        ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
      done
          '';
  };

  imports = [
    ./aerospace.nix
    ./sketchybar.nix
    ./jankyborders.nix
  ];
}
