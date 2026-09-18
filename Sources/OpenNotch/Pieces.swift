import AppKit
import SwiftUI

// MARK: - Status glyph

/// Small state indicator: an arc while running, a pulse while waiting, a check
/// when finished, a bang when it failed.
///
/// Every state has a distinct silhouette, so the glyph stays readable when the
/// colour does not.
struct StatusGlyph: View {
    let state: SessionState
    let size: CGFloat
    /// The client this glyph speaks for, when it has one.
    let style: SourceStyle?
    /// True beside the cutout, false inside the open panel. Out there a running
    /// turn is drawn as the client's mark; in here it is not drawn at all.
    let showsIdentity: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    /// The state actually being drawn, mirrored from the one passed in.
    ///
    /// It exists only to own the crossfade, and it has to be `@State` seeded
    /// from the property for the crossfade to happen at all. Views up the tree
    /// scope their animations to `expanded` and `active` with
    /// `.animation(_:value:)`, and a scope keyed on a value that did not change
    /// leaves everything under it with no animation to inherit — so a swap
    /// driven straight off the store landed in a single frame, whatever
    /// transition was attached here. Assigning it inside an explicit
    /// `withAnimation` is a transaction nothing upstream can take away.
    ///
    /// Seeding matters as much as the mirror: written as `shown ?? state` with
    /// an optional behind it, the glyph falls back to the new value the instant
    /// the property changes and there is nothing left to cross from.
    @State private var shown: SessionState

    init(state: SessionState, size: CGFloat = 12,
         style: SourceStyle? = nil, showsIdentity: Bool = false) {
        self.state = state
        self.size = size
        self.style = style
        self.showsIdentity = showsIdentity
        _shown = State(initialValue: state)
    }

    /// Keyed to the glyph being drawn, not the one just reported. Taken from
    /// the incoming state, the outgoing glyph recolours a frame before it
    /// leaves, and for 200ms the panel shows a running ring in failure red.
    private var color: Color { Palette.color(for: shown) }

    /// One state's glyph giving way to another's. The arriving one comes up
    /// from slightly under size; the leaving one barely shrinks, so for the
    /// 150ms they overlap there is one shape on screen rather than two.
    private static let swap = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.7)),
        removal: .opacity.combined(with: .scale(scale: 0.88))
    )

    var body: some View {
        // The `id` belongs on the individual marks, not on the whole glyph.
        // Hung on the outside it replaced the view wholesale on every state
        // change, which meant there was no old glyph left for the new one to
        // cross with and the swap landed in a single frame. Inside, it does
        // only what it is for: restarting a mark's own loop when the client or
        // the Reduce Motion setting changes underneath it.
        Group {
            switch shown {
            case .running:
                runningMark
                    .id("running-\(style?.id ?? "")-\(reduceMotion)")
                    .transition(Self.swap)
            case .waiting:
                waitingMark
                    .id("waiting-\(reduceMotion)")
                    .transition(Self.swap)
            case .done:
                symbol("checkmark", scale: 0.72).transition(Self.swap)
            case .error:
                symbol("exclamationmark", scale: 0.92).transition(Self.swap)
            case .idle:
                Circle().fill(Palette.idle.opacity(0.4))
                    .frame(width: size * 0.5)
                    .transition(Self.swap)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: state) { _, now in
            withAnimation(Motion.glyph(reduceMotion)) { shown = now }
        }
    }

    /// Running.
    ///
    /// Beside the cutout it is the client's own mark, standing still. Inside the
    /// panel it is nothing at all: the row already names the client on the left
    /// and shows a clock on the right, and a turn in flight is the ordinary case
    /// — the case that earns no badge.
    ///
    /// Nothing in the product rotates any more. A turn in flight is what the
    /// notch looks like for most of the working day, and something moving in the
    /// corner of your eye all day is something you train yourself to stop
    /// seeing — which costs you the one state that genuinely needs you. Motion
    /// now means waiting, everywhere, and nothing else.
    @ViewBuilder
    private var runningMark: some View {
        if !showsIdentity {
            // Holds its slot so the swap to a state that does have a glyph can
            // still cross rather than pop.
            Color.clear
        } else if let style {
            SourceMark(style: style, size: size * 0.8)
        } else {
            // No client to speak for: an outline, which is still a silhouette
            // no other state uses. Never a filled disc — that is waiting.
            Circle()
                .stroke(color, lineWidth: max(1.5, size * 0.1))
                .padding(max(0.75, size * 0.06))
        }
    }

    /// Reduce Motion drops the pulse but keeps the disc, which is already the
    /// one silhouette no other state uses.
    private var waitingMark: some View {
        Circle()
            .fill(color)
            .frame(width: size * 0.68, height: size * 0.68)
            .scaleEffect(pulse ? 1 : 0.7)
            .opacity(pulse ? 1 : 0.55)
            .onAppear {
                guard !reduceMotion else { pulse = true; return }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }

    private func symbol(_ name: String, scale: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * scale, weight: .semibold))
            .foregroundStyle(color)
    }
}

/// A client's identifying mark: its own vector if it has one, else its
/// SF Symbol, else the generic fallback. Identity only — never state.
struct SourceMark: View {
    let style: SourceStyle
    var size: CGFloat = 14

    @Environment(\.ink) private var ink

