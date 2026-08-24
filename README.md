# Rork Highlighter

Rork Highlighter is a fast, Swift-native syntax-highlighting library powered
by Tree-sitter. It parses source code into immutable semantic spans, preserves
syntax state while a document changes, and lets each application choose how
those results are rendered.

![Rork Highlighter rendering Swift with native attributed output.](Sources/RorkHighlighter/RorkHighlighter.docc/Resources/swift-attributed-output.png)

The preview uses the bundled Swift parser and the Rork Dark theme.

## What it is designed for

Rork Highlighter works well anywhere Swift code needs accurate highlighting:

- Code blocks, previews, diffs, and documentation.
- UIKit and AppKit text views.
- Full editors that need incremental updates while typing.
- SwiftUI views using native `AttributedString`.
- Custom Core Text, Metal, terminal, HTML, and server-side renderers.
- Mobile and web projects that mix languages through Tree-sitter injections.

The library does not ship a text view or take over layout, selection, scrolling,
or editing. It supplies highlighting state and optional rendering helpers, so
an application can use as much or as little of the package as it needs.

## Choose your integration level

| Level | Use it when | Main API |
| --- | --- | --- |
| Framework-agnostic core | You own rendering or need semantic syntax data | `Highlighter`, `HighlightSession`, `HighlightSnapshot` |
| Native attributed output | You need a complete SwiftUI, UIKit, or AppKit value | `attributedString(theme:font:)`, `nsAttributedString(theme:font:)` |
| Incremental TextKit integration | An editable UIKit or AppKit text view owns its storage | `TextKitHighlightRenderer` |
| Custom rendering backend | You want reusable rendering for Metal, Core Text, a terminal, or another target | `HighlightRenderer` |

The framework-agnostic core has no UIKit, AppKit, SwiftUI, or TextKit
dependency. The Apple rendering APIs are conveniences built on top of the same
snapshots, updates, themes, and UTF-16 ranges.

## Requirements

- Swift 6.0 or newer.
- macOS 13 or newer.
- iOS and Mac Catalyst 16 or newer.
- tvOS 16, watchOS 9, or visionOS 1 when those platforms are relevant.

Tree-sitter and the bundled parser pack also build on supported non-Apple Swift
platforms.

## Installation

Add Rork Highlighter to your package:

```swift
.package(
    url: "https://github.com/rorkai/rork-highlighter.git",
    .upToNextMinor(from: "0.3.0")
)
```

Add the library product to your target:

```swift
.product(
    name: "RorkHighlighter",
    package: "rork-highlighter"
)
```

Your application imports one module. The standard catalog and its 36 native
Tree-sitter parsers are managed by the package.

## Quick start

Highlight an immutable source string:

```swift
import RorkHighlighter

let highlighter = try Highlighter()
let source = #"let greeting = "Hello, code!""#
let snapshot = try highlighter.highlight(
    source,
    as: .swift
)
```

`snapshot.text` contains the original source. `snapshot.highlights` contains
ordered `HighlightSpan` values with Tree-sitter capture scopes and
Foundation-compatible UTF-16 ranges.

Use a file URL when the language should be discovered from its filename or
extension:

```swift
import Foundation
import RorkHighlighter

let source = #"let greeting = "Hello, code!""#
let snapshot = try Highlighter().highlight(
    source,
    for: URL(fileURLWithPath: "/tmp/WelcomeView.swift")
)
```

## Framework-agnostic core

The core API returns data rather than drawing into a particular framework.
Resolve the snapshot through a theme and pass its typed values into any
rendering pipeline:

```swift
let styledHighlights = snapshot.styledHighlights(using: .rorkDark)
```

Each `StyledHighlight` retains its semantic `span`, exposes its UTF-16 `range`,
and carries its resolved `style`. Values remain in capture order because later
overlapping captures can refine broader styles. Every styling value is
immutable, `Sendable`, and renderer neutral.

### Incremental documents

Create one actor-isolated session for each changing document:

```swift
import RorkHighlighter

let source = #"let greeting = "Hello, code!""#
let highlighter = try Highlighter()
let session = try highlighter.makeSession(source, as: .swift)

let update = try await session.replaceCharacters(
    in: UTF16Range(location: 23, length: 4),
    with: "Rork"
)

let renderingRanges = update.renderingRanges
```

The session edits the existing Tree-sitter syntax tree, so parsing stays
incremental, and it queries the complete document so its captures always
match a one-shot highlight of the same text. `update.invalidatedRanges`
covers every capture that changed, and `update.snapshot` still contains the
complete latest state when a backend prefers simple full rendering.

