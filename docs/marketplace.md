# Omarchy Plugins submission metadata

- Repository: https://github.com/Syfra3/keyritual
- Category: Productivity
- Tags: Education, Quickshell
- Plugin ID: `io.github.syfra3.keyritual`
- Description: Local typing-practice overlay with timed/word tests, pace charts and session history.
- License: MIT for the repository's original code and artwork; the provider of the supplied seal image confirmed permission to publish and license it with Keyritual.
- Dependencies: Omarchy Quattro/4.x on x86_64 Linux with compatible glibc. The Rust engine is bundled as an executable at `bin/keyritual-core`. No separate Cargo step or privileged install hook is used by `omarchy plugin add`.
- Install: `omarchy plugin add https://github.com/Syfra3/keyritual.git --enable`
- Launch: `omarchy-shell shell toggle io.github.syfra3.keyritual '{}'`; marketplace installation does not add an app-list shortcut.
- Remove: `omarchy plugin remove io.github.syfra3.keyritual`; session history remains at `${XDG_STATE_HOME:-$HOME/.local/state}/keyritual/history.json` unless the user separately chooses to delete it.
- Data and permissions: typing remains local in the Rust engine; only the explicit `Open X compose` click opens an external browser with rounded score and mode. Plugins run unsandboxed. Marketplace `plugin add` does not run scripts or change Hyprland. On first open, an explicit Yes choice can run the bundled optional hotkey script to back up and append one non-conflicting Super+Shift+K binding under the user's Hyprland config; No does not invoke it. Local `make install` is a separate opt-in installer that backs up recognized previous Keyritual plugin files and refuses unknown contents.
- Root preview: `preview.png` is a cropped real Reflect-screen capture; `images/practice-live.png` and `images/reflect-live.png` show real UI. Concept images remain clearly labeled separately.

v0.1.0 stable source-release limitations: the bundled binary is x86_64/glibc-specific; current Quickshell pointer/keyboard controls and narrow-viewport behavior, clean-clone UI, History/Share across display sizes, external-share browser navigation, and the first-open shortcut effect against real user configuration remain unverified live. No separate release binary asset or marketplace submission is part of this preparation. Marketplace maintainer approval is separate and is not a security review. See [release notes](releases/v0.1.0.md).
