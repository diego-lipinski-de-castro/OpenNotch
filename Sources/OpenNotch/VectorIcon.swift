import CoreGraphics
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
struct VectorIconShape: Shape {
    let icon: VectorIcon

    func path(in rect: CGRect) -> Path {
        let parsed = SVGPath.parse(icon.data)
        let box = icon.viewBox
        guard box.width > 0, box.height > 0 else { return parsed }
        let scale = min(rect.width / box.width, rect.height / box.height)
        let transform = CGAffineTransform(
            translationX: rect.midX - box.midX * scale,
            y: rect.midY - box.midY * scale
        ).scaledBy(x: scale, y: scale)
        return parsed.applying(transform)
    }
}

/// Minimal SVG path parser: everything except elliptical arcs, which no mark
/// here uses. Malformed input yields a partial path rather than a crash.
enum SVGPath {
    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        let tokens = tokenize(d)
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubic: CGPoint?
        var lastQuad: CGPoint?

        func nextNumber() -> CGFloat? {
            guard index < tokens.count, case .number(let value) = tokens[index] else { return nil }
            index += 1
            return value
        }

        func nextPoint(_ relative: Bool) -> CGPoint? {
            guard let x = nextNumber(), let y = nextNumber() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            let startIndex = index
            if case .command(let c) = tokens[index] {
                command = c
                index += 1
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
                guard let x = nextNumber() else { break }
                let p = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: p); current = p
                lastCubic = nil; lastQuad = nil
            case "V":
                guard let y = nextNumber() else { break }
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
            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastCubic = nil; lastQuad = nil
            default:
                index += 1      // unsupported verb: skip it
            }

            // Nothing consumed means the data is malformed; stop rather than spin.
            if index == startIndex { break }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isLetter {
                tokens.append(.command(c))
                i += 1
            } else if c == "," || c.isWhitespace {
                i += 1
            } else {
                var j = i
                if chars[j] == "+" || chars[j] == "-" { j += 1 }
                var seenDot = false, seenExponent = false
                while j < chars.count {
                    let ch = chars[j]
                    if ch.isNumber {
                        j += 1
                    } else if ch == ".", !seenDot, !seenExponent {
                        seenDot = true; j += 1
                    } else if (ch == "e" || ch == "E"), !seenExponent, j > i {
                        seenExponent = true; j += 1
                        if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
                    } else {
                        break
                    }
                }
                guard j > i, let value = Double(String(chars[i..<j])) else { i += 1; continue }
                tokens.append(.number(CGFloat(value)))
                i = j
            }
        }
        return tokens
    }
}

/// Marks shipped for the clients that have an adapter in this repo.
enum BuiltInIcons {
    /// Anthropic's Claude symbol, via
    /// https://commons.wikimedia.org/wiki/File:Claude_AI_symbol.svg
    static let claude = VectorIcon(data: "m19.6 66.5 19.7-11 .3-1-.3-.5h-1l-3.3-.2-11.2-.3L14 53l-9.5-.5-2.4-.5L0 49l.2-1.5 2-1.3 2.9.2 6.3.5 9.5.6 6.9.4L38 49.1h1.6l.2-.7-.5-.4-.4-.4L29 41l-10.6-7-5.6-4.1-3-2-1.5-2-.6-4.2 2.7-3 3.7.3.9.2 3.7 2.9 8 6.1L37 36l1.5 1.2.6-.4.1-.3-.7-1.1L33 25l-6-10.4-2.7-4.3-.7-2.6c-.3-1-.4-2-.4-3l3-4.2L28 0l4.2.6L33.8 2l2.6 6 4.1 9.3L47 29.9l2 3.8 1 3.4.3 1h.7v-.5l.5-7.2 1-8.7 1-11.2.3-3.2 1.6-3.8 3-2L61 2.6l2 2.9-.3 1.8-1.1 7.7L59 27.1l-1.5 8.2h.9l1-1.1 4.1-5.4 6.9-8.6 3-3.5L77 13l2.3-1.8h4.3l3.1 4.7-1.4 4.9-4.4 5.6-3.7 4.7-5.3 7.1-3.2 5.7.3.4h.7l12-2.6 6.4-1.1 7.6-1.3 3.5 1.6.4 1.6-1.4 3.4-8.2 2-9.6 2-14.3 3.3-.2.1.2.3 6.4.6 2.8.2h6.8l12.6 1 3.3 2 1.9 2.7-.3 2-5.1 2.6-6.8-1.6-16-3.8-5.4-1.3h-.8v.4l4.6 4.5 8.3 7.5L89 80.1l.5 2.4-1.3 2-1.4-.2-9.2-7-3.6-3-8-6.8h-.5v.7l1.8 2.7 9.8 14.7.5 4.5-.7 1.4-2.6 1-2.7-.6-5.8-8-6-9-4.7-8.2-.5.4-2.9 30.2-1.3 1.5-3 1.2-2.5-2-1.4-3 1.4-6.2 1.6-8 1.3-6.4 1.2-7.9.7-2.6v-.2H49L43 72l-9 12.3-7.2 7.6-1.7.7-3-1.5.3-2.8L24 86l10-12.8 6-7.9 4-4.6-.1-.5h-.3L17.2 77.4l-4.7.6-2-2 .2-3 1-1 8-5.5Z")
}
