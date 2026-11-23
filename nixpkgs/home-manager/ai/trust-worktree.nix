{ lib, pkgs, ... }:

# ai-trust-worktree: pre-trusts a fresh git worktree for Codex and agy (both
# trust exact paths only), so workers started there skip the trust screen.
{
  home.packages = [ (pkgs.writeShellScriptBin "ai-trust-worktree" ''
    PATH=${lib.makeBinPath [ pkgs.git ]}:$PATH
    exec ${pkgs.python3.withPackages (ps: [ ps.tomlkit ])}/bin/python3 -I ${./ai-trust-worktree.py} "$@"
  '') ];
}
