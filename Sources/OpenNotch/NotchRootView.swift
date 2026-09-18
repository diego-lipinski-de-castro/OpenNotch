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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One-shot scale on the collapsed glyph when a turn starts needing a
    /// human. The pulse that then runs forever says *still waiting*; this says
    /// *started waiting*, which is a different fact and only true once.
    @State private var beat: CGFloat = 1


    private var state: SessionState { store.overall.asSessionState }
    private var active: Bool { store.overall.isVisible }
    private var expanded: Bool { ui.hovered }
    private var rows: Int { max(store.activeSessions.count, 1) }

    private var m: NotchMetrics { ui.metrics }
    private var shoulder: CGFloat { m.shoulder(expanded: expanded, active: active) }
    private var trailing: CGFloat { m.trailingWing(for: store.badge) }
    private var contentSize: CGSize {
        m.contentSize(expanded: expanded, active: active, rows: rows, trailing: trailing)
    }
    /// The shape is asymmetric about the cutout; the window is not. This is the
    /// difference, and it animates with the width so the cutout never moves.
    private var cutoutOffset: CGFloat {
        m.cutoutOffset(expanded: expanded, active: active, trailing: trailing)
    }

    /// Idle paints nothing at all.
    ///
    /// The panel is sized to the cutout's *bounding box*, but the cutout's own
    /// bottom corners are rounded, so the box includes two slivers of real
    /// screen. Filling them black drew two square nubs poking out from under
    /// the notch. Leaving them unpainted shows the menu bar, which is what is
    /// supposed to be there. Hover is polled against the window frame rather
    /// than hit-tested, so an unpainted shape is still a working target.

    var body: some View {
        let shape = NotchShape(shoulder: shoulder,
                               corner: m.corner(expanded: expanded, active: active))
        ZStack(alignment: .top) {
            shape.fill(Palette.body.opacity(active || expanded ? 1 : 0))
            content
        }
        .frame(width: contentSize.width, height: contentSize.height)
        // Content swaps while the shape springs, so clip it to the shape or
        // text spills across the menu bar mid-animation.
        .clipShape(shape)
        // The rim is drawn over the clip and clipped again, which leaves half a
        // point of light exactly on the silhouette instead of a soft point of
        // it straddling the edge.
        .overlay {
            shape.stroke(Palette.rim, lineWidth: 1)
                .clipShape(shape)
                .opacity(expanded ? 1 : 0)
        }
        // Only the expanded panel casts one, and only downward. A shadow on the
        // collapsed shape would prove it is a window sitting on the screen,
        // which is the one thing the idle and active states have to deny.
        //
        // Wide and faint rather than tight and dark. At radius 16 and half
        // black it was gone within 40 points of a 436pt-wide panel, which does
        // not read as a panel floating — it reads as a dark band ruled around
        // the outline, squarer than the shape it belongs to. A shadow says how
        // far off the surface something is, and this one is a hover, not a lift.
        .shadow(color: .black.opacity(expanded ? 0.34 : 0), radius: 28, y: 10)
        .offset(x: cutoutOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.ink, contrast == .increased ? .increased : .standard)
        .onChange(of: state) { _, now in
            // One beat when a turn starts needing a human, and none when it
            // merely carries on needing one.
            guard !reduceMotion, now == .waiting || now == .error else { return }
            withAnimation(Motion.attention) { beat = 1.24 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
                withAnimation(Motion.attention) { beat = 1 }
            }
        }
        .animation(expanded ? Motion.open(reduceMotion) : Motion.close(reduceMotion),
                   value: expanded)
        .animation(active ? Motion.activate(reduceMotion) : Motion.deactivate(reduceMotion),
                   value: active)
        .animation(Motion.open(reduceMotion), value: rows)
        // The badge outgrowing its wing as the clock passes a minute, and again
        // as it passes an hour.
        .animation(Motion.resize(reduceMotion), value: trailing)
    }

    @ViewBuilder
    private var content: some View {
        if expanded {
            ExpandedPanel(store: store, registry: registry, ui: ui, m: m)
                .transition(Motion.content(reduceMotion))
        } else if active {
            collapsedContent
                .transition(Motion.content(reduceMotion))
        }
    }

    // MARK: - Collapsed

    /// The glyph and the badge sit on the menu bar's own centre line, not the
    /// centre of the black band below it. They have the system's status items
    /// as immediate neighbours on both sides, and lining up with your
    /// neighbours is most of what makes something look like it belongs.
    private var collapsedContent: some View {
        HStack(spacing: 0) {
            StatusGlyph(state: state, size: 16, style: primaryStyle, showsIdentity: true)
                .scaleEffect(beat)
                .frame(width: m.wing, alignment: .center)

            Color.clear.frame(width: m.notchWidth)   // the physical cutout

            trailingBadge
                .frame(width: trailing, alignment: .center)
        }
        // The scoops flare outside the body, so the wings are the body's own
        // width and the scoop is padding around them. Centring the mark in
        // `wing + shoulder` instead pushed it half a scoop outward — the badge
        // ended up three points from the edge of the black while the mark had
        // nine, which is why one end always looked tighter than the other.
        .padding(.horizontal, shoulder)
        .frame(height: m.collapsedHeight)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var primaryStyle: SourceStyle? {
        store.primarySession.map { registry.style(for: $0.source) }
    }

    /// Drawn from the same `Badge` the wing was measured from, so the text and
    /// the space made for it can never disagree.
    @ViewBuilder
    private var trailingBadge: some View {
        if let badge = store.badge {
            Text(badge.text)
                .font(badge.font)
                .monospacedDigit()
                .foregroundStyle(Palette.color(for: state).opacity(badge.isCount ? 1 : 0.85))
                .lineLimit(1)
                .fixedSize()
        }
    }
}