Apply the same edit to your own text model before rendering the matching update.
Keep revisions in order when coordinating edits from another versioned buffer.

Streaming clients can read `snapshot.stableUTF16Length` to learn how much of
the leading source parses without end-of-input recovery. Captures before that
boundary match one-shot highlighting of the same text, while the trailing
region remains speculative until more source arrives.

### Custom rendering backends

`HighlightRenderer` defines a small typed contract for complete snapshots and
incremental updates. A backend chooses its own target, error type, configuration,
and caches. Implementing complete rendering is enough to begin because the
default update path renders the latest complete snapshot.

An optimized backend can implement update rendering and use `renderingRanges`
to touch only affected regions. The protocol does not prescribe layout,
drawing, font objects, or storage ownership.

See [Building Rendering Backends](Sources/RorkHighlighter/RorkHighlighter.docc/RenderingBackends.md)
for a complete implementation.

## Native attributed output

Native output is optional. It converts a complete snapshot into a value that
SwiftUI, UIKit, or AppKit already understands.

### SwiftUI

```swift
import RorkHighlighter
import SwiftUI

let source = #"""
import SwiftUI

struct WelcomeView: View {
    var body: some View {
        Text("Hello, Rork!")
    }
}
"""#

let snapshot = try Highlighter().highlight(source, as: .swift)
let rendered = try snapshot.attributedString(
    theme: .rorkDark,
    font: .system(size: 15, design: .monospaced)
)

let code = Text(rendered)
    .textSelection(.enabled)
    .padding()
```

### UIKit and AppKit

Create a complete `NSAttributedString` when the destination does not need
incremental editing:

```swift
let source = #"let greeting = "Hello, Rork!""#
let snapshot = try Highlighter().highlight(source, as: .swift)
let rendered = try snapshot.nsAttributedString(
    theme: .rorkDark,
    font: .monospacedSystemFont(ofSize: 15, weight: .regular)
)
```

Assign it to `UILabel.attributedText`, `UITextView.attributedText`,
`NSTextStorage.setAttributedString(_:)`, or any API that accepts native
attributed text.

Bundled themes leave text backgrounds unset. The surrounding view or editor
owns its canvas color, so highlighted runs do not paint separate background
strips.

See [Rendering Attributed Code](Sources/RorkHighlighter/RorkHighlighter.docc/RenderingAttributedCode.md)
for native color, font, trait, and range behavior.

## TextKit integration

`TextKitHighlightRenderer` is an optional built-in backend for editable UIKit
and AppKit text views. It works with the `NSTextStorage` exposed by TextKit 1
and TextKit 2 without depending on a layout manager or owning the text view.

It changes only syntax-owned font, foreground, background, underline, and
strikethrough attributes. Paragraph styles, links, attachments, and custom
attributes remain under application control.

### UIKit

```swift
import RorkHighlighter
import UIKit

let source = #"let greeting = "Hello, Rork!""#
let snapshot = try Highlighter().highlight(source, as: .swift)
textView.text = snapshot.text

let renderer = TextKitHighlightRenderer(theme: .rorkDark)
try renderer.render(snapshot, in: textView.textStorage)
```

### AppKit

```swift
import AppKit
import RorkHighlighter

let source = #"let greeting = "Hello, Rork!""#
let snapshot = try Highlighter().highlight(source, as: .swift)
textView.string = snapshot.text

guard let textStorage = textView.textStorage else {
    return
}

let renderer = TextKitHighlightRenderer(theme: .rorkDark)
try renderer.render(snapshot, in: textStorage)
```

Keep one renderer beside each editable storage so its native style and font
caches survive between edits. Ask `HighlightSession` to validate and apply an
edit first. Apply the same replacement to TextKit after that succeeds, then
render the returned `HighlightUpdate`. Only the replacement and invalidated
syntax ranges are restyled.

See [Integrating with TextKit](Sources/RorkHighlighter/RorkHighlighter.docc/TextKitIntegration.md)
for the complete editing sequence and synchronization contract.

## Performance

Rork Highlighter uses native Tree-sitter parsers and preserves syntax trees
between edits. The common one-shot path streams lightweight predicate-aware
captures, while incremental sessions retain unaffected spans. Themes, native
colors, font faces, and TextKit attributes are cached where reuse matters.

These release-mode median ranges come from two campaigns on the same Apple M5
Max development machine:

| Workload | Source | Median range |
| --- | ---: | ---: |
| One-shot semantic highlighting | 256 KiB Swift | 35.7 to 36.2 ms |
| Incremental parse | 1 MiB Swift | 11.1 to 11.4 ms |
| Incremental parse and TextKit restyling | 1 MiB Swift | 11.7 to 11.9 ms |

