import AppKit
import SwiftUI

/// Timing for the two things that move: the silhouette, and the content
/// crossing over inside it.
private enum Motion {
    /// `smooth` is the system's spring with the bounce taken out. A damped
    /// spring overshoots, and on a 92pt-per-side width change that overshoot
    /// reads as a wobble at the end of the expansion. Bounce is ruled out by
    /// PRODUCT.md anyway.
    static let expand = Animation.smooth(duration: 0.24)
    static let activate = Animation.smooth(duration: 0.30)

    /// The old content went to full opacity the instant hover flipped, while
    /// the shape was still a third of its final width, so you saw the middle
    /// band of a 424pt panel clipped to a notch and revealing outward. Leaving
    /// content waits for the silhouette to have room; the outgoing content
    /// leaves fast so the two never smear over each other.
    static let contentFade = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.12).delay(0.05)),
        removal: .opacity.animation(.easeOut(duration: 0.06))
    )
}

@MainActor
final class NotchUIModel: ObservableObject {
    @Published var hovered = false
    @Published var metrics = NotchMetrics()
    @Published var launchAtLogin = LoginItem.isEnabled
}

struct NotchRootView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var registry: SourceRegistry
    @ObservedObject var ui: NotchUIModel

    @Environment(\.colorSchemeContrast) private var contrast

    private var state: SessionState { store.overall.asSessionState }
    private var active: Bool { store.overall.isVisible }
    private var expanded: Bool { ui.hovered }
    private var rows: Int { max(store.activeSessions.count, 1) }

    private var m: NotchMetrics { ui.metrics }
    private var bodyWidth: CGFloat { m.bodyWidth(expanded: expanded, state: state) }
    private var bodyHeight: CGFloat { m.bodyHeight(expanded: expanded, rows: rows, state: state) }
    private var flare: CGFloat { m.topRadius(expanded: expanded, active: active) }

    /// Idle paints nothing at all.
    ///
    /// The panel is sized to the cutout's *bounding box*, but the cutout's own
    /// bottom corners are rounded, so the box includes two slivers of real
    /// screen. Filling them black drew two square nubs poking out from under
    /// the notch. Leaving them unpainted shows the menu bar, which is what is
    /// supposed to be there. Hover is polled against the window frame rather
    /// than hit-tested, so an unpainted shape is still a working target.

    var body: some View {
        let shape = NotchShape(topRadius: flare,
                               bottomRadius: m.bottomRadius(expanded: expanded, state: state))
        ZStack(alignment: .top) {
            shape.fill(Palette.body.opacity(active || expanded ? 1 : 0))
            content
        }
            .frame(width: bodyWidth + flare * 2, height: bodyHeight)
            // Content swaps instantly while the shape springs, so clip it to
            // the shape or text spills across the menu bar mid-animation.
            .clipShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.ink, contrast == .increased ? .increased : .standard)
            .animation(Motion.expand, value: expanded)
            .animation(Motion.activate, value: active)
    }

    @ViewBuilder
    private var content: some View {
        if expanded {
            ExpandedPanel(store: store, registry: registry, ui: ui, m: m, flare: flare)
                .transition(Motion.contentFade)
        } else if active {
            collapsedContent
                .transition(Motion.contentFade)
        }
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        let wing = m.wing(state) + flare
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                StatusGlyph(state: state, size: 13, style: primaryStyle)
                    .frame(width: wing, alignment: .center)

                Color.clear.frame(width: m.notchWidth)   // the physical cutout

                trailingBadge
                    .frame(width: wing, alignment: .center)
            }
            .frame(height: m.notchHeight)

            StateEdge(state: state)
                .frame(height: m.depth(state))
        }
        .frame(width: m.notchWidth + wing * 2)
    }

    /// The session the collapsed glyph speaks for: the most recent one whose
    /// state matches the aggregate, so the mark and the state agree.
    private var primarySession: Session? {
        store.activeSessions.first { store.displayState(for: $0) == state }
            ?? store.activeSessions.first
    }

    private var primaryStyle: SourceStyle? {
        primarySession.map { registry.style(for: $0.source) }
    }

    /// How many when there are several, how long when there is one. Never both.
    @ViewBuilder
    private var trailingBadge: some View {
        let tint = Palette.color(for: state)
        if store.activeSessions.count > 1 {
            Text("\(store.activeSessions.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        } else if let s = primarySession,
                  let label = Label.timer(for: s, state: store.displayState(for: s), now: store.now) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint.opacity(0.85))
        }
    }
}

/// The lit edge under the cutout, and the reason the collapsed state reads at
/// the edge of vision rather than needing to be looked at. Its depth comes from
/// `NotchMetrics.depth`; its brightness and whether it moves come from here.
///
/// Clipped by the silhouette, so the corner radius rounds its ends and it reads
/// as the notch glowing along its bottom rather than as a bar stuck underneath.
private struct StateEdge: View {
    let state: SessionState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        Rectangle()
            .fill(Palette.color(for: state).opacity(peak * (lit ? 1 : trough)))
            .onAppear(perform: start)
            .id(state)
    }

    private var peak: Double {
        switch state {
        case .idle:         return 0
        case .running:      return 0.38
        case .waiting:      return 1
        case .done, .error: return 0.9
        }
    }

    /// Only waiting breathes. Running holding still is the point: a turn in
    /// flight is the normal case and does not deserve movement down here, where
    /// the client's own mark is already turning.
    private var trough: Double { state == .waiting ? 0.5 : 1 }

    private func start() {
        guard state == .waiting, !reduceMotion else { lit = true; return }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            lit = true
        }
    }
}
