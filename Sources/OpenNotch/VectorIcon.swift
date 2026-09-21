import CoreGraphics
import Foundation
import SwiftUI

/// A client's brand mark, supplied as SVG path data so an icon is data rather
/// than code: built in for known clients, or set per client in sources.json
/// with `"path"` and `"viewBox"`.
struct VectorIcon: Equatable {
    var data: String
    var viewBox: CGRect

    init(data: String, viewBox: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)) {
        self.data = data
        self.viewBox = viewBox
    }

    /// Accepts the SVG attribute form: "minX minY width height".
    init?(data: String, viewBoxAttribute: String) {
        let parts = viewBoxAttribute
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return nil }
        self.init(data: data,
                  viewBox: CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]))
    }
}

/// Scales a parsed SVG path to fit a rect, preserving aspect ratio.
/// SVG and SwiftUI both put the origin top-left with y growing downward, so
/// there is no flip to undo.
///
/// With a non-zero `amplitude` the mark also *breathes*: see `breathed`.
struct VectorIconShape: Shape {
    let icon: VectorIcon
    /// Where the breath has got to, in turns. The wave is periodic in 1, so 0
    /// and 1 are the same frame and a loop can restart without a seam.
    ///
    /// Deliberately not `animatableData`. Both of these are handed a finished
    /// value per frame by whoever is driving the breath, and a shape that also
    /// interpolated them would be interpolating between two frames that are
    /// already one frame apart.
    var phase: CGFloat = 0
    /// How far the breath carries, as a fraction of each point's own distance
    /// from the middle of the mark. Zero draws the mark exactly as authored.
    var amplitude: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let parsed = SVGPath.cached(icon.data)
        let box = icon.viewBox
        guard box.width > 0, box.height > 0 else { return parsed }
        let scale = min(rect.width / box.width, rect.height / box.height)
        let transform = CGAffineTransform(
            translationX: rect.midX - box.midX * scale,
            y: rect.midY - box.midY * scale
        ).scaledBy(x: scale, y: scale)
        guard amplitude > 0 else { return parsed.applying(transform) }
        return parsed.breathed(phase: phase, amplitude: amplitude).applying(transform)
    }
}

extension Path {
    /// The mark quietly inhaling and exhaling, one arm at a time.
    ///
    /// Every point is pushed along its own radius from the middle of the mark
    /// by a fraction of how far out it already is, so the middle is nailed down
    /// and only the tips travel — arms lengthen and shorten rather than the
    /// whole thing scaling, which is the difference between something alive and
    /// something being zoomed.
    ///
    /// Which arm is out at any moment comes from two waves wrapped around the
    /// mark, one with three lobes and one with five, turning in opposite
    /// directions at the same rate. Counter-turning is the point: either wave
    /// alone is a pattern visibly going round, and the eye locks onto anything
    /// going round. Against each other they only beat, so arms rise and fall in
    /// an order you cannot predict and never resolve into a direction. Three
    /// and five are also what keeps the Claude mark's twelve arms apart: three
    /// alone would put every fourth arm in step and leave a square beating in
    /// the middle of it, and against five nothing lines up short of the same
    /// arm coming round again — all twelve are at twelve different points of
    /// the breath at every instant.
    func breathed(phase: CGFloat, amplitude: CGFloat) -> Path {
        let bounds = boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return self }
        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        let turn = 2 * CGFloat.pi

        func moved(_ p: CGPoint) -> CGPoint {
            let dx = p.x - mid.x, dy = p.y - mid.y
            let r = (dx * dx + dy * dy).squareRoot()
            guard r > 1e-6 else { return p }
            let theta = atan2(dy, dx)
            let wave = 0.62 * sin(3 * theta + turn * phase)
                     + 0.38 * sin(5 * theta - turn * phase + 0.9)
            let k = 1 + amplitude * wave
            return CGPoint(x: mid.x + dx * k, y: mid.y + dy * k)
        }

        var out = Path()
        forEach { element in
            switch element {
            case .move(let to):
                out.move(to: moved(to))
            case .line(let to):
                out.addLine(to: moved(to))
            case .quadCurve(let to, let control):
                out.addQuadCurve(to: moved(to), control: moved(control))
            case .curve(let to, let control1, let control2):
                // Control points ride the same displacement as the ends they
                // belong to, which keeps a blade's edges parallel as it moves
                // instead of letting the curve bulge sideways.
                out.addCurve(to: moved(to),
                             control1: moved(control1), control2: moved(control2))
            case .closeSubpath:
                out.closeSubpath()
            }
        }
        return out
    }
}