On the shared 256 KiB fixture, Rork Highlighter measured 35.7 to 36.2 ms and
highlight.js 11.11.1 on Node 24.4.0 measured 36.5 to 42.6 ms. Rork returned
63,146 semantic UTF-16 spans, while highlight.js returned escaped HTML, so the
comparison describes practical throughput rather than identical output. The
editing benchmark is where retained Tree-sitter state matters because a change
does not trigger another full-document pass.

Performance results vary with hardware, operating system, Swift toolchain, and
source structure. The repository includes public-workflow regression
benchmarks and an opt-in same-corpus comparison with HighlightKit,
swift-highlight, and highlight.js. The
[benchmark guide](Benchmarks/README.md) documents workloads, commands, pins,
and reporting constraints.

## Languages

The standard catalog bundles 36 definitions for Swift, React Native and Expo,
Android, and modern web projects. It includes primary languages and the
supporting parsers needed for nested code.

Nested-language queries resolve through the same catalog. This covers examples
such as JavaScript inside HTML, TypeScript inside Vue, GraphQL tagged templates,
Swift regular-expression literals, and fenced code inside Markdown.

The [bundled language guide](Sources/RorkHighlighter/RorkHighlighter.docc/BundledLanguages.md)
lists every language, typed identifier, alias, and file mapping.

### Application footprint

The complete 0.3.0 catalog increased the complete ad hoc-signed arm64 iOS
application bundle by 39.4 MiB in a controlled Release comparison. The stripped
application executable accounted for 39.22 MiB of that increase. Generated
parser tables account for almost all of the growth. Bundled query resources
contribute only about 83 KiB.

The locally compressed application delta was 3.82 MiB, but this is not an App
Store download estimate. Apple applies app thinning, DRM, and recompression
before distribution. The [benchmark guide](Benchmarks/README.md#ios-application-footprint)
records the measurement setup and its limitations.

## Themes

Rork Light and Rork Dark use hierarchical Tree-sitter capture scopes. A
`string.special.key` span inherits broader `string` and `string.special`
rules before its exact rule is applied.

Create a custom renderer-neutral theme with a base style and scope refinements:

```swift
let theme = HighlightTheme(
    name: "Brand",
    baseStyle: HighlightStyle(
        foregroundColor: HighlightColor(rgb: 0xE6E6E6),
        textTraits: []
    ),
    styles: [
        "comment": HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x7A8A99),
            textTraits: [.italic]
        ),
        "keyword": HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xD99BFF)
        ),
    ]
)
```

See [Theming](Sources/RorkHighlighter/RorkHighlighter.docc/Theming.md) for
inheritance and native typography behavior.

## Custom languages

The bundled catalog needs no application-side parser registration.
`HighlightLanguage` remains available for a private grammar or a language
outside the common pack. A definition combines one generated Tree-sitter
parser with compatible highlight, injection, and locals queries.

See [Registering Languages](Sources/RorkHighlighter/RorkHighlighter.docc/RegisteringLanguages.md)
for the complete setup.

## Documentation

- [Getting Started](Sources/RorkHighlighter/RorkHighlighter.docc/GettingStarted.md)
  introduces immutable highlighting.
- [Incremental Highlighting](Sources/RorkHighlighter/RorkHighlighter.docc/IncrementalHighlighting.md)
  explains document sessions without assuming a rendering framework.
- [Building Rendering Backends](Sources/RorkHighlighter/RorkHighlighter.docc/RenderingBackends.md)
  covers the low-level renderer contract.
- [Rendering Attributed Code](Sources/RorkHighlighter/RorkHighlighter.docc/RenderingAttributedCode.md)
  covers complete SwiftUI, UIKit, and AppKit output.
- [Integrating with TextKit](Sources/RorkHighlighter/RorkHighlighter.docc/TextKitIntegration.md)
  covers editable UIKit and AppKit storage.
- [Architecture](Docs/Architecture.md) explains parser ownership and
  distribution.

## Development

Run the complete validation:

```bash
make check
```

Run the public-workflow performance suite:

```bash
make benchmark
```

Run the opt-in same-corpus comparison:

```bash
make benchmark-comparison \
  COMPARISON_BENCHMARK_ARGUMENTS="--metric wallClock --time-units microseconds --no-progress"
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for maintenance workflows and
[CHANGELOG.md](CHANGELOG.md) for published releases.

## License

See the [Apache-2.0 license](LICENSE) and
[third-party notices](THIRD_PARTY_NOTICES.md).
