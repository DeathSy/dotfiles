{ lib, ... }:
let
  # Global npm tools installed into nvm's Node 22.
  packages = [ "pnpm" "yarn" "vercel" "@mermaid-js/mermaid-cli" "depcheck" "clawdhub" "marked" ];
in {
  home.activation.node-globals = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    (
      # HM enables nounset; nvm is not safe under it. Keep this local.
      set +u
      export NVM_DIR="$HOME/.nvm"
      if [ ! -s /opt/homebrew/opt/nvm/nvm.sh ]; then
        echo "node-globals: nvm.sh missing; skipping" >&2
      elif ! . /opt/homebrew/opt/nvm/nvm.sh --no-use; then
        echo "node-globals: loading nvm failed" >&2
      else
        if [ "$(nvm version 22)" = "N/A" ]; then
          run nvm install 22 || echo "node-globals: Node 22 install failed" >&2
          run nvm alias default 22 || echo "node-globals: default alias failed" >&2
        fi
        if nvm use 22; then
          for package in ${lib.escapeShellArgs packages}; do
            if ! npm ls -g --depth=0 "$package" >/dev/null 2>&1; then
              run npm install -g "$package" || echo "node-globals: $package install failed" >&2
            fi
          done
        else
          echo "node-globals: selecting Node 22 failed; skipping tools" >&2
        fi
      fi
    )
  '';
}
