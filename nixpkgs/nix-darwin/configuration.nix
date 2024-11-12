{ pkgs, config, ... }: {
  environment.systemPackages = with pkgs; [
    vim
    neovim
    git
    direnv
    neofetch
    go
    antigen
    gh
    gitflow
    git-lfs
    kubectl
    tree
    k9s
    kubectx
    ripgrep
    btop
    eza
    awscli2
    tmux
    lazygit
    zoxide
    bun
    git-credential-manager
    slack
    sketchybar
    jankyborders
    fzf
    bat
    fd
    mkalias
    postman
    raycast
    tableplus
    lf
  ];

  services.nix-daemon.enable = true;
  services.activate-system.enable = true;
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
		(nerdfonts.override { fonts = ["Hack" "FiraCode"]; })
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
      "common-fate/granted"
		];

    brews = [
      "granted"
      "trivy"
    ];

    casks = [
      "nikitabobko/tap/aerospace"
      "sf-symbols"
      "runjs"
      "desktoppr"
      "notion-calendar"
      "firefox"
      "arc"
      "wezterm"
    ];

    masApps = {
      "Things3" = 904280696;
      "Xcode" = 497799835;
      "Pages" = 409201541;
    };
  };

  system = {
    stateVersion = 5;
    
    defaults =  {
      dock = {
        autohide = true;
        mru-spaces = false;
        show-recents = false;
        tilesize = 32;
        expose-group-by-app = true;
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
        pathsToLink = "/Applications";
      };
    in
      pkgs.lib.mkForce ''
      # Set up applications.
      echo "setting up /Applications..." >&2
      rm -rf /Applications/Nix\ Apps
      mkdir -p /Applications/Nix\ Apps
      find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
      while read src; do
        app_name=$(basename "$src")
        echo "copying $src" >&2
        ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
      done
          '';
  };

	services = {
		jankyborders = {
			enable = true;
			style = "round";
			hidpi = false;
			active_color = "0xc0e2e2e3";
			inactive_color = "0xc02c2e34";
			background_color = "0x302c2e34";
			width = 6.0;
		};

		sketchybar.enable = true;
	};
}
