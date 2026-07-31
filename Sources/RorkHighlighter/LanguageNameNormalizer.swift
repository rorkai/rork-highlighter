import Foundation

/// Normalizes language discovery metadata for definitions and catalog lookups.
enum LanguageNameNormalizer {
    /// Removes spelling variations that should not affect extension lookup.
    ///
    /// - Parameter value: The extension supplied by a definition or caller.
    /// - Returns: A lowercase extension without surrounding periods or spaces.
    static func fileExtension(from value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: ". \t\r\n"))
            .lowercased()
    }

    /// Removes spelling variations that should not affect filename lookup.
    ///
    /// - Parameter value: The filename supplied by a definition or caller.
    /// - Returns: A lowercase filename without surrounding whitespace.
    static func filename(from value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