/// SVG path parser: the whole `d` grammar, including elliptical arcs.
/// Malformed input yields a partial path rather than a crash.
enum SVGPath {
    /// Reads the path data one token at a time, on demand.
    ///
    /// This replaced a pass that tokenised the whole string into numbers up
    /// front, which cannot represent arcs correctly. Arc flags are single
    /// characters and the grammar lets them run together with what follows, so
    /// `0 0 1 5 5` and `0015 5` mean the same thing — and a tokeniser with no
    /// idea which argument it is reading turns the second into the number 15.
    /// Gemini's mark is written that way, and every arc in it came out wrong.
    /// Reading on demand means the parser knows when it wants a flag.
    private struct Scanner {
        let chars: [Character]
        var index = 0

        mutating func skipSeparators() {
            while index < chars.count, chars[index] == "," || chars[index].isWhitespace {
                index += 1
            }
        }

        mutating func nextCommand() -> Character? {
            skipSeparators()
            guard index < chars.count, chars[index].isLetter else { return nil }
            defer { index += 1 }
            return chars[index]
        }

        mutating func startsNumber() -> Bool {
            skipSeparators()
            guard index < chars.count else { return false }
            let c = chars[index]
            return c.isNumber || c == "." || c == "-" || c == "+"
        }

        mutating func nextNumber() -> CGFloat? {
            skipSeparators()
            let start = index
            var j = index
            if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
            var seenDot = false, seenExponent = false
            while j < chars.count {
                let c = chars[j]
                if c.isNumber {
                    j += 1
                } else if c == ".", !seenDot, !seenExponent {
                    seenDot = true; j += 1
                } else if c == "e" || c == "E", !seenExponent, j > start {
                    seenExponent = true; j += 1
                    if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
                } else {
                    break
                }
            }
            guard j > start, let value = Double(String(chars[start..<j])) else { return nil }
            index = j
            return CGFloat(value)
        }

        /// An arc flag is exactly one character, `0` or `1`, and is allowed to
        /// carry no separator at all.
        mutating func nextFlag() -> Bool? {
            skipSeparators()
            guard index < chars.count else { return nil }
            switch chars[index] {
            case "0": index += 1; return false
            case "1": index += 1; return true
            default: return nil
            }
        }
    }

    /// Parsed once per distinct `d` string.
    ///
    /// Parsing was cheap enough when a mark was drawn once and then sat still:
    /// 200µs, once. A breathing mark asks for its path sixty times a second for
    /// as long as a turn runs, and the answer to the parse never changes — only
    /// what is done to it afterwards does.
    ///
    /// Behind a lock, and holding a `CGPath` rather than a `Path`, because a
    /// shape is not asked for its path on the main thread alone. Reading this
    /// dictionary while another mark writes it is a data race; handing a
    /// `Path` between threads before it has realised its storage is a second
    /// one. Either shows up as the odd frame where the mark comes out empty,
    /// which on screen is the mark blinking — rare enough to look like a
    /// display glitch and frequent enough to be maddening. A `CGPath` is
    /// immutable once built, so the dictionary is the only thing left to guard.
    private static let lock = NSLock()
    private static var parsed: [String: CGPath] = [:]

