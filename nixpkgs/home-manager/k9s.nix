{ home, config, pkgs, ... }:
let
  k9sSkins = pkgs.fetchurl {
    url = "https://github.com/catppuccin/k9s/archive/main.tar.gz";
    hash = "sha256-uI9g0YYUcX7MO8W6JSV32aZtGFyXwgOK/m9Ljai99/k=";
  };

  extractSkins = pkgs.runCommand "k9s-skins" {} ''
    mkdir -p $out
    tar xz --strip-components=2 -f ${k9sSkins} -C $out k9s-main/dist
  '';
in 
{
  home.file."${config.home.homeDirectory}/Library/Application Support/k9s/skins" = {
    source = "${extractSkins}";
    recursive = true;
  };

	programs.k9s = {
		enable = true;
      settings = {
        k9s = {
          ui = {
            skin = "catppuccin-mocha-transparent";
          };
        };
      };
	};
}
