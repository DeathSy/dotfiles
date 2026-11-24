{ pkgs, ... }:

# hc-worker: start an hc worker in the current Herdr app tab and arrange panes
# as 70% session (left) / 30% stacked workers (right).
{
  home.packages = [ (pkgs.writeShellScriptBin "hc-worker" ''
    exec ${pkgs.python3}/bin/python3 -I ${./hc-worker.py} "$@"
  '') ];
}
