# Preview generator

This private Swift package renders the hero image used by the README and the
DocC article. It is deliberately separate from the library package, so the
preview tooling does not add a public product or an AppKit dependency to
Rork Highlighter.

Run the generator from the repository root.

```sh
make preview
```

The command writes
`Sources/RorkHighlighter/RorkHighlighter.docc/Resources/swift-attributed-output.png`.
The code is parsed and styled by Rork Highlighter before AppKit composes the
editor window.

## Committed inputs

`Sources/PreviewGenerator/Resources/WelcomeView.swift.txt` contains the exact
Swift sample shown in the preview.

`Sources/PreviewGenerator/Resources/Backdrop.png` contains the quiet spatial
background behind the editor. Keeping it separate from the rendered window
makes the code, layout, and highlighted colors reproducible from source.

## Backdrop provenance

The backdrop is the only generated bitmap input. It was created with the
following ImageGen prompt.

```text
Use case: ui-mockup
Asset type: atmospheric background layer for a minimal open-source Swift library README hero
Primary request: Create an extremely restrained, premium Apple-inspired dark spatial gradient that quietly frames one simple code window. The background must support the code rather than attract attention.
Scene/backdrop: deep midnight graphite with one broad, very soft central bloom in muted indigo and cool violet, plus an almost imperceptible warm edge glow. Fine natural grain and subtle depth only.
Composition/framing: wide 2.16:1 landscape composition with calm negative space across the center and gently darkened outer edges.
Lighting/mood: quiet, precise, sophisticated, minimal, and modern.
Constraints: background layer only. No editor window, no UI, no devices, no people, no code, no typography, no text, no symbols, no logos, and no watermark.
Avoid: bright aurora ribbons, multiple focal points, neon cyberpunk colors, geometric grids, decorative particles, excessive saturation, or dramatic lens effects.
```
