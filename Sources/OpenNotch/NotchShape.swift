import SwiftUI

/// The notch silhouette: square at the top (flush with the screen edge), rounded
/// at the bottom, and flared outward at the top corners so it reads as the notch
/// itself growing rather than a rectangle stuck underneath it.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        // Keep the flares inside the drawing rect.
        let body = rect.insetBy(dx: topRadius, dy: 0)
        let top = min(topRadius, body.height / 2)
        let bottom = min(bottomRadius, body.height - top, body.width / 2)

        var p = Path()
        p.move(to: CGPoint(x: body.minX - top, y: body.minY))
        p.addQuadCurve(to: CGPoint(x: body.minX, y: body.minY + top),
                       control: CGPoint(x: body.minX, y: body.minY))
        p.addLine(to: CGPoint(x: body.minX, y: body.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: body.minX + bottom, y: body.maxY),
                       control: CGPoint(x: body.minX, y: body.maxY))
        p.addLine(to: CGPoint(x: body.maxX - bottom, y: body.maxY))
        p.addQuadCurve(to: CGPoint(x: body.maxX, y: body.maxY - bottom),
                       control: CGPoint(x: body.maxX, y: body.maxY))
        p.addLine(to: CGPoint(x: body.maxX, y: body.minY + top))
        p.addQuadCurve(to: CGPoint(x: body.maxX + top, y: body.minY),
                       control: CGPoint(x: body.maxX, y: body.minY))
        p.closeSubpath()
        return p
    }
}
