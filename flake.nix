{
  description = "Garage Configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";

    home-manager = {
	    url = "github:nix-community/home-manager/master";
	    inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
	    url = "github:LnL7/nix-darwin";
	    inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{
			self, nixpkgs, nix-darwin, home-manager
		}: {

    darwinConfigurations."garage" = nix-darwin.lib.darwinSystem {
			system = "aarch64-darwin";

      modules = [
				./nixpkgs/nix-darwin/configuration.nix

				home-manager.darwinModules.home-manager {
					home-manager = {
						useGlobalPkgs = true;
						useUserPackages = true;
						backupFileExtension = "backup";
						users.ksotis.imports = [
							./nixpkgs/home-manager/home.nix
							./nixpkgs/home-manager/direnv.nix
							./nixpkgs/home-manager/git.nix
							./nixpkgs/home-manager/tmux.nix
							./nixpkgs/home-manager/zsh.nix
							./nixpkgs/home-manager/starship.nix
						];
					};

					users.users.ksotis.home = "/Users/ksotis";
				}
      ];
    };

    specialArgs = { inherit inputs; };

		darwinPackages = self.darwinConfigurations."garage".pkgs;
  };
}
