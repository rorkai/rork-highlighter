/// Describes a renderer-neutral color in the sRGB color space.
///
/// Channels use eight-bit values so themes remain deterministic across Apple
/// and non-Apple platforms.
public struct HighlightColor: Hashable, Sendable, Codable {
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
    /// The packed value must not exceed `0xFFFFFF`.
    ///
    /// - Parameters:
    ///   - rgb: The red, green, and blue channels in hexadecimal order.
    ///   - alpha: The opacity channel.
    public init(
        rgb: UInt32,
        alpha: UInt8 = .max
    ) {
        precondition(
            rgb <= 0xFF_FF_FF,
            "Packed RGB colors cannot exceed 24 bits."
        )
        self.init(
            red: UInt8((rgb >> 16) & 0xFF),
            green: UInt8((rgb >> 8) & 0xFF),
            blue: UInt8(rgb & 0xFF),
            alpha: alpha
        )
    }
}
