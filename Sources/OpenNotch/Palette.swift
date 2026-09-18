import SwiftUI

/// Colours are authored in OKLCH and converted to sRGB at first use.
///
/// The point is perceptual control: the five states have to be separable by
/// something other than hue (see PRODUCT.md, "never color-only"), so their
/// lightness is laid out as a deliberate ladder rather than falling out of
/// whatever hex values looked right. Read `l` as "how loud" and it is obvious
/// that waiting is the loudest thing on screen and running is nearly silent.
struct OKLCH {
    var l: Double
    var c: Double
    var h: Double

    var color: Color {
        let (r, g, b) = Self.srgb(l: l, c: c, h: h)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// OKLCH -> OKLab -> linear sRGB -> gamma-encoded sRGB.
    static func srgb(l: Double, c: Double, h: Double) -> (Double, Double, Double) {
        let rad = h * .pi / 180
        let a = c * cos(rad)
        let bb = c * sin(rad)

        let l_ = l + 0.3963377774 * a + 0.2158037573 * bb
        let m_ = l - 0.1055613458 * a - 0.0638541728 * bb
        let s_ = l - 0.0894841775 * a - 1.2914855480 * bb

        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_

        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let b = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S

        return (encode(r), encode(g), encode(b))
    }

    private static func encode(_ x: Double) -> Double {
        let v = max(0, min(1, x))
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}

enum Palette {
    /// The hue everything neutral is tinted toward. Cool, so the panel never
    /// reads warm against the menu bar.
    static let baseHue: Double = 250

    // State colours. Lightness is the separable channel: 0.82 > 0.70 > 0.62
    // survives deuteranopia even where the hues collapse into each other.
    private static let runningLCH = OKLCH(l: 0.74, c: 0.028, h: baseHue)
    private static let waitingLCH = OKLCH(l: 0.82, c: 0.160, h: 80)
    private static let doneLCH    = OKLCH(l: 0.70, c: 0.130, h: 152)
    private static let errorLCH   = OKLCH(l: 0.62, c: 0.200, h: 27)
    private static let idleLCH    = OKLCH(l: 0.55, c: 0.008, h: baseHue)

    /// Running is intentionally near-neutral. A turn in flight is the normal
    /// case and does not deserve a colour of its own; when the client has a
    /// mark, that mark carries the identity instead.
    static let running = runningLCH.color
    static let waiting = waitingLCH.color
    static let done    = doneLCH.color
    static let error   = errorLCH.color
    static let idle    = idleLCH.color

    /// The panel body. This is the one place pure black is correct: the panel
    /// has to be indistinguishable from a physical hole in the display, and any
    /// tint at all would show the seam. Everything else is tinted.
    static let body = Color.black

    /// Tinted neutral for text and rules. Chroma is low enough to be
    /// imperceptible as colour and high enough to stop the panel reading grey.
    static func ink(_ opacity: Double) -> Color {
        OKLCH(l: 0.97, c: 0.006, h: baseHue).color.opacity(opacity)
    }

    static func color(for state: SessionState) -> Color {
        switch state {
        case .running: return running
        case .waiting: return waiting
        case .done:    return done
        case .error:   return error
        case .idle:    return idle
        }
    }

    static func color(for state: OverallState) -> Color {
        color(for: state.asSessionState)
    }

    /// How much of the user's attention a state is allowed to take, 0...1.
    /// The panel sorts by it, so whatever needs a human is always on top.
    static func urgency(for state: SessionState) -> Double {
        switch state {
        case .idle:    return 0
        case .running: return 0.18
        case .done:    return 0.55
        case .error:   return 0.85
        case .waiting: return 1
        }
    }
}

/// Text opacities on the black body, named by role rather than by number so
/// there is one place to check them against WCAG.
///
/// The floor is `tertiary`. Anything dimmer than 0.50 white on black drops
/// under 4.5:1 and stops being body text, which is how the old panel ended up
/// with 2.5:1 client labels. Increase Contrast raises the whole scale.
struct InkScale: Equatable {
    var primary: Double
    var secondary: Double
    var tertiary: Double
    var rule: Double

    /// tertiary 0.50 measures 4.9:1 against the body; 0.45 measures 4.1:1.
    static let standard = InkScale(primary: 0.95, secondary: 0.74, tertiary: 0.50, rule: 0.08)
    static let increased = InkScale(primary: 1, secondary: 0.90, tertiary: 0.76, rule: 0.20)
}

private struct InkScaleKey: EnvironmentKey {
    static let defaultValue = InkScale.standard
}

extension EnvironmentValues {
    var ink: InkScale {
        get { self[InkScaleKey.self] }
        set { self[InkScaleKey.self] = newValue }
    }
}
