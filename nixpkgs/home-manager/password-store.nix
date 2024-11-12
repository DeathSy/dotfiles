{ pkgs, ... }: {
  programs.gpg = {
    enable = true;
  };
  programs.password-store = {
    enable = true;
  };
}
