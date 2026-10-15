# Raycast

Raycast keeps its settings in an encrypted database, so they live here as an
export rather than a config file.

- Export: Raycast → Settings → Advanced → Export, with a password, saved as
  `settings.rayconfig` in this folder. The password encrypts the file; don't
  export without one, since extension preferences can hold API tokens.
- Import: open Raycast once on the new Mac and finish its onboarding, then run
  `rebuild`; that opens the file in Raycast once, and you enter the password to
  import. To import again later, run
  `open ~/studio/personal/dotfiles/raycast/settings.rayconfig`.