    var body: some View {
        let tint = style.accent ?? Palette.ink(ink.secondary)
        Group {
            if let vector = style.vector {
                VectorIconShape(icon: vector).fill(tint)
            } else {
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.82, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - The collapsed badge

/// What the badge beside the cutout says, and how much room it needs.
///
/// The view draws it and the controller sizes the window around it, so the two
/// have to agree on its width *before* anything is laid out — which is why this
/// measures itself with AppKit rather than letting SwiftUI discover the width
/// during layout and reporting it back a frame later.
struct Badge: Equatable {
    var text: String
    /// How many sessions, rather than how long one has been going.
    var isCount: Bool

    var font: Font {
        isCount ? .system(size: 12, weight: .semibold)
                : .system(size: 10.5, weight: .medium)
    }

    private var measuringFont: NSFont {
        isCount ? .systemFont(ofSize: 12, weight: .semibold)
                : .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
    }

    /// Cached because this is asked once per frame per badge while the panel
    /// animates, and the answer only changes when the text does.
    private static var widths: [String: CGFloat] = [:]

    var width: CGFloat {
        let key = "\(isCount)|\(text)"
        if let w = Self.widths[key] { return w }
        let w = (text as NSString)
            .size(withAttributes: [.font: measuringFont]).width
            .rounded(.up)
        Self.widths[key] = w
        return w
    }
}

extension SessionStore {
    /// The session the collapsed indicator speaks for: the most recent one
    /// whose state matches the aggregate, so the mark and the state agree.
    var primarySession: Session? {
        let s = overall.asSessionState
        return activeSessions.first { displayState(for: $0) == s } ?? activeSessions.first
    }

    /// How many when there are several, how long when there is one. Never both.
    var badge: Badge? {
        if activeSessions.count > 1 {
            return Badge(text: "\(activeSessions.count)", isCount: true)
        }
        guard let s = primarySession,
              let label = Label.timer(for: s, state: displayState(for: s), now: now)
        else { return nil }
        return Badge(text: label, isCount: false)
    }
}

// MARK: - Panel furniture

struct Hairline: View {
    @Environment(\.ink) private var ink

    var body: some View {
        Rectangle().fill(Palette.ink(ink.rule)).frame(height: 1)
    }
}

/// A menu item: a label that takes a highlight under the cursor.
///
/// The panel claims to be a menu, and a menu item that does not light up when
/// you point at it is the thing that gives away that it is a picture of one.
private struct MenuItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Item(configuration: configuration)
    }

    private struct Item: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.highlight(hovering))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(configuration.isPressed ? 0.55 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.1), value: hovering)
        }
    }
}

/// Two menu items, not a settings pane.
///
/// This was an AppKit checkbox beside a plain text button, which is two control
/// vocabularies in one row: the checkbox brought its own metrics and system
/// tinting, so nothing lined up and the one piece of chrome in the product was
/// sitting in the corner of an otherwise black panel. A leading checkmark that
/// occupies its slot whether or not it is drawn is how the system's own menus
/// show a toggled item, and it lets both controls share one font and one
/// baseline.
struct PanelFooter: View {
    @ObservedObject var ui: NotchUIModel

    @Environment(\.ink) private var ink

    var body: some View {
        HStack(spacing: 0) {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit").foregroundStyle(Palette.ink(ink.tertiary))
            }

            Spacer(minLength: 12)

            Button {
                ui.launchAtLogin = LoginItem.set(!ui.launchAtLogin)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        // Reserved, not conditional: a label that shifts
                        // sideways when you toggle it is the tell.
                        .opacity(ui.launchAtLogin ? 1 : 0)
                        .frame(width: 9, alignment: .leading)
                    Text("Open at login")
                }
                .foregroundStyle(Palette.ink(ui.launchAtLogin ? ink.secondary : ink.tertiary))
            }
            .accessibilityLabel("Open at login")
            .accessibilityAddTraits(ui.launchAtLogin ? [.isSelected] : [])
        }
        // One font and one button style for both, which is what makes them
        // share a baseline. The inset cancels the style's own padding, so the
        // labels line up with the rows above rather than the highlights do.
        .font(.system(size: 12))
        .buttonStyle(MenuItemStyle())
        .padding(.horizontal, -7)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Shared formatting

enum Label {
    /// How long, for whichever sense of long applies; nil when neither does, so
    /// callers can drop the column entirely.
    ///
    /// One format for every state, because these are a column and a column with
    /// two formats in it is a column you have to read twice. `Format.duration`
    /// still exists and is what VoiceOver hears, where "1m 38s" reads better
    /// than a colon and there is no column to keep narrow.
    static func timer(for session: Session, state: SessionState, now: Date) -> String? {
        switch state {
        case .running, .waiting:
            guard let started = session.started else { return nil }
            return Format.elapsed(now.timeIntervalSince(started))
        case .done, .error:
            guard let d = session.lastDuration else { return nil }
            return Format.elapsed(d)
        case .idle:
            return nil
        }
    }

    /// The directory a session is working in, shortened for display. Sessions
    /// often share a folder name, and this is what tells them apart.
    static func home(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let shortened = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        return (shortened as NSString).deletingLastPathComponent
    }

    /// What a session is doing, in the system's voice: plain and short. The
    /// panel says this with a glyph and a number; VoiceOver gets the sentence.
    static func detail(_ session: Session, _ state: SessionState, _ now: Date) -> String {
        switch state {
        case .running:
            guard let started = session.started else { return "running" }
            return "running for \(Format.duration(now.timeIntervalSince(started)))"
        case .waiting:
            guard let started = session.started else { return "waiting for you" }
            return "waiting for you for \(Format.duration(now.timeIntervalSince(started)))"
        case .done:
            if let d = session.lastDuration { return "done in \(Format.duration(d))" }
            return "done"
        case .error:
            if let d = session.lastDuration { return "failed after \(Format.duration(d))" }
            return "failed"
        case .idle:
            return "idle"
        }
    }
}
