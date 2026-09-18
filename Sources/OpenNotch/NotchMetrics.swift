import CoreGraphics
import SwiftUI

/// Every measurement the notch panel needs, derived from the real screen cutout.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat = 185
    var notchHeight: CGFloat = 32
    /// False on displays without a cutout, where the idle shape must not be drawn.
    var hasNotch: Bool = true

    /// How far the black spills past the sides of the cutout when something is
    /// happening. One size for every state: what is happening is said by the
    /// glyph, not by the frame.
    ///
    /// The wing has to be wider than the thing standing in it. At 28 the mark
    /// and the badge each had about nine points of black around them, which is
    /// not a margin, it is a near miss.
    ///
    /// This is the leading wing only, and it is fixed because what stands in it
    /// — the client's mark — is always the same size.
    var wing: CGFloat = 38

    /// How far the shape hangs below the cutout. Zero wherever there is a real
    /// cutout to grow out of, which is the whole point: active is the notch
    /// getting *wider*, never taller. A bar dropping down below the menu bar
    /// reads as a panel that appeared; the same content arriving to the left
    /// and right of the cutout, at exactly its height, reads as the hardware
    /// itself having more to say. Only a display with no cutout needs this,
    /// because there it has no height of its own to borrow.
    var depth: CGFloat = 22

    /// Black either side of the badge, inside the body.
    var badgeGap: CGFloat = 11
    /// Floor for the trailing wing, so a single digit does not pinch the shape.
    var minTrailingWing: CGFloat = 30

    /// The trailing wing, sized to whatever it is holding.
    ///
    /// A fixed wing has to be wide enough for the longest thing it will ever
    /// show and is therefore too wide for everything else: `1h02m` needs half
    /// again what `42s` does, so one of the two was always going to be wrong.
    /// Sizing it to the text keeps the black around the badge constant instead,
    /// and the notch grows by a few points as the clock passes a minute and
    /// again as it passes an hour.
    func trailingWing(for badge: Badge?) -> CGFloat {
        guard let badge else { return minTrailingWing }
        return max(minTrailingWing, (badge.width + badgeGap * 2).rounded())
    }

    // Expanded panel. Rows carry two lines, so they are taller than the label
    // alone would need.
    var expandedWidth: CGFloat = 436
    var rowHeight: CGFloat = 46
    var footerHeight: CGFloat = 34
    /// Black below the footer.
    ///
    /// The footer's own height already centres its labels in 34 points, so this
    /// is on top of 17 — at 12 there was nearly twice as much room under the
    /// last line as above it, and the panel sat down heavily on its bottom edge.
    var expandedPadding: CGFloat = 4
    /// Gutter for row and footer content.
    ///
    /// Bigger than a menu's, because the panel's corners are bigger than a
    /// menu's: against a 26pt continuous corner, 16pt of gutter reads as text
    /// crowding the edge rather than as a margin.
    var inset: CGFloat = 22

    /// Transparent margin the window carries around the shape so the expanded
    /// panel has somewhere to cast a shadow. Never on the top edge, which stays
    /// flush with the screen, and not carried at all while collapsed, where
    /// there is no shadow to make room for.
    ///
    /// Measured against the shadow, to the point where it stops darkening the
    /// background *at all* — not to the point where it stops being obvious.
    /// That distinction is the whole bug: a shadow cut off while it is still
    /// one part in 255 darker than the page leaves a straight edge one level
    /// deep, running the full width of the panel. Nothing in a screenshot, and
    /// perfectly visible on a good display, because the eye finds a straight
    /// line in a smooth gradient whatever its amplitude.
    ///
    /// Two numbers because the shadow is offset downward and is not
    /// symmetrical: it reaches 68 points below the shape and 43 to each side.
    var shadowPadBelow: CGFloat = 76
    var shadowPadSides: CGFloat = 52

    /// The strip the summary sits in.
    ///
    /// On a machine with a cutout this is the cutout, because the glyph's
    /// immediate neighbours are the system's own menu bar items and lining up
    /// with your neighbours is most of what makes something look like it
    /// belongs there. Elsewhere the cutout is a fiction ten points tall, and a
    /// 16pt glyph centred in it would be clipped.
    var headerHeight: CGFloat { hasNotch ? notchHeight : 30 }

    /// Height of the collapsed shape, and of the summary inside it. It is the
    /// cutout exactly where there is one, so the menu bar's centre line is also
    /// the shape's; elsewhere it has to stand up on its own.
    var collapsedHeight: CGFloat { hasNotch ? notchHeight : notchHeight + depth }

    /// Depth of the scoop where the shape rejoins the top of the screen. It
    /// grows with the panel: a scoop that stays small while the body triples in
    /// width stops reading as a blend and starts reading as a notch on a box.
    func shoulder(expanded: Bool, active: Bool) -> CGFloat {
        if expanded { return 13 }
        return active ? 7 : 0
    }

    /// Corner radius along the bottom.
    ///
    /// Collapsed, this is the only curve of the silhouette anyone can see: the
    /// cutout's own bottom corners are now inside the black and invisible, so
    /// the wings' outer corners are what the shape reads as. Kept near the
    /// cutout's own so the two look like one piece of hardware rather than a
    /// lozenge parked over it.
    ///
    /// Idle has a radius even though it draws nothing, because the value is
    /// still interpolated on the way there: at 0 the panel squared off as it
    /// faded out, which is a strange last thing to see.
    func corner(expanded: Bool, active: Bool) -> CGFloat {
        expanded ? 26 : 10
    }

    /// Width of the black body (excluding the scoops).
    func bodyWidth(expanded: Bool, active: Bool, trailing: CGFloat) -> CGFloat {
        if expanded { return expandedWidth }
        return active ? notchWidth + wing + trailing : notchWidth
    }

    /// How far the body reaches left of the cutout's left edge.
    func leadingInset(expanded: Bool, active: Bool) -> CGFloat {
        if expanded { return (expandedWidth - notchWidth) / 2 }
        return active ? wing : 0
    }

    /// How far the drawn shape sits from the middle of its window.
    ///
    /// The window stays centred on the cutout, because the cutout is the one
    /// fixed point on the screen and a window that has to move is a window that
    /// moves at the wrong moment. The shape inside it is no longer symmetric,
    /// so this is the difference, and the view carries it as an offset.
    ///
    /// Anchoring the window by its left edge instead looks equivalent and is
    /// not: while the panel closes, the window holds the *old* size so the
    /// shape has room to animate in, and pinning that oversized window to the
    /// *new* edge threw the whole thing 88 points sideways on the first frame.
    func cutoutOffset(expanded: Bool, active: Bool, trailing: CGFloat) -> CGFloat {
        bodyWidth(expanded: expanded, active: active, trailing: trailing) / 2
            - leadingInset(expanded: expanded, active: active)
            - notchWidth / 2
    }

    func bodyHeight(expanded: Bool, active: Bool, rows: Int) -> CGFloat {
        if expanded {
            let list = CGFloat(max(rows, 1)) * rowHeight
            return headerHeight + list + footerHeight + expandedPadding
        }
        return active ? collapsedHeight : notchHeight
    }

    /// The drawn shape, scoops included. This is also the hover target: the
    /// shadow margin around it must not count as part of the notch.
    func contentSize(expanded: Bool, active: Bool, rows: Int, trailing: CGFloat) -> CGSize {
        CGSize(width: bodyWidth(expanded: expanded, active: active, trailing: trailing)
                    + shoulder(expanded: expanded, active: active) * 2,
               height: bodyHeight(expanded: expanded, active: active, rows: rows))
    }

    /// Full window size: the shape, plus room for its shadow on three sides,
    /// plus whatever it takes to stay symmetric about the cutout.
    func windowSize(expanded: Bool, active: Bool, rows: Int, trailing: CGFloat) -> CGSize {
        let content = contentSize(expanded: expanded, active: active,
                                  rows: rows, trailing: trailing)
        let offset = cutoutOffset(expanded: expanded, active: active, trailing: trailing)
        let sides = expanded ? shadowPadSides : 0
        let below = expanded ? shadowPadBelow : 0
        let half = content.width / 2 + abs(offset) + sides
        return CGSize(width: half * 2, height: content.height + below)
    }
}

enum Format {
    /// Elapsed time, for the badge beside the cutout and the end of a row.
    ///
    /// Seconds on their own for the first minute, then a stopwatch. A strict
    /// `m:ss` rule is tidier on paper and produces `0:42`, which is a leading
    /// zero that never carries information, in the state the notch spends most
    /// of its life showing. Past a minute the stopwatch earns its colon.
    static func elapsed(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        if s < 60 { return "\(s)s" }
        let m = s / 60, rem = s % 60
        if m < 60 { return String(format: "%d:%02d", m, rem) }
        return String(format: "%dh%02dm", m / 60, m % 60)
    }

    /// A span that has finished. Rounded to the largest unit that still says
    /// something true: nobody reading "how long did that take" wants seconds
    /// once the answer is in hours.
    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        if s < 60 { return "\(s)s" }
        if s < 3600 {
            let m = s / 60, rem = s % 60
            return rem == 0 || m >= 10 ? "\(m)m" : "\(m)m \(rem)s"
        }
        let h = s / 3600, m = (s % 3600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
