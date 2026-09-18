import SwiftUI

/// The notch silhouette.
///
/// Square across the top so it sits flush with the screen edge, scooped inward
/// where it meets that edge, and rounded along the bottom. The scoop is the
/// whole trick: a rectangle hanging off the top of the screen reads as a
/// window, and the same rectangle with its top corners blended back into the
/// edge reads as the cutout itself having grown.
///
/// Every corner is a quarter **superellipse**, not a quarter circle. A circular
/// fillet changes curvature instantly where it meets the straight edge it joins,
/// and the eye sees that discontinuity as a faint crease. Continuous curvature
/// is why the system's own corners have looked the way they do since iOS 7, and
/// a shape built from quarter-circles is one of the reliable tells that
/// something was not drawn by the platform.
struct NotchShape: Shape {
    /// Depth of the inward scoop where the shape meets the top of the screen.
    var shoulder: CGFloat
    /// Corner radius along the bottom.
    var corner: CGFloat

    /// Squareness of the bottom corners. 2 would be a circle; the system's
    /// continuous corners sit near 4.
    var cornerExponent: Double = 4
    /// The scoop is kept much closer to circular. Pushed toward 4 it stops
    /// reading as a blend and starts reading as a hook.
    var shoulderExponent: Double = 2.4

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, corner) }
        set { shoulder = newValue.first; corner = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        // The scoops are drawn outside the body, so the body has to leave them
        // room inside the rect it was given.
        let body = rect.insetBy(dx: shoulder, dy: 0)
        guard body.width > 0, body.height > 0 else { return Path() }

        let s = max(0, min(shoulder, body.height))
        let c = max(0, min(corner, body.width / 2, body.height - s))

        var p = Path()
        p.move(to: CGPoint(x: body.minX - s, y: body.minY))

        // Top left: out to the screen edge, around the corner the black
        // spills past. That corner lands inside the fill, which is what makes
        // this one read as a scoop while the identical construction at the
        // bottom reads as a rounded corner.
        p.addCorner(to: CGPoint(x: body.minX, y: body.minY + s),
                    meeting: CGPoint(x: body.minX, y: body.minY),
                    exponent: shoulderExponent)

        p.addLine(to: CGPoint(x: body.minX, y: body.maxY - c))
        p.addCorner(to: CGPoint(x: body.minX + c, y: body.maxY),
                    meeting: CGPoint(x: body.minX, y: body.maxY),
                    exponent: cornerExponent)

        p.addLine(to: CGPoint(x: body.maxX - c, y: body.maxY))
        p.addCorner(to: CGPoint(x: body.maxX, y: body.maxY - c),
                    meeting: CGPoint(x: body.maxX, y: body.maxY),
                    exponent: cornerExponent)

        p.addLine(to: CGPoint(x: body.maxX, y: body.minY + s))
        p.addCorner(to: CGPoint(x: body.maxX + s, y: body.minY),
                    meeting: CGPoint(x: body.maxX, y: body.minY),
                    exponent: shoulderExponent)

        p.closeSubpath()
        return p
    }
}

private extension Path {
    /// A quarter superellipse from wherever the path currently is, to `end`.
    ///
    /// `k` is the point where the two edges would have met — the sharp corner
    /// being replaced. The curve leaves each edge at distance `r` from `k` and
    /// is tangent to it there, which fixes its centre at the opposite corner of
    /// that square; there is exactly one such curve, so both of the shape's
    /// corner treatments are the same construction. Whether the result reads as
    /// a corner rounded off or a corner scooped out depends only on which side
    /// of the curve the fill ends up on.
    ///
    /// At `n = 2` this is a circular arc. Above it the curve hugs the original
    /// corner for longer and then turns harder, which is what continuous
    /// curvature buys: the join into the straight edge stops being a point
    /// where curvature jumps from 1/r to nothing, and the crease the eye picks
    /// up at that join goes away.
    mutating func addCorner(to end: CGPoint, meeting k: CGPoint, exponent n: Double) {
        let start = currentPoint ?? k
        let r = hypot(start.x - k.x, start.y - k.y)
        guard r > 0.01, n >= 1 else {
            addLine(to: end)
            return
        }

        // Unit vectors from the corner out along each of the two edges, and the
        // centre the curve turns about.
        let e1 = CGPoint(x: (start.x - k.x) / r, y: (start.y - k.y) / r)
        let e2 = CGPoint(x: (end.x - k.x) / r, y: (end.y - k.y) / r)
        let o = CGPoint(x: k.x + r * (e1.x + e2.x), y: k.y + r * (e1.y + e2.y))

        // Enough samples that the facets stay under a third of a pixel at 2x.
        let steps = max(10, min(32, Int(r.rounded()) * 2))
        for i in 1...steps {
            let theta = Double(i) / Double(steps) * .pi / 2
            // u^n + v^n = 1, parametrised so the samples stay evenly spread.
            let u = CGFloat(pow(cos(theta), 2 / n))
            let v = CGFloat(pow(sin(theta), 2 / n))
            addLine(to: CGPoint(x: o.x - r * (v * e1.x + u * e2.x),
                                y: o.y - r * (v * e1.y + u * e2.y)))
        }
    }
}