    static func cached(_ d: String) -> Path {
        lock.lock()
        let hit = parsed[d]
        lock.unlock()
        if let hit { return Path(hit) }
        // Two marks arriving together may both parse the same string. That
        // costs one extra parse; holding the lock across the parse would cost
        // every other mark on screen a wait for it.
        let built = parse(d).cgPath
        lock.lock()
        parsed[d] = built
        lock.unlock()
        return Path(built)
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        var scanner = Scanner(chars: Array(d))
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubic: CGPoint?
        var lastQuad: CGPoint?

        func nextPoint(_ relative: Bool) -> CGPoint? {
            guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            let before = scanner.index
            if let c = scanner.nextCommand() {
                command = c
            } else if !scanner.startsNumber() {
                break       // Neither a command nor an implicit repeat: done.
            }

            let relative = command.isLowercase
            guard let verb = command.uppercased().first else { break }

            switch verb {
            case "M":
                guard let p = nextPoint(relative) else { break }
                path.move(to: p)
                current = p
                subpathStart = p
                // Further coordinate pairs after a moveto are implicit linetos.
                command = relative ? "l" : "L"
                lastCubic = nil; lastQuad = nil
            case "L":
                guard let p = nextPoint(relative) else { break }
                path.addLine(to: p); current = p
                lastCubic = nil; lastQuad = nil
            case "H":
                guard let x = scanner.nextNumber() else { break }
                let p = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: p); current = p
                lastCubic = nil; lastQuad = nil
            case "V":
                guard let y = scanner.nextNumber() else { break }
                let p = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: p); current = p
                lastCubic = nil; lastQuad = nil
            case "C":
                guard let c1 = nextPoint(relative),
                      let c2 = nextPoint(relative),
                      let p = nextPoint(relative) else { break }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p; lastCubic = c2; lastQuad = nil
            case "S":
                guard let c2 = nextPoint(relative), let p = nextPoint(relative) else { break }
                let c1 = lastCubic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p; lastCubic = c2; lastQuad = nil
            case "Q":
                guard let c = nextPoint(relative), let p = nextPoint(relative) else { break }
                path.addQuadCurve(to: p, control: c)
                current = p; lastQuad = c; lastCubic = nil
            case "T":
                guard let p = nextPoint(relative) else { break }
                let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addQuadCurve(to: p, control: c)
                current = p; lastQuad = c; lastCubic = nil
            case "A":
                guard let rx = scanner.nextNumber(), let ry = scanner.nextNumber(),
                      let rotation = scanner.nextNumber(),
                      let largeArc = scanner.nextFlag(), let sweep = scanner.nextFlag(),
                      let p = nextPoint(relative) else { break }
                path.addSVGArc(from: current, to: p, rx: rx, ry: ry,
                               rotation: rotation, largeArc: largeArc, sweep: sweep)
                current = p; lastCubic = nil; lastQuad = nil
            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastCubic = nil; lastQuad = nil
            default:
                break       // Unknown verb: its arguments are skipped below.
            }

            // Nothing consumed means the data is malformed; stop rather than spin.
            if scanner.index == before { break }
        }
        return path
    }
}

private extension Path {
    /// SVG's elliptical arc, converted to cubic Béziers.
    ///
    /// This used to be the one verb the parser skipped, and skipping it is
    /// worse than it sounds: the command token was dropped but its seven
    /// numbers were not, so they were read as arguments to whatever came
    /// before and the whole rest of the path came out scrambled. Most icon
    /// sets round their corners with arcs, so "unsupported" meant "silently
    /// mangled" for a good share of real artwork.
    mutating func addSVGArc(from p0: CGPoint, to p1: CGPoint,
                            rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat,
                            largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        // Zero radii, or an arc that goes nowhere, is a straight line.
        guard rx > 1e-9, ry > 1e-9,
              abs(p0.x - p1.x) > 1e-12 || abs(p0.y - p1.y) > 1e-12 else {
            addLine(to: p1)
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        // Endpoint to centre parameterisation, SVG spec F.6.5.
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 =  cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        // Radii too small to reach between the endpoints are scaled up (F.6.6)
        // rather than treated as an error.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
        }

        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let scale = denominator > 0
            ? (largeArc == sweep ? -1 : 1) * sqrt(max(0, numerator) / denominator)
            : 0
        let cxp =  scale * rx * y1 / ry
        let cyp = -scale * ry * x1 / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let length = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            guard length > 0 else { return 0 }
            let a = acos(max(-1, min(1, (ux * vx + uy * vy) / length)))
            return ux * vy - uy * vx < 0 ? -a : a
        }

        let ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry
        let vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry
        var theta = angle(1, 0, ux, uy)
        var sweepAngle = angle(ux, uy, vx, vy)
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        // A single cubic cannot hold much more than a quarter turn before the
        // error shows, so the arc is split into quarters or finer.
        let steps = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let step = sweepAngle / CGFloat(steps)
        let k = 4.0 / 3.0 * tan(step / 4)

        func onArc(_ t: CGFloat) -> (point: CGPoint, slope: CGPoint) {
            let c = cos(t), s = sin(t)
            return (CGPoint(x: cx + cosPhi * rx * c - sinPhi * ry * s,
                            y: cy + sinPhi * rx * c + cosPhi * ry * s),
                    CGPoint(x: -cosPhi * rx * s - sinPhi * ry * c,
                            y: -sinPhi * rx * s + cosPhi * ry * c))
        }

