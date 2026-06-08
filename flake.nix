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
  };

  outputs = inputs@{
			self, nixpkgs, nix-darwin, home-manager
		}: {

    darwinConfigurations."garage" = nix-darwin.lib.darwinSystem {
			system = "aarch64-darwin";

			specialArgs = { inherit inputs; };

      modules = [
				./nixpkgs/nix-darwin/configuration.nix

				home-manager.darwinModules.home-manager {
					home-manager = {
						useGlobalPkgs = true;
						useUserPackages = true;
						backupFileExtension = "backup";
						users.ksotis.imports = [
							./nixpkgs/home-manager/direnv.nix
							./nixpkgs/home-manager/git.nix
							./nixpkgs/home-manager/home.nix
							./nixpkgs/home-manager/k9s.nix
							./nixpkgs/home-manager/password-store.nix
							./nixpkgs/home-manager/starship.nix
							./nixpkgs/home-manager/zsh.nix
							./nixpkgs/home-manager/tmux.nix
						];
					};

					users.users.ksotis.home = "/Users/ksotis";
				}
      ];
    };

		darwinPackages = self.darwinConfigurations."garage".pkgs;
  };
}
