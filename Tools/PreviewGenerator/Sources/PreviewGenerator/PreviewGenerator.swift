import AppKit
import Foundation
import RorkHighlighter

/// Generates the committed README and DocC preview on macOS.
@main
@MainActor
private enum PreviewGenerator {
    /// The logical drawing size used to position every preview element.
    private static let designSize = NSSize(width: 1_600, height: 740)

    /// The fixed pixel dimensions of the committed preview.
    private static let pixelSize = NSSize(width: 2_400, height: 1_110)

    /// The monospaced font used for highlighted code.
    private static let codeFont = NSFont.monospacedSystemFont(
        ofSize: 27,
        weight: .regular
    )

    /// The additional distance between rendered code lines.
    private static let lineSpacing: CGFloat = 8.5

    /// Reads the output path and renders the preview.
    ///
    /// - Throws: A generator error when the arguments or preview inputs are
    ///   invalid.
    private static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1 else {
            throw PreviewGeneratorError.invalidArguments
        }

        let outputURL = URL(fileURLWithPath: arguments[0])
        try generatePreview(at: outputURL)
    }

    /// Renders the highlighted fixture and writes it to the requested path.
    ///
    /// - Parameter outputURL: The location that receives the PNG preview.
    /// - Throws: A generator error when an input cannot be read, rendered, or
    ///   written.
    private static func generatePreview(
        at outputURL: URL
    ) throws(PreviewGeneratorError) {
        let source = try loadSource()
        let backdrop = try loadBackdrop()
        let code = try highlightedCode(for: source)
        let view = PreviewView(
            frame: NSRect(origin: .zero, size: designSize),
            backdrop: backdrop,
            code: code,
            source: source,
            codeFont: codeFont,
            lineSpacing: lineSpacing
        )
        let representation = try bitmapRepresentation(for: view)

        guard
            let data = representation.representation(
                using: .png,
                properties: [:]
            )
        else {
            throw .couldNotEncodePNG
        }

        let outputDirectory = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: outputURL, options: .atomic)
        } catch {
            throw .couldNotWriteOutput(outputURL)
        }
    }

    /// Loads the Swift fixture without its final newline.
    ///
    /// - Throws: A generator error when the fixture is missing or unreadable.
    private static func loadSource() throws(PreviewGeneratorError) -> String {
        let sourceURL = try resourceURL(
            named: "WelcomeView.swift.txt"
        )
        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
                .trimmingCharacters(in: .newlines)
        } catch {
            throw .couldNotReadFixture(sourceURL)
        }
    }

    /// Loads the committed spatial backdrop.
    ///
    /// - Throws: A generator error when the backdrop is missing or unreadable.
    private static func loadBackdrop()
        throws(PreviewGeneratorError) -> NSImage
    {
        let backdropURL = try resourceURL(named: "Backdrop.png")
        guard let backdrop = NSImage(contentsOf: backdropURL) else {
            throw .couldNotLoadBackdrop(backdropURL)
        }
        return backdrop
    }

    /// Resolves a committed input from the package resource bundle.
    ///
    /// - Parameter name: The complete filename of the requested resource.
    /// - Returns: The location of the bundled resource.
    /// - Throws: A generator error when the resource is absent.
    private static func resourceURL(
        named name: String
    ) throws(PreviewGeneratorError) -> URL {
        let resourceURL = Bundle.module.bundleURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        guard FileManager.default.fileExists(atPath: resourceURL.path) else {
            throw .missingResource(name)
        }
        return resourceURL
    }

    /// Highlights the fixture with the public native attributed output API.
    ///
    /// - Parameter source: The Swift source to parse and render.
    /// - Returns: The styled source with preview line spacing applied.
    /// - Throws: A generator error when parsing or native rendering fails.
    private static func highlightedCode(
        for source: String
    ) throws(PreviewGeneratorError) -> NSAttributedString {
        let highlighter: Highlighter
        let snapshot: HighlightSnapshot
        do {
            highlighter = try Highlighter()
            snapshot = try highlighter.highlight(source, as: .swift)
        } catch {
            throw .couldNotHighlight(String(describing: error))
        }

        let rendered: NSAttributedString
        do {
            rendered = try snapshot.nsAttributedString(
                theme: .rorkDark,
                font: codeFont
            )
        } catch {
            throw .couldNotRender(String(describing: error))
        }

        let code = NSMutableAttributedString(
            attributedString: rendered
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        code.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: code.length)
        )
        return code
    }

    /// Draws the logical view into a fixed-resolution calibrated RGB bitmap.
    ///
    /// - Parameter view: The fully configured preview view.
    /// - Returns: The bitmap that is ready for PNG encoding.
    /// - Throws: A generator error when AppKit cannot allocate the bitmap.
    private static func bitmapRepresentation(
        for view: NSView
    ) throws(PreviewGeneratorError) -> NSBitmapImageRep {
        guard
            let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pixelSize.width),
                pixelsHigh: Int(pixelSize.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            throw .couldNotCreateBitmap
        }

        representation.size = designSize
        view.cacheDisplay(in: view.bounds, to: representation)
        return representation
    }
}

