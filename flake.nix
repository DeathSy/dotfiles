{
  description = "Garage Configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
	    url = "git+https://github.com/nix-community/home-manager?ref=master&shallow=1";
	    inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
	    url = "github:nix-darwin/nix-darwin/master";
	    inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hermes Agent (garage-hq only, nixpkgs/home-manager/ai/hermes.nix). Pinned
    # to a release tag with its own nixpkgs: Nix is a best-effort platform
    # upstream, so we build exactly what that release locked. Used through
    # `hermesAgent` below, which applies our local patches.
    hermes-agent.url = "github:NousResearch/hermes-agent/v0.23.3";

    # Private data layer (project paths, internal URLs; no logic). Defaults
    # to an empty module; `rebuild` overrides it with the private checkout.
    private = {
	    url = "path:./private-stub";
	    flake = false;
    };
  };

  outputs = inputs@{
			self, nixpkgs, nix-darwin, home-manager, private, hermes-agent, ...
		}: let
    # hermes-agent v0.23.3 with upstream PR #150967 applied (still open): on
    # macOS pnpm leaves an empty v11/links directory in the dependency store,
    # so the pnpm-deps fixed-output hash differs from Linux's and the build
    # fails (issue #150713). Drop the patch once a release includes the fix.
    hermesAgent = let
      src = nixpkgs.legacyPackages.aarch64-darwin.applyPatches {
        name = "hermes-agent-v0.23.3-patched";
        src = hermes-agent;
        patches = [ ./nixpkgs/home-manager/ai/hermes-pnpm-macos.patch ];
      };
      outputs = (import "${src}/flake.nix").outputs (hermes-agent.inputs // { self = flake; });
      flake = outputs // hermes-agent.sourceInfo // {
        _type = "flake";
        outPath = "${src}";
        inherit (hermes-agent) inputs;
        inherit outputs;
      };
    in flake;

    # The shared modules below are the global layer every Mac gets;
    # nixpkgs/hosts/<hostName>.nix adds that device's names and extra apps.
    mkHost = hostName: nix-darwin.lib.darwinSystem {
			system = "aarch64-darwin";

			specialArgs = { inputs = inputs // { hermes-agent = hermesAgent; }; };

      modules = [
				{ networking = { inherit hostName; }; }
				./nixpkgs/nix-darwin/desktop-extras.nix
				./nixpkgs/nix-darwin/configuration.nix
				./nixpkgs/nix-darwin/macos.nix
				./nixpkgs/nix-darwin/vorssaint.nix
				./nixpkgs/nix-darwin/hotkeys.nix
				./nixpkgs/hosts/${hostName}.nix

				home-manager.darwinModules.home-manager {
					home-manager = {
						useGlobalPkgs = true;
						useUserPackages = true;
						backupFileExtension = "backup";
						users.ksotis.imports = [
							./nixpkgs/home-manager/direnv.nix
							./nixpkgs/home-manager/git.nix
							./nixpkgs/home-manager/home.nix
							./nixpkgs/home-manager/desktop.nix
							./nixpkgs/home-manager/hammerspoon.nix
							./nixpkgs/home-manager/node-globals.nix
							./nixpkgs/home-manager/k9s.nix
							./nixpkgs/home-manager/password-store.nix
							./nixpkgs/home-manager/starship.nix
							./nixpkgs/home-manager/zsh.nix
							./nixpkgs/home-manager/tmux.nix
							./nixpkgs/home-manager/ai
							private.outPath
						];
					};

					users.users.ksotis.home = "/Users/ksotis";
				}
      ];
    };
  in {

    # One entry per device, each with a nixpkgs/hosts/<name>.nix. darwin-rebuild
    # picks the host by LocalHostName, which networking.hostName sets.
    darwinConfigurations = nixpkgs.lib.genAttrs [
      "garage"
      "garage-server"
      "garage-hq"
    ] mkHost;

		darwinPackages = self.darwinConfigurations."garage".pkgs;
  };
}