        for _ in 0..<steps {
            let a = onArc(theta), b = onArc(theta + step)
            addCurve(to: b.point,
                     control1: CGPoint(x: a.point.x + k * a.slope.x,
                                       y: a.point.y + k * a.slope.y),
                     control2: CGPoint(x: b.point.x - k * b.slope.x,
                                       y: b.point.y - k * b.slope.y))
            theta += step
        }
    }
}

/// Marks shipped for the clients that have an adapter in this repo.
enum BuiltInIcons {
    /// Anthropic's Claude symbol, via
    /// https://commons.wikimedia.org/wiki/File:Claude_AI_symbol.svg
    static let claude = VectorIcon(data: "m19.6 66.5 19.7-11 .3-1-.3-.5h-1l-3.3-.2-11.2-.3L14 53l-9.5-.5-2.4-.5L0 49l.2-1.5 2-1.3 2.9.2 6.3.5 9.5.6 6.9.4L38 49.1h1.6l.2-.7-.5-.4-.4-.4L29 41l-10.6-7-5.6-4.1-3-2-1.5-2-.6-4.2 2.7-3 3.7.3.9.2 3.7 2.9 8 6.1L37 36l1.5 1.2.6-.4.1-.3-.7-1.1L33 25l-6-10.4-2.7-4.3-.7-2.6c-.3-1-.4-2-.4-3l3-4.2L28 0l4.2.6L33.8 2l2.6 6 4.1 9.3L47 29.9l2 3.8 1 3.4.3 1h.7v-.5l.5-7.2 1-8.7 1-11.2.3-3.2 1.6-3.8 3-2L61 2.6l2 2.9-.3 1.8-1.1 7.7L59 27.1l-1.5 8.2h.9l1-1.1 4.1-5.4 6.9-8.6 3-3.5L77 13l2.3-1.8h4.3l3.1 4.7-1.4 4.9-4.4 5.6-3.7 4.7-5.3 7.1-3.2 5.7.3.4h.7l12-2.6 6.4-1.1 7.6-1.3 3.5 1.6.4 1.6-1.4 3.4-8.2 2-9.6 2-14.3 3.3-.2.1.2.3 6.4.6 2.8.2h6.8l12.6 1 3.3 2 1.9 2.7-.3 2-5.1 2.6-6.8-1.6-16-3.8-5.4-1.3h-.8v.4l4.6 4.5 8.3 7.5L89 80.1l.5 2.4-1.3 2-1.4-.2-9.2-7-3.6-3-8-6.8h-.5v.7l1.8 2.7 9.8 14.7.5 4.5-.7 1.4-2.6 1-2.7-.6-5.8-8-6-9-4.7-8.2-.5.4-2.9 30.2-1.3 1.5-3 1.2-2.5-2-1.4-3 1.4-6.2 1.6-8 1.3-6.4 1.2-7.9.7-2.6v-.2H49L43 72l-9 12.3-7.2 7.6-1.7.7-3-1.5.3-2.8L24 86l10-12.8 6-7.9 4-4.6-.1-.5h-.3L17.2 77.4l-4.7.6-2-2 .2-3 1-1 8-5.5Z")

    /// Cursor's cube, via the Simple Icons set.
    static let cursor = VectorIcon(
        data: "M11.503.131 1.891 5.678a.84.84 0 0 0-.42.726v11.188c0 .3.162.575.42.724l9.609 5.55a1 1 0 0 0 .998 0l9.61-5.55a.84.84 0 0 0 .42-.724V6.404a.84.84 0 0 0-.42-.726L12.497.131a1.01 1.01 0 0 0-.996 0M2.657 6.338h18.55c.263 0 .43.287.297.515L12.23 22.918c-.062.107-.229.064-.229-.06V12.335a.59.59 0 0 0-.295-.51l-9.11-5.257c-.109-.063-.064-.23.061-.23",
        viewBox: CGRect(x: 0, y: 0, width: 24, height: 24))

