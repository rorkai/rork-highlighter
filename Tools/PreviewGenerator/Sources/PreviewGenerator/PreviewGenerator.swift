import AppKit
import Foundation
import RorkHighlighter

/// Generates the committed README and DocC preview on macOS.
@main
@MainActor
private enum PreviewGenerator {
    /// The logical drawing size used to position every preview element.
    private static let designSize = NSSize(width: 1_120, height: 800)

    /// The fixed pixel dimensions of the committed preview.
    private static let pixelSize = NSSize(width: 1_680, height: 1_200)

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

    /// The font whose metrics position the focused source lines.
    private let codeFont: NSFont

    /// The additional distance between rendered source lines.
    private let lineSpacing: CGFloat

    /// The zero-based source lines that receive restrained emphasis.
    private let focusedLines = 8..<10

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
    ///   - codeFont: The font used to render the highlighted source.
    ///   - lineSpacing: The extra distance between source lines.
    init(
        frame frameRect: NSRect,
        backdrop: NSImage,
        code: NSAttributedString,
        codeFont: NSFont,
        lineSpacing: CGFloat
    ) {
        self.backdrop = backdrop
        self.code = code
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

        let titlebarHeight: CGFloat = 64
        let codePadding = NSSize(width: 56, height: 24)
        let codeSize = code.size()
        let windowRect = NSRect(
            x: floor((bounds.width - ceil(codeSize.width) - codePadding.width * 2) / 2),
            y: floor(
                (bounds.height - titlebarHeight - ceil(codeSize.height)
                    - codePadding.height * 2) / 2
            ),
            width: ceil(codeSize.width) + codePadding.width * 2,
            height: titlebarHeight + ceil(codeSize.height)
                + codePadding.height * 2
        )
        drawWindowGlow(behind: windowRect)
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

    /// Fills the canvas with the committed backdrop, vignette, and fine grain.
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
                NSColor.black.withAlphaComponent(0.24),
            ]
        )?.draw(in: bounds, angle: -90)

        drawBackdropNoise()
    }

    /// Adds deterministic grain that keeps the dark gradient from banding.
    private func drawBackdropNoise() {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let lightNoise = CGMutablePath()
        let darkNoise = CGMutablePath()
        let sampleCount = Int(bounds.width * bounds.height / 34)
        var state: UInt64 = 0xA076_1D64_78BD_642F

        for index in 0..<sampleCount {
            state =
                state &* 6_364_136_223_846_793_005
                &+ 1_442_695_040_888_963_407
            let x =
                CGFloat(state & 0xFFFF_FFFF)
                / CGFloat(UInt32.max) * bounds.width
            state =
                state &* 6_364_136_223_846_793_005
                &+ 1_442_695_040_888_963_407
            let y =
                CGFloat(state & 0xFFFF_FFFF)
                / CGFloat(UInt32.max) * bounds.height
            let speck = NSRect(
                x: floor(x),
                y: floor(y),
                width: 0.75,
                height: 0.75
            )
            if index.isMultiple(of: 2) {
                lightNoise.addRect(speck)
            } else {
                darkNoise.addRect(speck)
            }
        }

        context.saveGState()
        context.addPath(darkNoise)
        context.setFillColor(
            NSColor.black.withAlphaComponent(0.05).cgColor
        )
        context.fillPath()
        context.addPath(lightNoise)
        context.setFillColor(
            NSColor.white.withAlphaComponent(0.035).cgColor
        )
        context.fillPath()
        context.restoreGState()
    }

    /// Draws a broad colored glow that separates the editor from the canvas.
    ///
    /// - Parameter windowRect: The editor bounds used to position the glow.
    private func drawWindowGlow(behind windowRect: NSRect) {
        let center = NSPoint(
            x: windowRect.midX,
            y: windowRect.midY + 26
        )
        NSGradient(
            colors: [
                NSColor.rgb(0x7A_5C_FF, alpha: 0.22),
                NSColor.rgb(0x3B_68_E8, alpha: 0.09),
                NSColor.clear,
            ]
        )?.draw(
            fromCenter: center,
            radius: 0,
            toCenter: center,
            radius: windowRect.width * 0.72,
            options: []
        )
    }

    /// Draws the single editor surface with its border, shadow, and inner glow.
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
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.72)
        shadow.shadowBlurRadius = 64
        shadow.shadowOffset = NSSize(width: 0, height: 28)
        shadow.set()
        NSColor.rgb(0x12_14_1B, alpha: 0.965).setFill()
        windowPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        windowPath.lineWidth = 1.1
        NSColor.white.withAlphaComponent(0.15).setStroke()
        windowPath.stroke()

        NSGraphicsContext.saveGraphicsState()
        windowPath.addClip()
        NSGradient(
            colors: [
                NSColor.clear,
                NSColor.white.withAlphaComponent(0.075),
                NSColor.white.withAlphaComponent(0.075),
                NSColor.clear,
            ]
        )?.draw(
            in: NSRect(
                x: windowRect.minX + 28,
                y: windowRect.minY + 1,
                width: windowRect.width - 56,
                height: 1
            ),
            angle: 0
        )
        NSGraphicsContext.restoreGraphicsState()
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

    /// Draws the highlighted source without decorative editor furniture.
    ///
    /// - Parameter editorRect: The area below the titlebar.
    private func drawCode(in editorRect: NSRect) {
        let codeOrigin = NSPoint(
            x: editorRect.minX + 56,
            y: editorRect.minY + 24
        )
        drawFocus(in: editorRect, codeOrigin: codeOrigin)
        code.draw(at: codeOrigin)
    }

    /// Gives the central API example a quiet visual anchor.
    ///
    /// - Parameters:
    ///   - editorRect: The complete editor area below the titlebar.
    ///   - codeOrigin: The point where the highlighted source begins.
    private func drawFocus(
        in editorRect: NSRect,
        codeOrigin: NSPoint
    ) {
        let lineHeight =
            codeFont.ascender - codeFont.descender
            + codeFont.leading + lineSpacing
        let focusRect = NSRect(
            x: editorRect.minX + 18,
            y: codeOrigin.y + CGFloat(focusedLines.lowerBound) * lineHeight - 3,
            width: editorRect.width - 36,
            height: CGFloat(focusedLines.count) * lineHeight + 6
        )
        let focusPath = NSBezierPath(
            roundedRect: focusRect,
            xRadius: 8,
            yRadius: 8
        )

        NSGraphicsContext.saveGraphicsState()
        focusPath.addClip()
        NSGradient(
            colors: [
                NSColor.rgb(0x82_6C_FF, alpha: 0.065),
                NSColor.rgb(0x56_7D_EF, alpha: 0.035),
            ]
        )?.draw(in: focusRect, angle: 0)
        NSGraphicsContext.restoreGraphicsState()

        focusPath.lineWidth = 0.8
        NSColor.white.withAlphaComponent(0.04).setStroke()
        focusPath.stroke()
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
