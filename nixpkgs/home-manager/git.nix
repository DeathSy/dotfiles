{ pkgs, ... }: {

	programs.git = {
		enable = true;
		lfs.enable = true;
		settings = {
			user = {
				name = "DeathSy";
				email = "ks.srikittichai@gmail.com";
			};
			init = { defaultBranch = "main"; };
			push = { autoSetupRemote = true; };
		};
	};
}