    /// Google's Gemini spark, via
    /// https://commons.wikimedia.org/wiki/File:Google_Gemini_icon_2025.svg
    static let gemini = VectorIcon(
        data: "M32.447 0c.68 0 1.273.465 1.439 1.125a38.904 38.904 0 001.999 5.905c2.152 5 5.105 9.376 8.854 13.125 3.751 3.75 8.126 6.703 13.125 8.855a38.98 38.98 0 005.906 1.999c.66.166 1.124.758 1.124 1.438 0 .68-.464 1.273-1.125 1.439a38.902 38.902 0 00-5.905 1.999c-5 2.152-9.375 5.105-13.125 8.854-3.749 3.751-6.702 8.126-8.854 13.125a38.973 38.973 0 00-2 5.906 1.485 1.485 0 01-1.438 1.124c-.68 0-1.272-.464-1.438-1.125a38.913 38.913 0 00-2-5.905c-2.151-5-5.103-9.375-8.854-13.125-3.75-3.749-8.125-6.702-13.125-8.854a38.973 38.973 0 00-5.905-2A1.485 1.485 0 010 32.448c0-.68.465-1.272 1.125-1.438a38.903 38.903 0 005.905-2c5-2.151 9.376-5.104 13.125-8.854 3.75-3.749 6.703-8.125 8.855-13.125a38.972 38.972 0 001.999-5.905A1.485 1.485 0 0132.447 0z",
        viewBox: CGRect(x: 0, y: 0, width: 65, height: 65))

    /// OpenAI's mark, which is what Codex signs itself with, via
    /// https://commons.wikimedia.org/wiki/File:ChatGPT-Logo.svg
    static let openAI = VectorIcon(
        data: "m297.06 130.97c7.26-21.79 4.76-45.66-6.85-65.48-17.46-30.4-52.56-46.04-86.84-38.68-15.25-17.18-37.16-26.95-60.13-26.81-35.04-.08-66.13 22.48-76.91 55.82-22.51 4.61-41.94 18.7-53.31 38.67-17.59 30.32-13.58 68.54 9.92 94.54-7.26 21.79-4.76 45.66 6.85 65.48 17.46 30.4 52.56 46.04 86.84 38.68 15.24 17.18 37.16 26.95 60.13 26.8 35.06.09 66.16-22.49 76.94-55.86 22.51-4.61 41.94-18.7 53.31-38.67 17.57-30.32 13.55-68.51-9.94-94.51zm-120.28 168.11c-14.03.02-27.62-4.89-38.39-13.88.49-.26 1.34-.73 1.89-1.07l63.72-36.8c3.26-1.85 5.26-5.32 5.24-9.07v-89.83l26.93 15.55c.29.14.48.42.52.74v74.39c-.04 33.08-26.83 59.9-59.91 59.97zm-128.84-55.03c-7.03-12.14-9.56-26.37-7.15-40.18.47.28 1.3.79 1.89 1.13l63.72 36.8c3.23 1.89 7.23 1.89 10.47 0l77.79-44.92v31.1c.02.32-.13.63-.38.83l-64.41 37.19c-28.69 16.52-65.33 6.7-81.92-21.95zm-16.77-139.09c7-12.16 18.05-21.46 31.21-26.29 0 .55-.03 1.52-.03 2.2v73.61c-.02 3.74 1.98 7.21 5.23 9.06l77.79 44.91-26.93 15.55c-.27.18-.61.21-.91.08l-64.42-37.22c-28.63-16.58-38.45-53.21-21.95-81.89zm221.26 51.49-77.79-44.92 26.93-15.54c.27-.18.61-.21.91-.08l64.42 37.19c28.68 16.57 38.51 53.26 21.94 81.94-7.01 12.14-18.05 21.44-31.2 26.28v-75.81c.03-3.74-1.96-7.2-5.2-9.06zm26.8-40.34c-.47-.29-1.3-.79-1.89-1.13l-63.72-36.8c-3.23-1.89-7.23-1.89-10.47 0l-77.79 44.92v-31.1c-.02-.32.13-.63.38-.83l64.41-37.16c28.69-16.55 65.37-6.7 81.91 22 6.99 12.12 9.52 26.31 7.15 40.1zm-168.51 55.43-26.94-15.55c-.29-.14-.48-.42-.52-.74v-74.39c.02-33.12 26.89-59.96 60.01-59.94 14.01 0 27.57 4.92 38.34 13.88-.49.26-1.33.73-1.89 1.07l-63.72 36.8c-3.26 1.85-5.26 5.31-5.24 9.06l-.04 89.79zm14.63-31.54 34.65-20.01 34.65 20v40.01l-34.65 20-34.65-20z",
        viewBox: CGRect(x: 0, y: 0, width: 320, height: 320))
}
