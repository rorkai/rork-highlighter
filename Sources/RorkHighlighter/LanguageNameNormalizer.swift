import Foundation

/// Normalizes language discovery metadata for definitions and catalog lookups.
enum LanguageNameNormalizer {
    /// Removes spelling variations that should not affect extension lookup.
    ///
    /// The value may come from a language definition or a caller. The result is
    /// lowercase and has no surrounding periods or spaces.
    static func fileExtension(from value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: ". \t\r\n"))
            .lowercased()
    }

    /// Removes spelling variations that should not affect filename lookup.
    ///
    /// The value may come from a language definition or a caller. The result is
    /// lowercase and has no surrounding whitespace.
    static func filename(from value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
