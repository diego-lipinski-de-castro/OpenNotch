import AppKit
import SwiftUI

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
    private var bodyWidth: CGFloat { m.bodyWidth(expanded: expanded, active: active) }
    private var bodyHeight: CGFloat { m.bodyHeight(expanded: expanded, active: active, rows: rows) }
    private var flare: CGFloat { m.topRadius(expanded: expanded, active: active) }
    /// On a display without a cutout there is nothing to blend into, so the
    /// idle shape stays invisible and only serves as a hover target.
    private var shapeOpacity: Double { (active || expanded || m.hasNotch) ? 1 : 0 }

    var body: some View {
        let shape = NotchShape(topRadius: flare,
                               bottomRadius: m.bottomRadius(expanded: expanded, active: active))
        ZStack(alignment: .top) {
            shape.fill(Palette.body.opacity(shapeOpacity))
            content
        }
            .frame(width: bodyWidth + flare * 2, height: bodyHeight)
            // Content swaps instantly while the shape springs, so clip it to
            // the shape or text spills across the menu bar mid-animation.
            .clipShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.ink, contrast == .increased ? .increased : .standard)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: expanded)
            .animation(.spring(response: 0.40, dampingFraction: 0.85), value: active)
    }

    @ViewBuilder
    private var content: some View {
        if expanded {
            ExpandedPanel(store: store, registry: registry, ui: ui, m: m, flare: flare)
        } else if active {
            collapsedContent
        }
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            StatusGlyph(state: state, size: 15, style: primaryStyle)
                .frame(width: m.wing + flare, alignment: .center)

            Color.clear.frame(width: m.notchWidth)   // the physical cutout

            trailingBadge
                .frame(width: m.wing + flare, alignment: .center)
        }
        .frame(height: m.notchHeight + m.depth)
        .transition(.opacity)
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
