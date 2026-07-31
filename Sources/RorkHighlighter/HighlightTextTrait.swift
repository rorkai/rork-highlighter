/// Describes renderer-neutral typography applied by a highlight style.
public enum HighlightTextTrait:
    String,
    CaseIterable,
    Hashable,
    Sendable,
    Codable
{
    /// Requests a heavier font weight.
    case bold

    /// Requests an italic font face.
    case italic

    /// Requests a line beneath the highlighted text.
    case underline

    /// Requests a line through the highlighted text.
    case strikethrough
}
