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
- Data and permissions: typing remains local in the Rust engine; only the explicit `Open X compose` click opens an external browser with rounded score and mode. Plugins run unsandboxed. No user config is overwritten by plugin code; local `make install` is a separate opt-in installer that backs up recognized previous Keyritual files and refuses unknown contents.
- Optional preview: do not submit concept mockups as real UI screenshots; add a consent-reviewed actual screenshot if desired.

Known prerelease gaps: the bundled binary is x86_64/glibc-specific; real clean-clone UI, History/Share across display sizes and external-share browser navigation still need broader live validation. No separate release binary asset is provided. The user explicitly accepted these gaps for prerelease submission. Marketplace maintainer approval is separate from the issue and is not a security review.
