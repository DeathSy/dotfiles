{ pkgs, config, lib, ... }: {
  environment.systemPackages = with pkgs; [
    # Terminal related
    vim
    neovim
    direnv
    neofetch
    fzf
    bash
    bat
    fd
    mkalias
    lf
    jq
    antigen
    tree
    ripgrep
    btop
    eza
    sketchybar
    jankyborders
    localstack
    ffmpeg

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

    overlays = [ ];
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
      cleanup = "uninstall";
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
    ];

    casks = [
      "sf-symbols"
      "runjs"
      "desktoppr"
      "arc"
      "wezterm"
      "anydesk"
      "ngrok"
      "postman"
      "raycast"
      "karabiner-elements"
    ];
  };

  system = {
    stateVersion = 5;
    
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
        _HIHideMenuBar = false;
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
        pathsToLink = "/Applications";
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
    # ./aerospace.nix
    # ./sketchybar.nix
    # ./jankyborders.nix
  ];
}
