# Tiny background app ("URL Catcher") set as the default http/https/HTML
# handler on headless hosts (garage-hq) so CLI `open` calls don't launch Safari.
# Logs caught URLs to ~/Library/Logs/url-catcher.log, posts a notification, and
# quits after a few idle seconds. macOS asks once at the console to confirm the
# default-browser change.
{ config, lib, pkgs, ... }:
let
  bundleId = "dev.ksotis.url-catcher";

  infoPlist = pkgs.writeText "Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDisplayName</key>
      <string>URL Catcher</string>
      <key>CFBundleDocumentTypes</key>
      <array>
        <dict>
          <key>CFBundleTypeName</key>
          <string>HTML Document</string>
          <key>CFBundleTypeRole</key>
          <string>Viewer</string>
          <key>LSItemContentTypes</key>
          <array>
            <string>public.html</string>
          </array>
        </dict>
      </array>
      <key>CFBundleExecutable</key>
      <string>url-catcher</string>
      <key>CFBundleIdentifier</key>
      <string>${bundleId}</string>
      <key>CFBundleName</key>
      <string>URL Catcher</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0</string>
      <key>CFBundleURLTypes</key>
      <array>
        <dict>
          <key>CFBundleURLName</key>
          <string>Web URL</string>
          <key>CFBundleURLSchemes</key>
          <array>
            <string>http</string>
            <string>https</string>
          </array>
        </dict>
      </array>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>LSUIElement</key>
      <true/>
    </dict>
    </plist>
  '';

  app = pkgs.runCommandCC "url-catcher" { } ''
    bundle="$out/Applications/URL Catcher.app"
    mkdir -p "$bundle/Contents/MacOS"
    # The arm64 linker ad-hoc signs the binary automatically (pure/sandbox-safe).
    "$CC" -fobjc-arc -O2 -Wall -Wextra \
      -framework Cocoa \
      ${./url-catcher.m} \
      -o "$bundle/Contents/MacOS/url-catcher"
    cp ${infoPlist} "$bundle/Contents/Info.plist"
  '';
in {
  dotfiles.desktop.browser = bundleId;

  # Copy a real bundle into ~/Applications (Launch Services handles a copy
  # better than a Nix store symlink) and register it before desktop.nix runs
  # duti to point http, https and public.html at it.
  home.activation.url-catcher = lib.hm.dag.entryBetween [ "default-apps" ] [ "writeBoundary" ] ''
    src="${app}/Applications/URL Catcher.app"
    dst="${config.home.homeDirectory}/Applications/URL Catcher.app"
    if [ ! -d "$dst" ] || ! /usr/bin/diff -rq "$src" "$dst" >/dev/null 2>&1; then
      run mkdir -p "${config.home.homeDirectory}/Applications"
      run rm -rf "$dst"
      run cp -R "$src" "$dst"
      run chmod -R u+w "$dst"
    fi
    run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dst" || true
  '';
}
