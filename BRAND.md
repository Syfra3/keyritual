# Keyritual — visual system v1

**Direction:** terminal discipline meets a fictional keyboard ritual. Based on the user-supplied moodboard; the vectors below are newly drawn interpretations, not pixel-extracted artwork. The occult cues are symbolic and playful, not a real-world affiliation.

## Marks and downloadable vector assets

- [Primary logomark / ritual key](images/keyritual-mark.svg) — concentric orbit and six nodes around a tilted `K` keycap. This is the distinctive mark; use it at 96 px and larger.
- [Compact iconography sheet](images/keyritual-icons.svg) — isolated terminal prompt, angular keycap, orbital seal, and crossed-key monogram. For small sizes use the simpler prompt or keycap, never the detailed seal.
- [Typography and tokens](images/keyritual-type.svg) — the title lockup, brackets, tiny telemetry labels, code-style copy, and the color system.
- [Launch](images/01-launch.svg), [Practice](images/02-practice.svg), [Results](images/03-results.svg) — complete walkthrough, now using the same graphic language.

## System

| Role | Value | Usage |
| --- | --- | --- |
| Void | `#080e13` | Desktop / poster background |
| Surface | `#111d22` | Raised panels |
| Grid | `#223039` | 24 px graph-paper lines, intentionally faint |
| Mint | `#a7e8bc` | Headline, correct text, focus / CTA |
| Chalk | `#d7e2d5` | Body copy |
| Muted | `#779489` | Labels and inactive controls |
| Ember | `#edaa77` | Ritual seal, errors, highlights; never the only error indicator |

**Typography:** uppercase mono display with squared proportions and spacious tracking; ordinary mono for controls, data, and code. SVGs declare `JetBrains Mono`, `IBM Plex Mono`, `DejaVu Sans Mono`, then `monospace` as fallback. These SVGs do not bundle a font, so glyph metrics can differ across machines. For shipping, choose and license a font explicitly or convert only the standalone wordmark to paths. Maintain readable contrast for controls and results in the actual Omarchy theme; the poster palette is a reference, not a fixed override of user themes.

**Graphic grammar:** thin nested frames, 24 px grid, `[ ]` and `>_` as navigation cues, numbered `01 / ...` chapters, small `SYSTEM_...` telemetry, asymmetric mint/ember glow on the large mark. Avoid noisy scanlines in the actual typing area; animations should respect reduced-motion settings.

**Usage:** launch shows a summon console and abbreviated seal; the test becomes a focused typographic panel with subtle corner brackets; results introduce the full seal as a personal-best badge. Tab, Backspace, Escape, and Enter remain plainly labeled. This design is a concept, not a captured implementation.
