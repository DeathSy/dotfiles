# macOS system settings, captured from the live machine so a fresh Mac
# comes up identical after the first switch.
{ config, ... }:
let
  user = config.system.primaryUser;
  home = "/Users/${user}";
in {
  networking = {
    computerName = "ksotis";
    # Also sets LocalHostName; matches darwinConfigurations."garage".
    hostName = "garage";

    applicationFirewall = {
      enable = true;
      enableStealthMode = true;
    };
  };

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  system.defaults = {
    dock = {
      autohide = true;
      mru-spaces = false;
      show-recents = false;
      tilesize = 32;
      expose-group-apps = false;
      showMissionControlGestureEnabled = true;
      # Bottom-right hot corner: Quick Note.
      wvous-br-corner = 14;
      persistent-apps = [
        "/System/Applications/Apps.app"
        "/Applications/Safari.app"
        "/System/Applications/Mail.app"
        "/System/Applications/Maps.app"
        "/System/Applications/Photos.app"
        "/System/Applications/Notes.app"
        "/System/Applications/Music.app"
        "/System/Applications/App Store.app"
        "/System/Applications/Siri AI.app"
        "/System/Applications/System Settings.app"
      ];
      persistent-others = [
        {
          folder = {
            path = "${home}/Downloads";
            arrangement = "date-added";
            displayas = "stack";
            showas = "fan";
          };
        }
      ];
    };

    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      AppleIconAppearanceTheme = "RegularDark";
      AppleShowAllExtensions = true;
      AppleEnableSwipeNavigateWithScrolls = false;
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 10;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      NSTableViewDefaultSizeMode = 2;
      _HIHideMenuBar = false;
      "com.apple.mouse.tapBehavior" = 1;
      "com.apple.swipescrolldirection" = true;
      "com.apple.trackpad.forceClick" = true;
      "com.apple.springing.enabled" = true;
      "com.apple.springing.delay" = 0.5;
    };

    WindowManager = {
      GloballyEnabled = false;
      AutoHide = false;
      AppWindowGroupingBehavior = true;
      EnableStandardClickToShowDesktop = false;
      EnableTilingByEdgeDrag = false;
      EnableTopTilingByEdgeDrag = false;
      EnableTilingOptionAccelerator = false;
      EnableTiledWindowMargins = false;
      HideDesktop = false;
      StageManagerHideWidgets = false;
      StandardHideWidgets = false;
    };

    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      ShowPathbar = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv";
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = false;
      ShowRemovableMediaOnDesktop = true;
    };

    trackpad = {
      Clicking = true;
      Dragging = false;
      DragLock = false;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
      TrackpadCornerSecondaryClick = 0;
      ActuateDetents = true;
      ForceSuppressed = false;
      FirstClickThreshold = 1;
      SecondClickThreshold = 1;
      TrackpadMomentumScroll = true;
      TrackpadPinch = true;
      TrackpadRotate = true;
      TrackpadTwoFingerDoubleTapGesture = true;
      TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
      TrackpadThreeFingerTapGesture = 0;
      TrackpadThreeFingerHorizSwipeGesture = 2;
      TrackpadThreeFingerVertSwipeGesture = 2;
      TrackpadFourFingerHorizSwipeGesture = 2;
      TrackpadFourFingerVertSwipeGesture = 2;
      TrackpadFourFingerPinchGesture = 2;
    };

    menuExtraClock = {
      ShowDate = 1;
      ShowDayOfWeek = true;
      ShowAMPM = true;
      ShowSeconds = true;
      IsAnalog = false;
      FlashDateSeparators = false;
    };

    screencapture = {
      location = "${home}/Pictures/screenshots";
      target = "file";
    };

    screensaver.askForPasswordDelay = 10;
    spaces.spans-displays = false;
    hitoolbox.AppleFnUsageType = "Do Nothing";
    ActivityMonitor.ShowCategory = 100;
    iCal.CalendarSidebarShown = false;

    loginwindow = {
      GuestEnabled = false;
      LoginwindowText = "KSOTIS Garage";
    };

    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

    # Settings nix-darwin has no typed option for.
    CustomUserPreferences = {
      NSGlobalDomain = {
        AppleLanguages = [ "en-TH" "th-TH" ];
        AppleLocale = "en_TH";
        AppleMenuBarVisibleInFullscreen = false;
        AppleMiniaturizeOnDoubleClick = false;
      };
      # Menu bar items: "Visible" = shown in the menu bar, "VisibleCC" = shown in Control Center.
      "com.apple.controlcenter" = {
        "NSStatusItem Visible BentoBox" = true;
        "NSStatusItem Visible Item-0" = false;
        "NSStatusItem Visible Item-1" = false;
        "NSStatusItem Visible Item-10" = false;
        "NSStatusItem Visible Item-2" = false;
        "NSStatusItem Visible Item-3" = false;
        "NSStatusItem Visible Item-4" = false;
        "NSStatusItem Visible Item-5" = false;
        "NSStatusItem Visible Item-6" = false;
        "NSStatusItem Visible Item-7" = false;
        "NSStatusItem Visible Item-8" = false;
        "NSStatusItem Visible Item-9" = false;
        "NSStatusItem Visible Shortcuts" = false;
        "NSStatusItem VisibleCC Battery" = true;
        "NSStatusItem VisibleCC BentoBox-0" = true;
        "NSStatusItem VisibleCC Clock" = true;
        "NSStatusItem VisibleCC WiFi" = true;
      };
      "com.apple.Spotlight" = {
        "NSStatusItem VisibleCC Item-0" = true;
      };
      "com.apple.TextInputMenuAgent" = {
        "NSStatusItem VisibleCC Item-0" = true;
      };
      "com.apple.Passwords" = {
        "showMenuBarExtra" = false;
      };
      # Input sources: ABC + Thai. Takes effect after the next login.
      "com.apple.HIToolbox" = {
        AppleEnabledInputSources = [
          { InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = 252; "KeyboardLayout Name" = "ABC"; }
          { InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = -26624; "KeyboardLayout Name" = "Thai"; }
          { InputSourceKind = "Non Keyboard Input Method"; "Bundle ID" = "com.apple.CharacterPaletteIM"; }
          { InputSourceKind = "Non Keyboard Input Method"; "Bundle ID" = "com.apple.PressAndHold"; }
          { InputSourceKind = "Non Keyboard Input Method"; "Bundle ID" = "com.apple.inputmethod.ironwood"; }
        ];
      };
      "com.apple.Siri" = {
        StatusMenuVisible = false;
        VoiceTriggerUserEnabled = false;
      };
    };
  };

  system.activationScripts.postActivation.text = ''
    # screencapture.location points here; macOS falls back to the Desktop
    # when the folder is missing.
    sudo -u ${user} mkdir -p ${home}/Pictures/screenshots

    # Menu bar / Control Center modules, per-host (ByHost) prefs, as set on
    # macOS 27: 8 = hidden; Battery shows the percentage inside the icon.
    for kv in AirDrop=8 Battery=2 BatteryShowEnergyMode=1 BatteryShowPercentage=1 \
      Bluetooth=8 Display=8 FocusModes=8 KeyboardBrightness=8 ShowSuggestions=1 \
      Sound=8 Spotlight=8 Timer=8 VoiceControl=8; do
      launchctl asuser "$(id -u ${user})" sudo -u ${user} defaults -currentHost write com.apple.controlcenter "''${kv%%=*}" -int "''${kv#*=}"
    done
    launchctl asuser "$(id -u ${user})" sudo -u ${user} defaults -currentHost write com.apple.Spotlight MenuItemHidden -bool true

    # Power: display never sleeps; the system never sleeps on AC and sleeps
    # after 1 minute on battery (if present); wake for network access on AC only.
    pmset -c sleep 0 displaysleep 0 disksleep 10 womp 1
    if pmset -g batt | grep -q InternalBattery; then
      pmset -b sleep 1 displaysleep 0 disksleep 10 womp 0
    fi
  '';
}