/// Draws the backdrop, editor window, and highlighted source.
@MainActor
private final class PreviewView: NSView {
    /// The quiet spatial image drawn behind the editor.
    private let backdrop: NSImage

    /// The source after Rork Highlighter applies native attributes.
    private let code: NSAttributedString

    /// The plain source used to derive the line-number gutter.
    private let source: String

    /// The font whose metrics align code with its line numbers.
    private let codeFont: NSFont

    /// The line spacing shared by code and its line numbers.
    private let lineSpacing: CGFloat

    /// Uses top-left coordinates for straightforward editor layout.
    override var isFlipped: Bool {
        true
    }

    /// Creates a preview view from its committed and rendered inputs.
    ///
    /// - Parameters:
    ///   - frameRect: The logical canvas occupied by the preview.
    ///   - backdrop: The spatial image drawn behind the editor.
    ///   - code: The attributed source rendered by Rork Highlighter.
    ///   - source: The original source used to create line numbers.
    ///   - codeFont: The font shared by code and its line numbers.
    ///   - lineSpacing: The extra distance between source lines.
    init(
        frame frameRect: NSRect,
        backdrop: NSImage,
        code: NSAttributedString,
        source: String,
        codeFont: NSFont,
        lineSpacing: CGFloat
    ) {
        self.backdrop = backdrop
        self.code = code
        self.source = source
        self.codeFont = codeFont
        self.lineSpacing = lineSpacing
        super.init(frame: frameRect)
    }

    /// Prevents construction from an archived AppKit view.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Draws the complete preview whenever AppKit requests an update.
    ///
    /// - Parameter dirtyRect: The region that AppKit asked the view to redraw.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBackdrop()

        let windowRect = NSRect(
            x: 164,
            y: 48,
            width: 1_272,
            height: 644
        )
        let titlebarHeight: CGFloat = 70
        drawWindow(in: windowRect)
        drawTitlebar(in: windowRect, height: titlebarHeight)
        drawCode(
            in: NSRect(
                x: windowRect.minX,
                y: windowRect.minY + titlebarHeight,
                width: windowRect.width,
                height: windowRect.height - titlebarHeight
            )
        )
    }

    /// Fills the canvas with the committed backdrop and a quiet vignette.
    private func drawBackdrop() {
        backdrop.draw(
            in: bounds,
            from: backdropSourceRect(
                imageSize: backdrop.size,
                destinationSize: bounds.size
            ),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        NSGradient(
            colors: [
                NSColor.black.withAlphaComponent(0.08),
                NSColor.clear,
                NSColor.black.withAlphaComponent(0.18),
            ]
        )?.draw(in: bounds, angle: -90)
    }

    /// Draws the single flat editor surface, border, and shadow.
    ///
    /// - Parameter windowRect: The bounds occupied by the editor window.
    private func drawWindow(in windowRect: NSRect) {
        let windowPath = NSBezierPath(
            roundedRect: windowRect,
            xRadius: 28,
            yRadius: 28
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.62)
        shadow.shadowBlurRadius = 48
        shadow.shadowOffset = NSSize(width: 0, height: 24)
        shadow.set()
        NSColor.rgb(0x10_12_18, alpha: 0.92).setFill()
        windowPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        windowPath.lineWidth = 1.1
        NSColor.white.withAlphaComponent(0.17).setStroke()
        windowPath.stroke()
    }

    /// Draws the traffic lights, centered filename, and separator.
    ///
    /// - Parameters:
    ///   - windowRect: The bounds occupied by the editor window.
    ///   - height: The titlebar height above the separator.
    private func drawTitlebar(
        in windowRect: NSRect,
        height: CGFloat
    ) {
        let dotColors = [
            NSColor.rgb(0xFF_5F_57),
            NSColor.rgb(0xFE_BC_2E),
            NSColor.rgb(0x28_C8_40),
        ]
        for (index, color) in dotColors.enumerated() {
            let dotRect = NSRect(
                x: windowRect.minX + 28 + CGFloat(index) * 25,
                y: windowRect.minY + 29,
                width: 13,
                height: 13
            )
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        let title = NSAttributedString(
            string: "WelcomeView.swift",
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: 16.5,
                    weight: .semibold
                ),
                .foregroundColor: NSColor.white.withAlphaComponent(0.86),
            ]
        )
        title.draw(
            at: NSPoint(
                x: windowRect.midX - title.size().width / 2,
                y: windowRect.minY + 24
            )
        )

        let separator = NSBezierPath()
        separator.move(
            to: NSPoint(
                x: windowRect.minX,
                y: windowRect.minY + height
            )
        )
        separator.line(
            to: NSPoint(
                x: windowRect.maxX,
                y: windowRect.minY + height
            )
        )
        separator.lineWidth = 1
        NSColor.white.withAlphaComponent(0.10).setStroke()
        separator.stroke()
    }

    /// Draws the highlighted source and its restrained line-number gutter.
    ///
    /// - Parameter editorRect: The area below the titlebar.
    private func drawCode(in editorRect: NSRect) {
        let codeOrigin = NSPoint(
            x: editorRect.minX + 142,
            y: editorRect.minY + 25
        )
        code.draw(at: codeOrigin)

        let lineNumbers =
            source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .indices
            .map { String($0 + 1) }
            .joined(separator: "\n")
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.lineSpacing = lineSpacing
        NSAttributedString(
            string: lineNumbers,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: codeFont.pointSize,
                    weight: .regular
                ),
                .foregroundColor: NSColor.white.withAlphaComponent(0.18),
                .paragraphStyle: paragraphStyle,
            ]
        ).draw(
            in: NSRect(
                x: editorRect.minX + 66,
                y: codeOrigin.y,
                width: 42,
                height: editorRect.height - 36
            )
        )

        let gutter = NSBezierPath()
        gutter.move(
            to: NSPoint(
                x: editorRect.minX + 124,
                y: editorRect.minY + 22
            )
        )
        gutter.line(
            to: NSPoint(
                x: editorRect.minX + 124,
                y: editorRect.maxY - 22
            )
        )
        gutter.lineWidth = 1
        NSColor.white.withAlphaComponent(0.055).setStroke()
        gutter.stroke()
    }

    /// Calculates the centered crop needed to fill the canvas.
    ///
    /// - Parameters:
    ///   - imageSize: The original dimensions of the backdrop.
    ///   - destinationSize: The dimensions that the backdrop must fill.
    /// - Returns: The source rectangle that preserves the backdrop aspect ratio.
    private func backdropSourceRect(
        imageSize: NSSize,
        destinationSize: NSSize
    ) -> NSRect {
        let scale = max(
            destinationSize.width / imageSize.width,
            destinationSize.height / imageSize.height
        )
        let visibleSize = NSSize(
            width: destinationSize.width / scale,
            height: destinationSize.height / scale
        )
        return NSRect(
            x: (imageSize.width - visibleSize.width) / 2,
            y: (imageSize.height - visibleSize.height) / 2,
            width: visibleSize.width,
            height: visibleSize.height
        )
    }
}

