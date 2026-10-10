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

    backups = os.path.join(home, ".codex", "backups")


    def tidy_backups():  # mode 600, keep the latest 5
        if not os.path.isdir(backups):
            return
        old = [os.path.join(backups, f) for f in os.listdir(backups) if f.startswith("config.toml.dotfiles-")]
        old.sort(key=os.path.getmtime, reverse=True)
        for i, path in enumerate(old):
            if i < 5:
                os.chmod(path, 0o600)
            else:
                os.remove(path)


    if after == before:
        tidy_backups()
        sys.exit(0)
    try:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if before:
            os.makedirs(backups, mode=0o700, exist_ok=True)
            fd, _ = tempfile.mkstemp(prefix="config.toml.dotfiles-" + time.strftime("%Y%m%d-%H%M%S") + ".", dir=backups)
            with os.fdopen(fd, "w") as f:
                f.write(before)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target))
        with os.fdopen(fd, "w") as f:
            f.write(after)
        if before:
            shutil.copymode(target, tmp)
        os.replace(tmp, target)
    except Exception as e:
        sys.exit(f"codex-config-merge: {e}; {target} left unchanged")
    tidy_backups()
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
