import CoreGraphics
import SwiftUI

/// Every measurement the notch panel needs, derived from the real screen cutout.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat = 185
    var notchHeight: CGFloat = 32
    /// False on displays without a cutout, where the idle shape must not be drawn.
    var hasNotch: Bool = true

    /// How far the shape spills past the cutout on each side, and how deep the
    /// lip below it runs. Both scale with how much the state needs a human:
    /// running is the normal case and stays nearly silent, waiting takes the
    /// whole edge. A state that cost the same as every other state would make
    /// the indicator say only "something is happening", which the user already
    /// knows.
    func wing(_ state: SessionState) -> CGFloat {
        switch state {
        case .idle:         return 0
        case .running:      return 26
        case .waiting:      return 34
        case .done, .error: return 32
        }
    }

    func depth(_ state: SessionState) -> CGFloat {
        switch state {
        case .idle:         return 0
        case .running:      return 5
        case .waiting:      return 11
        case .done, .error: return 8
        }
    }

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

    /// Tracks the lip, so the corner never eats more than the lip is deep.
    func bottomRadius(expanded: Bool, state: SessionState) -> CGFloat {
        if expanded { return 22 }
        switch state {
        case .idle:         return 0
        case .running:      return 9
        case .waiting:      return 14
        case .done, .error: return 12
        }
    }

    /// Width of the black body (excluding the flares).
    func bodyWidth(expanded: Bool, state: SessionState) -> CGFloat {
        if expanded { return expandedWidth }
        return notchWidth + wing(state) * 2
    }

    func bodyHeight(expanded: Bool, rows: Int, state: SessionState) -> CGFloat {
        if expanded {
            let list = CGFloat(max(rows, 1)) * rowHeight
            return notchHeight + list + footerHeight + expandedPadding
        }
        return notchHeight + depth(state)
    }

    /// Full window size, including room for the flares on both sides.
    func windowSize(expanded: Bool, active: Bool, rows: Int, state: SessionState) -> CGSize {
        let flare = topRadius(expanded: expanded, active: active)
        return CGSize(
            width: bodyWidth(expanded: expanded, state: state) + flare * 2,
            height: bodyHeight(expanded: expanded, rows: rows, state: state)
        )
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
