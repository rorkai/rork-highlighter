import CryptoKit
import Foundation
import RorkHighlighter

/// Describes the generated fixture manifest shared with the JavaScript suite.
private struct ComparisonFixtureManifest: Decodable, Sendable {
    /// Identifies the manifest format understood by this benchmark.
    let schemaVersion: Int

    /// Names the language represented by every fixture.
    let language: String

    /// Holds the original fixed-width marker near the start of each fixture.
    let revisionMarker: String

    /// Holds the replacement marker used by editing workloads.
    let replacementMarker: String

    /// Describes every generated source file in measurement order.
    let fixtures: [ComparisonFixtureManifestEntry]
}

/// Describes one generated source file and its integrity metadata.
private struct ComparisonFixtureManifestEntry: Decodable, Sendable {
    /// Provides the stable size label used in benchmark names.
    let name: String

    /// Provides the source filename relative to the fixture directory.
    let fileName: String

    /// Records the requested minimum UTF-16 length.
    let minimumUTF16Length: Int

    /// Records the exact encoded byte count.
    let byteCount: Int

    /// Records the exact UTF-16 code-unit count.
    let utf16Count: Int

    /// Records the line count including a final empty line.
    let lineCount: Int

    /// Records the lowercase SHA-256 digest of the source bytes.
    let sha256: String
}

/// Reports why a generated comparison fixture could not be loaded safely.
private enum ComparisonFixtureLoadingError: Error, CustomStringConvertible {
    /// The manifest uses a format this benchmark does not understand.
    case unsupportedSchemaVersion(Int)

    /// The manifest describes a language other than Swift.
    case unsupportedLanguage(String)

    /// A generated fixture is not valid UTF-8 text.
    case invalidUTF8(String)

    /// A generated fixture does not match its recorded metadata.
    case integrityMismatch(String)

    /// A generated fixture does not contain the editing marker.
    case missingRevisionMarker(String)

    /// Explains the loading failure in benchmark diagnostics.
    var description: String {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "The comparison fixture schema version \(version) is unsupported."
        case .unsupportedLanguage(let language):
            "The comparison fixture language \(language) is unsupported."
        case .invalidUTF8(let name):
            "The \(name) comparison fixture is not valid UTF-8."
        case .integrityMismatch(let name):
            "The \(name) comparison fixture does not match its manifest."
        case .missingRevisionMarker(let name):
            "The \(name) comparison fixture has no revision marker."
        }
    }
}

/// Holds one immutable source document used by every Swift implementation.
struct ComparisonFixture: Sendable {
    /// Provides the stable size label used in benchmark names.
    let name: String

    /// Contains the original generated Swift source.
    let text: String

    /// Contains the source after its fixed-width marker changes.
    let editedText: String

    /// Locates the marker in Foundation-native UTF-16 coordinates.
    let markerRange: UTF16Range

    /// Records the exact source size used by throughput calculations.
    let byteCount: Int

    /// Records the source digest printed by the fixture generator.
    let sha256: String
}

/// Loads the canonical fixture corpus shared by every comparison runtime.
enum ComparisonFixtures {
    /// Holds the validated manifest shared by every fixture accessor.
    private static let manifest: ComparisonFixtureManifest = {
        do {
            return try loadManifest()
        } catch {
            preconditionFailure(
                "Could not load the comparison fixture manifest. \(error)"
            )
        }
    }()

    /// Contains every generated Swift fixture in measurement order.
    static let swiftSources: [ComparisonFixture] = {
        do {
            return try loadFixtures()
        } catch {
            preconditionFailure(
                "Could not load comparison fixtures. \(error)"
            )
        }
    }()

    /// Holds the original marker used by editing workloads.
    static var revisionMarker: String { manifest.revisionMarker }

    /// Holds the same-width replacement used by editing workloads.
    static var replacementMarker: String { manifest.replacementMarker }

    /// Returns the largest fixture used by editor workloads.
    static var editingFixture: ComparisonFixture {
        guard let fixture = swiftSources.last else {
            preconditionFailure(
                "The comparison fixture collection is empty."
            )
        }
        return fixture
    }

    /// Locates generated fixtures without depending on the process directory.
    private static var directoryURL: URL {
        if let override = ProcessInfo.processInfo.environment[
            "RORK_HIGHLIGHTER_COMPARISON_FIXTURES"
        ] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
    }

    /// Locates the generated manifest beside the shared source files.
    private static var manifestURL: URL {
        directoryURL.appendingPathComponent("manifest.json")
    }

    /// Loads and validates the fixture manifest.
    ///
    /// - Returns: The decoded manifest accepted by this benchmark version.
    /// - Throws: A decoding, file-system, or manifest validation error.
    private static func loadManifest() throws -> ComparisonFixtureManifest {
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(
            ComparisonFixtureManifest.self,
            from: data
        )
        guard manifest.schemaVersion == 1 else {
            throw ComparisonFixtureLoadingError.unsupportedSchemaVersion(
                manifest.schemaVersion
            )
        }
        guard manifest.language == "swift" else {
            throw ComparisonFixtureLoadingError.unsupportedLanguage(
                manifest.language
            )
        }
        return manifest
    }

    /// Loads every source file and verifies its recorded identity.
    ///
    /// - Returns: The complete ordered fixture collection.
    /// - Throws: A source-file validation error.
    private static func loadFixtures() throws -> [ComparisonFixture] {
        return try manifest.fixtures.map { entry in
            try loadFixture(entry, manifest: manifest)
        }
    }

    /// Loads one source file and constructs its edited counterpart.
    ///
    /// - Parameters:
    ///   - entry: The integrity metadata for the requested source file.
    ///   - manifest: The manifest that provides the editing markers.
    /// - Returns: A validated immutable comparison fixture.
    /// - Throws: A file-system, encoding, or integrity validation error.
    private static func loadFixture(
        _ entry: ComparisonFixtureManifestEntry,
        manifest: ComparisonFixtureManifest
    ) throws -> ComparisonFixture {
        let sourceURL = directoryURL.appendingPathComponent(entry.fileName)
        let data = try Data(contentsOf: sourceURL)
        guard let source = String(data: data, encoding: .utf8) else {
            throw ComparisonFixtureLoadingError.invalidUTF8(entry.name)
        }

        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let lineCount = source.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
        guard
            data.count == entry.byteCount,
            source.utf16.count == entry.utf16Count,
            source.utf16.count >= entry.minimumUTF16Length,
            lineCount == entry.lineCount,
            digest == entry.sha256
        else {
            throw ComparisonFixtureLoadingError.integrityMismatch(entry.name)
        }

        guard let marker = source.range(of: manifest.revisionMarker) else {
            throw ComparisonFixtureLoadingError.missingRevisionMarker(
                entry.name
            )
        }
        let markerRange = NSRange(marker, in: source)
        let editedText = (source as NSString).replacingCharacters(
            in: markerRange,
            with: manifest.replacementMarker
        )
        return ComparisonFixture(
            name: entry.name,
            text: source,
            editedText: editedText,
            markerRange: UTF16Range(
                location: markerRange.location,
                length: markerRange.length
            ),
            byteCount: entry.byteCount,
            sha256: entry.sha256
        )
    }
}
