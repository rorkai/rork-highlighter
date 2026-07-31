/// Describes a renderer-neutral color in the sRGB color space.
///
/// Channels use eight-bit values so themes remain deterministic across Apple
/// and non-Apple platforms.
public struct HighlightColor: Hashable, Sendable, Codable {
    /// Holds a validated packed 24-bit RGB value.
    ///
    /// Integer literals remain concise for authored themes. Dynamic values use
    /// the failable ``init(rawValue:)`` initializer before creating a color.
    public struct RGB:
        RawRepresentable,
        ExpressibleByIntegerLiteral,
        Hashable,
        Sendable
    {
        /// Holds the packed red, green, and blue channels.
        public let rawValue: UInt32

        /// Validates a dynamically produced packed RGB value.
        ///
        /// - Parameter rawValue: The proposed 24-bit RGB value.
        public init?(rawValue: UInt32) {
            guard rawValue <= 0xFF_FF_FF else {
                return nil
            }
            self.rawValue = rawValue
        }

        /// Creates a packed RGB value from an integer literal.
        ///
        /// Theme literals must not exceed `0xFFFFFF`.
        ///
        /// - Parameter value: The 24-bit RGB integer literal.
        public init(integerLiteral value: UInt32) {
            guard let rgb = Self(rawValue: value) else {
                preconditionFailure(
                    "Packed RGB color literals cannot exceed 24 bits."
                )
            }
            self = rgb
        }
    }

    /// Holds the red channel.
    public let red: UInt8

    /// Holds the green channel.
    public let green: UInt8

    /// Holds the blue channel.
    public let blue: UInt8

    /// Holds the opacity channel, where zero is transparent and 255 is opaque.
    public let alpha: UInt8

    /// Creates a color from individual eight-bit channels.
    ///
    /// - Parameters:
    ///   - red: The red channel.
    ///   - green: The green channel.
    ///   - blue: The blue channel.
    ///   - alpha: The opacity channel.
    public init(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: UInt8 = .max
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Creates a color from a packed 24-bit RGB value.
    ///
    /// - Parameters:
    ///   - rgb: The validated red, green, and blue channels.
    ///   - alpha: The opacity channel.
    public init(
        rgb: RGB,
        alpha: UInt8 = .max
    ) {
        self.init(
            red: UInt8((rgb.rawValue >> 16) & 0xFF),
            green: UInt8((rgb.rawValue >> 8) & 0xFF),
            blue: UInt8(rgb.rawValue & 0xFF),
            alpha: alpha
        )
    }
}
