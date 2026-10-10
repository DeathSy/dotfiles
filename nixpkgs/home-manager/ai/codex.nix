{ config, lib, pkgs, ... }:

let
  cfg = config.dotfiles.ai;

  # Codex rewrites ~/.codex/config.toml itself, so deep-merge the managed keys
  # into the live file (tomlkit keeps its layout) instead of linking it.
  codexMerge = pkgs.writers.writePython3Bin "codex-config-merge" {
    libraries = [ pkgs.python3Packages.tomlkit ];
    flakeIgnore = [ "E501" ];
  } ''
    import os
    import shutil
    import sys
    import tempfile
    import time
    import tomlkit

    home = os.environ["HOME"]
    target = os.path.join(home, ".codex", "config.toml")
    sources = sys.argv[1:]


    def merge(dst, src):
        for key, value in src.items():
            if key in dst and isinstance(dst[key], dict) and isinstance(value, dict):
                merge(dst[key], value)
            else:
                dst[key] = value


    try:
        before = open(target).read() if os.path.exists(target) else ""
        doc = tomlkit.parse(before)
        for path in sources:
            merge(doc, tomlkit.parse(open(path).read()))
        after = tomlkit.dumps(doc)
    except Exception as e:
        sys.exit(f"codex-config-merge: {e}; {target} left unchanged")

    if after == before:
        sys.exit(0)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if before:
        backups = os.path.join(home, ".codex", "backups")
        os.makedirs(backups, exist_ok=True)
        shutil.copy2(target, os.path.join(backups, "config.toml.dotfiles-" + time.strftime("%Y%m%d-%H%M%S")))
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target))
    with os.fdopen(fd, "w") as f:
        f.write(after)
    if before:
        shutil.copymode(target, tmp)
    os.replace(tmp, target)
    print(f"codex-config-merge: updated {target}")
  '';

  overlay = (pkgs.formats.toml { }).generate "codex-overlay.toml" (lib.recursiveUpdate cfg.codex.settings
    (lib.optionalAttrs (cfg.codex.trustedProjects != [ ]) {
      projects = lib.genAttrs cfg.codex.trustedProjects (_: { trust_level = "trusted"; });
    }));
  sources = [ ../../../codex/config.base.toml overlay ];
in
{
  home.packages = [ (pkgs.writeShellScriptBin "codex-config-sync" ''
    exec ${codexMerge}/bin/codex-config-merge ${lib.escapeShellArgs (map toString sources)}
  '') ];

  home.activation.codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [[ -v DRY_RUN ]]; then
      echo "Would merge ~/.codex/config.toml"
    else
      ${codexMerge}/bin/codex-config-merge ${lib.escapeShellArgs (map toString sources)} \
        || warnEcho "codex config merge skipped (see above)"
    fi
  '';
}
