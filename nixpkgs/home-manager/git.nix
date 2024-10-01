{ pkgs, ... }: {

	programs.git = {
		enable = true;
		userName = "DeathSy";
		userEmail = "ks.srikittichai@gmail.com";
		lfs.enable = true;
		extraConfig = {
			init = { defaultBranch = "main"; };
			push = { autoSetupRemote = true; };
		};
	};
}
