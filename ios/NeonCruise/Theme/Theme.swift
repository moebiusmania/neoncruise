import SwiftUI

/// oklch → sRGB, the same conversion the web (CSS) and TUI (`color.rs`) use, so every
/// station keeps its exact colour world.
nonisolated struct RGB: Equatable, Sendable {
    var r: Double, g: Double, b: Double

    static func oklch(_ l: Double, _ c: Double, _ h: Double) -> RGB {
        let hr = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) * .pi / 180
        let a = c * cos(hr), b = c * sin(hr)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let (l3, m3, s3) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_)
        let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bl = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        func enc(_ v: Double) -> Double {
            let v = min(1, max(0, v))
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return RGB(r: enc(r), g: enc(g), b: enc(bl))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    func color(_ opacity: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: opacity) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

/// `oklch(L C H / a)` as a SwiftUI colour.
func ok(_ l: Double, _ c: Double, _ h: Double, _ a: Double = 1) -> Color {
    RGB.oklch(l, c, h).color(a)
}

enum Palette {
    static let bg = Color(.sRGB, red: 5 / 255, green: 2 / 255, blue: 10 / 255)
    static let ink = Color(.sRGB, red: 246 / 255, green: 240 / 255, blue: 251 / 255)
    static let ink2 = Color.white.opacity(0.74)
    static let ink3 = Color.white.opacity(0.55)
    static let line = Color.white.opacity(0.2)
    static let lineSoft = Color.white.opacity(0.08)
    static let glass = Color(.sRGB, red: 5 / 255, green: 2 / 255, blue: 10 / 255, opacity: 0.74)
    static let deep = Color(.sRGB, red: 11 / 255, green: 6 / 255, blue: 16 / 255)
    static let labelInk = Color(.sRGB, red: 20 / 255, green: 10 / 255, blue: 24 / 255)
    static let good = ok(0.8, 0.2, 145)
}

/// Station colour world derived from one (animated) hue, like the CSS `.theme` class.
struct Theme: Equatable {
    var hue: Double
    var acc: Color { ok(0.74, 0.19, hue) }
    var acc2: Color { ok(0.88, 0.13, hue + 60) }
    var accDeep: Color { ok(0.52, 0.22, hue) }
    var glow: Color { ok(0.74, 0.19, hue, 0.7) }
    var line: Color { ok(0.74, 0.19, hue, 0.35) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(hue: 350)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Animates the theme hue the short way round the colour wheel (the web's `--hue`
/// transition): the interpolated hue flows through the environment during the animation.
struct AnimatedTheme: ViewModifier, Animatable {
    var hue: Double
    var animatableData: Double {
        get { hue }
        set { hue = newValue }
    }

    func body(content: Content) -> some View {
        content.environment(\.theme, Theme(hue: hue))
    }
}

/// Keeps a hue "unwrapped" so animations take the shortest path (350 → 385, not 350 → 25).
func unwrapHue(_ target: Double, from prev: Double) -> Double {
    let d = (target - prev + 540).truncatingRemainder(dividingBy: 360) - 180
    return prev + d
}