/// Provides compact sRGB colors for the preview renderer.
private extension NSColor {
    /// Creates an sRGB color from a hexadecimal RGB value.
    ///
    /// - Parameters:
    ///   - value: The red, green, and blue components packed into an integer.
    ///   - alpha: The opacity applied to the resulting color.
    /// - Returns: The requested sRGB color.
    static func rgb(
        _ value: UInt32,
        alpha: CGFloat = 1
    ) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Describes failures that prevent the preview from being generated.
private enum PreviewGeneratorError: Error, CustomStringConvertible {
    /// The command did not receive exactly one output path.
    case invalidArguments

    /// A committed input could not be found in the package bundle.
    case missingResource(String)

    /// The Swift fixture could not be decoded as UTF-8.
    case couldNotReadFixture(URL)

    /// AppKit could not decode the committed backdrop.
    case couldNotLoadBackdrop(URL)

    /// Tree-sitter could not parse and highlight the Swift fixture.
    case couldNotHighlight(String)

    /// Native attributed output could not render the highlighted snapshot.
    case couldNotRender(String)

    /// AppKit could not allocate the fixed-resolution bitmap.
    case couldNotCreateBitmap

    /// AppKit could not encode the rendered bitmap as PNG.
    case couldNotEncodePNG

    /// The completed PNG could not be written to its requested path.
    case couldNotWriteOutput(URL)

    /// Returns a readable explanation for command-line diagnostics.
    var description: String {
        switch self {
        case .invalidArguments:
            "Usage: PreviewGenerator <output-path>"
        case let .missingResource(name):
            "The bundled resource \(name) could not be found."
        case let .couldNotReadFixture(url):
            "The Swift fixture at \(url.path) could not be read."
        case let .couldNotLoadBackdrop(url):
            "The backdrop at \(url.path) could not be loaded."
        case let .couldNotHighlight(message):
            "The Swift fixture could not be highlighted. \(message)"
        case let .couldNotRender(message):
            "The highlighted fixture could not be rendered. \(message)"
        case .couldNotCreateBitmap:
            "The fixed-resolution bitmap could not be created."
        case .couldNotEncodePNG:
            "The rendered preview could not be encoded as PNG."
        case let .couldNotWriteOutput(url):
            "The preview could not be written to \(url.path)."
        }
    }
}
