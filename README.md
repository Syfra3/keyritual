<div align="center">
  <img src="assets/keyritual-header.png" alt="Keyritual — daily practice and steady improvement" width="100%"/>
</div>

# Keyritual

**A native typing-practice concept for Omarchy.** Build a steady rhythm, learn from mistakes, and make daily practice feel like a small terminal ritual.

> **Status: design and implementation plan.** The images below are concept mockups. There is no installable plugin or Rust binary in this repository yet. The planned Omarchy integration targets **Quattro / 4.x**; the design machine runs Omarchy 3.8.5, which does not provide the required plugin shell.

## The ritual

1. **Summon** a focused, theme-aware typing surface from Omarchy.
2. **Practice** in timed or word-count mode with immediate character feedback, corrections, and an unobtrusive live score.
3. **Reflect** on WPM, accuracy, consistency, missed keys, and local personal bests.

| Summon | Practice | Reflect |
| :---: | :---: | :---: |
| <img src="images/01-launch.png" alt="Keyritual launch concept" width="400"/> | <img src="images/02-practice.png" alt="Keyritual typing concept" width="400"/> | <img src="images/03-results.png" alt="Keyritual results concept" width="400"/> |

## Brand kit

The visual language pairs a dark graph-paper grid and bracketed terminal typography with a mint-and-ember **ritual key**. The logo and icons are original vector interpretations of the supplied visual reference; they are not an exact trace. The eventual app should respect the active Omarchy theme rather than forcing the poster palette.

| Logomark | Iconography | Typography and palette |
| :---: | :---: | :---: |
| <img src="images/keyritual-mark.png" alt="Orbital K keycap logomark" width="210"/> | <img src="images/keyritual-icons.png" alt="Keyritual iconography" width="300"/> | <img src="images/keyritual-type.png" alt="Keyritual wordmark and palette" width="300"/> |

Editable SVGs and PNG previews live in [`images/`](images/). See [BRAND.md](BRAND.md) for tokens, typography, icon usage, and accessibility notes.

## Planned implementation

- **Rust core:** prompt generation, timing, deterministic session state, scoring, settings, and bounded local history.
- **Omarchy shell overlay:** a QML surface for focus, key input, layout, and active theme tokens. It will communicate with one Rust process using newline-delimited JSON, rather than launching a process per keystroke.
- **Local by default:** no Monkeytype account, network dependency, or global keystroke capture.
- **Distribution:** one Quattro plugin manifest at the repo root, a documented Rust binary prerequisite, and validation with `omarchy plugin validate .` once implemented on Omarchy 4.x.

The feature sequence and acceptance checks are in [PLAN.md](PLAN.md). The proposed plugin ID is `io.github.syfra3.keyritual`. **There is no manifest or installable plugin yet**, so the commands in the plan are future examples.

## Inspiration and references

- [OmaType](https://github.com/jamesd7788/omatype) demonstrates an Omarchy-native typing surface. Keyritual aims for a larger, more forgiving practice experience.
- [Raycast's Monkeytype extension](https://github.com/raycast/extensions/tree/2b7f8341a1500ec36b9b3ff7b0cc1079f11d989d/extensions/monkeytype/) opens Monkeytype web pages; it is not a local typing engine.
- [Omarchy Quattro shell plugin guide](https://github.com/omacom/omarchy/blob/quattro/manual/32-shell-plugins.md) and [plugin marketplace](https://plugins.omarchy.org/).

## License

[MIT](LICENSE) for the repository's original documentation and artwork. Third-party projects linked above keep their own licenses.
