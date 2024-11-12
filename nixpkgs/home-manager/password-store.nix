{ pkgs, config, ... }: {
  programs.gpg = {
    enable = true;
  };
  programs.password-store = {
    enable = true;
    settings = {
      PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
      PASSWORD_STORE_KEY = "A64CB287167F83C3AEC36236C00D9E4BD62E3739";
    };
  };
}
