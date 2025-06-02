{ config, lib, pkgs, ... } :
{
  services.aerospace = {
    enable = true;

    settings = {
      # After login and startup commands
      after-login-command = [];
      after-startup-command = [
        "exec-and-forget borders style=round hidpi=off active_color=0xc0e2e2e3 inactive_color=0xc02c2e34 background_color=0x302c2e34 width=6.0"
        "exec-and-forget ${pkgs.sketchybar}/bin/sketchybar"
      ];

      # Sketchybar integration
      exec-on-workspace-change = [
        "/bin/bash"
        "-c"
        "${pkgs.sketchybar}/bin/sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE"
      ];

      # Normalization settings
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;

      # Layouts
      accordion-padding = 10;
      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";

      # Key mapping
      key-mapping.preset = "qwerty";

      # Focus behavior
      on-focused-monitor-changed = ["move-mouse monitor-lazy-center"];
      "on-focus-changed" = ["move-mouse window-lazy-center"];

      # Gaps configuration
      gaps = {
        inner = {
          horizontal = 12;
          vertical = 12;
        };
        outer = {
          left = 12;
          bottom = 12;
          top = [
            { monitor.built-in = 15; }
            42
          ];
          right = 12;
        };
      };

      # Main mode bindings
      mode.main.binding = {
        # Disable annoying macOS hide window
        "cmd-h" = [];
        "cmd-alt-h" = [];
        "cmd-m" = [];

        # Layout controls
        "alt-slash" = "layout tiles horizontal vertical";
        "alt-comma" = "layout accordion horizontal vertical";

        # Focus controls
        "alt-h" = "focus left";
        "alt-j" = "focus down";
        "alt-k" = "focus up";
        "alt-l" = "focus right";

        # Move controls
        "alt-shift-h" = "move left";
        "alt-shift-j" = "move down";
        "alt-shift-k" = "move up";
        "alt-shift-l" = "move right";

        # Resize controls
        "alt-shift-minus" = "resize smart -50";
        "alt-shift-equal" = "resize smart +50";

        # Workspace controls
        "alt-1" = "workspace 1";
        "alt-a" = "workspace A";
        "alt-c" = "workspace C";
        "alt-d" = "workspace D";
        "alt-n" = "workspace N";
        "alt-s" = "workspace S";
        "alt-w" = "workspace W";
        "alt-p" = "workspace P";
        "alt-t" = "workspace T";
        "alt-x" = "workspace X";

        # Move to workspace
        "alt-shift-1" = "move-node-to-workspace 1";
        "alt-shift-a" = "move-node-to-workspace A";
        "alt-shift-c" = "move-node-to-workspace C";
        "alt-shift-d" = "move-node-to-workspace D";
        "alt-shift-n" = "move-node-to-workspace N";
        "alt-shift-s" = "move-node-to-workspace S";
        "alt-shift-w" = "move-node-to-workspace W";
        "alt-shift-p" = "move-node-to-workspace P";
        "alt-shift-t" = "move-node-to-workspace T";
        "alt-shift-x" = "move-node-to-workspace X";

        # Fullscreen
        "ctrl-alt-enter" = "fullscreen";

        # Monitor controls
        "alt-shift-tab" = "move-workspace-to-monitor --wrap-around next";
        "alt-ctrl-l" = "focus-monitor next";
        "alt-ctrl-h" = "focus-monitor prev";

        # Mode switch
        "alt-shift-semicolon" = "mode service";
      };

      # Service mode bindings
      mode.service.binding = {
        "esc" = ["reload-config" "mode main"];
        "r" = ["flatten-workspace-tree" "mode main"];
        "f" = ["layout floating tiling" "mode main"];
        "backspace" = ["close-all-windows-but-current" "mode main"];
        
        "alt-shift-h" = ["join-with left" "mode main"];
        "alt-shift-j" = ["join-with down" "mode main"];
        "alt-shift-k" = ["join-with up" "mode main"];
        "alt-shift-l" = ["join-with right" "mode main"];
      };
      
      # Window rules (convert on-window-detected to rules format)
      on-window-detected = [
        {
          "if".app-id = "com.linear";
          run = "move-node-to-workspace 1";
        }
        {
          "if".app-id = "company.thebrowser.Browser";
          run = "move-node-to-workspace A";
        }
        {
          "if".app-id = "notion.id";
          run = "move-node-to-workspace C";
        }
        {
          "if".app-id = "com.cron.electron";
          run = "move-node-to-workspace C";
        }
        {
          "if".app-id = "notion.id";
          run = "move-node-to-workspace C";
        }
        {
          "if".app-id = "notion.mail.id";
          run = "move-node-to-workspace C";
        }
        {
          "if".app-id = "com.tinyapp.TablePlus";
          run = "move-node-to-workspace D";
        }
        {
          "if".app-id = "com.postmanlabs.mac";
          run = "move-node-to-workspace P";
        }
        {
          "if".app-id = "com.tinyspeck.slackmacgap";
          run = "move-node-to-workspace S";
        }
        {
          "if".app-id = "com.apple.MobileSMS";
          run = "move-node-to-workspace S";
        }
        {
          "if".app-id = "com.hnc.Discord";
          run = "move-node-to-workspace S";
        }
        {
          "if".app-id = "jp.naver.line.mac";
          run = "move-node-to-workspace X";
        }
        {
          "if".app-id = "net.whatsapp.WhatsApp";
          run = "move-node-to-workspace X";
        }
        {
          "if".app-id = "com.microsoft.teams2";
          run = "move-node-to-workspace T";
        }
        {
          "if".app-id = "com.github.wez.wezterm";
          run = "move-node-to-workspace W";
        }

        ## Floating application
        {
          "if".app-id = "com.raycast.macos";
          run = "layout floating";
        }
      ];
    };
  };
}
