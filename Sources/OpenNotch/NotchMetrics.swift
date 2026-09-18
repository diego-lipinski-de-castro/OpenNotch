import CoreGraphics
import SwiftUI

/// Every measurement the notch panel needs, derived from the real screen cutout.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat = 185
    var notchHeight: CGFloat = 32
    /// False on displays without a cutout, where the idle shape must not be drawn.
    var hasNotch: Bool = true

    // Collapsed-but-active: how far the shape spills past the cutout.
    var wing: CGFloat = 30
    /// A shallow lip below the cutout — enough for the rounded corners to read
    /// as the notch widening, without a band of empty black.
    var depth: CGFloat = 6

    // Expanded panel. Rows carry two lines, so they are taller than the label
    // alone would need.
    var expandedWidth: CGFloat = 424
    var rowHeight: CGFloat = 42
    var footerHeight: CGFloat = 30
    var expandedPadding: CGFloat = 12

    /// Outward flare at the top corners, also the horizontal slack the window
    /// needs so the flares have somewhere to draw.
    func topRadius(expanded: Bool, active: Bool) -> CGFloat {
        if expanded { return 10 }
        return active ? 7 : 0
    }

    func bottomRadius(expanded: Bool, active: Bool) -> CGFloat {
        if expanded { return 22 }
        return active ? 11 : 0
    }

    /// Width of the black body (excluding the flares).
    func bodyWidth(expanded: Bool, active: Bool) -> CGFloat {
        if expanded { return expandedWidth }
        return active ? notchWidth + wing * 2 : notchWidth
    }

    func bodyHeight(expanded: Bool, active: Bool, rows: Int) -> CGFloat {
        if expanded {
            let list = CGFloat(max(rows, 1)) * rowHeight
            return notchHeight + list + footerHeight + expandedPadding
        }
        return active ? notchHeight + depth : notchHeight
    }

    /// Full window size, including room for the flares on both sides.
    func windowSize(expanded: Bool, active: Bool, rows: Int) -> CGSize {
        let flare = topRadius(expanded: expanded, active: active)
        return CGSize(
            width: bodyWidth(expanded: expanded, active: active) + flare * 2,
            height: bodyHeight(expanded: expanded, active: active, rows: rows)
        )
    }

    /// The largest window we ever need — used to size the hosting view once.
    func maxWindowSize(rows: Int) -> CGSize {
        let collapsed = windowSize(expanded: false, active: true, rows: rows)
        let expanded = windowSize(expanded: true, active: true, rows: rows)
        return CGSize(width: max(collapsed.width, expanded.width),
                      height: max(collapsed.height, expanded.height))
    }
}

enum Format {
    static func elapsed(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        if s < 60 { return "\(s)s" }
        let m = s / 60, rem = s % 60
        if m < 60 { return String(format: "%d:%02d", m, rem) }
        return String(format: "%dh%02dm", m / 60, m % 60)
    }
}
