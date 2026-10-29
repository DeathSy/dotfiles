# Raycast

Raycast keeps its settings in an encrypted database tied to this Mac's
Keychain, so they can't be copied or symlinked; they live here as an export.

- Export: run the `Export Settings & Data` command in Raycast and save the file
  as `settings.rayconfig` in this folder. Raycast requires a password (8+
  characters) and encrypts the file with it, so it's safe in this public repo;
  keep the password out of the repo.
- Import (garage only, where `nixpkgs/home-manager/raycast.nix` is imported):
  open Raycast once on garage (for example, after a fresh install) and finish
  its onboarding, then run
  `rebuild`; that opens the file in Raycast once, and you enter the password to
  import. To import again later, run
  `open ~/studio/personal/dotfiles/raycast/settings.rayconfig`.
