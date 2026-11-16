import SwiftUI

/// The web app's three typefaces, bundled (OFL / Apache 2.0, licences next to the files).
/// `relativeTo:` keeps them scaling with Dynamic Type.
enum Fonts {
    /// Syncopate: wide display caps for names and labels.
    static func display(_ size: CGFloat, bold: Bool = true, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? "Syncopate-Bold" : "Syncopate-Regular", size: size, relativeTo: style)
    }

    /// VT323: the pixel "terminal" face for numbers and readouts.
    static func mono(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("VT323-Regular", size: size, relativeTo: style).monospacedDigit()
    }

    /// Space Grotesk (variable): body text.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Space Grotesk", size: size, relativeTo: style).weight(weight)
    }
}

extension View {
    /// CSS `letter-spacing` in em.
    func spacing(_ em: CGFloat, size: CGFloat) -> some View {
        tracking(em * size)
    }

    /// The neon `text-shadow` used on station names and readouts.
    func neon(_ color: Color, radius: CGFloat = 9) -> some View {
        shadow(color: color, radius: radius).shadow(color: color, radius: 1.5)
    }
}
