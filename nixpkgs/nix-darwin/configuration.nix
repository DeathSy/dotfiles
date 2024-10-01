{ pkgs, ... }: {
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
    ripgrep
    btop
    eza
    wezterm
    awscli2
    tmux
    lazygit
    zoxide
    sesh
    bun
		git-credential-manager
		slack
		raycast
		arc-browser
		sketchybar
		jankyborders
		fzf
    nodejs_22
    corepack_22
    yarn
    pnpm
    bat
    fd
    postman
    ngrok
    atac
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

		onActivation = {
      cleanup = "uninstall";
      upgrade = true;
    };

		taps = [
			"nikitabobko/tap"
		];

    casks = [
      "nikitabobko/tap/aerospace"
      "sf-symbols"
      "runjs"
      "desktoppr"
    ];

    masApps = {

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
        InitialKeyRepeat = 25;
        KeyRepeat = 6;
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
