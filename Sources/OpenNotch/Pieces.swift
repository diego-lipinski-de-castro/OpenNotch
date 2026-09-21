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
    /// Beside the cutout it is the client's own mark, breathing. Inside the
    /// panel it is nothing at all: the row already names the client on the left
    /// and shows a clock on the right, and a turn in flight is the ordinary case
    /// — the case that earns no badge.
    ///
    /// Nothing rotates, and nothing here travels: the mark keeps its place, its
    /// size and its colour, and only its arms lengthen and shorten, by about a
    /// point each, in an order that never resolves into a direction. That is
    /// the whole point of the shape it was given — there is nothing in it for
    /// the eye to follow, so it does not pull at you from the edge of vision
    /// the way a spinner does. You see it when you look at the notch.
    ///
    /// Waiting keeps every louder register to itself. An arm here takes 1.25s
    /// to go out and the same to come back, against the pulse's 0.85s each way
    /// — but the gap that matters is not the tempo, it is what moves: waiting
    /// takes the whole glyph up and down in size and down to half opacity,
    /// while running never changes size, position or opacity at all and only
    /// ever redraws its own outline. That is what keeps them apart at a glance,
    /// which is the only test either of them has to pass.
    @ViewBuilder
    private var runningMark: some View {
        if !showsIdentity {
            // Holds its slot so the swap to a state that does have a glyph can
            // still cross rather than pop.
            Color.clear
        } else if let style {
            SourceMark(style: style, size: size * 0.8, breathing: true)
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
///
/// `breathing` is the one exception, and only just: it does not change which
/// mark is drawn or how it reads, it only lets the one already standing there
/// show that its turn is still going. It is set beside the cutout, and on the
/// panel row belonging to a session that is mid-turn — the same mark, saying
/// the same thing, in both places.
struct SourceMark: View {
    let style: SourceStyle
    var size: CGFloat = 14
    /// True while this client's turn is in flight. Turning it off does not cut
    /// the breath off where it stood: the mark eases back to the shape it was
    /// drawn as, and only then stops being redrawn at all.
    var breathing: Bool = false

    @Environment(\.ink) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far an arm reaches past where it was drawn, as a share of its own
    /// length: about a point either way at the 12.8pt the mark gets beside the
    /// cutout, so a bit over two points between an arm at full stretch and the
    /// same arm drawn back. Tuned at that size and nowhere else.
    ///
    /// This started at half as much, which was the right answer on paper and
    /// the wrong one on a screen: correct in the frame-by-frame sheet, and in
    /// the menu bar barely there at all. A mark 12.8pt across has very little
    /// room to say anything, and a tenth of that is under what you notice
    /// without staring. Past about 0.22 the arms come out uneven enough that
    /// the mark reads as drawn wrong rather than as moving, so this is roughly
    /// two thirds of the way to where the brand starts to suffer.
    ///
    /// Not private only so the render harness can lay out one breath as frames.
    static let breathDepth: CGFloat = 0.16

    /// One breath: 2.5s for every arm to go out and come back once. Not much
    /// over the waiting pulse's 1.7s, and deliberately not much under either —
    /// slower than this and the tips travel so little per second that the mark
    /// stops reading as moving and starts reading as being redrawn wrong.
    private static let period: TimeInterval = 2.5

    /// How long the breath takes to swell in at the start of a turn, and to die
    /// away at the end of one. Short enough to be over before you have finished
    /// reading the row, long enough that neither end is a twitch.
    private static let settle: TimeInterval = 0.45

    /// The breath is read off the clock rather than animated.
    ///
    /// It has two jobs at once — loop forever, and swell in or die away at the
    /// ends — and a `Shape` has exactly one `animatableData`, so a looping
    /// phase and a fading depth cannot both be in flight: whichever was set
    /// last takes the other over. It also has to stop *well*. A repeating
    /// animation cancelled mid-cycle leaves the arms wherever the frame
    /// happened to fall, which on a finished turn is a visible flinch in the
    /// one column that is supposed to be holding still. Three dates and a
    /// number have neither problem, and they make every frame a pure function
    /// of the time it is drawn at.
    ///
    /// When this breath began, which is what fixes the cycle:
    @State private var started: Date?
    /// when the depth last began rising, which is a different instant if the
    /// breath was stopped and started again before it had settled;
    @State private var rising: Date?
    /// and when it was told to stop, with the depth it had reached by then, so
    /// the fade starts from what is actually on screen.
    @State private var stopping: Date?
    @State private var stoppingFrom: CGFloat = 0

    /// An SF Symbol cannot be deformed the way a path can, so a client with no
    /// vector of its own simply does not breathe. Nothing is lost: what the
    /// breath says is already said, in words, by the clock beside it.
    private var wants: Bool { breathing && !reduceMotion && style.vector != nil }

    var body: some View {
        let tint = style.accent ?? Palette.ink(ink.secondary)
        Group {
            if let vector = style.vector {
                // Paused once it is at rest, which is most of the time: a mark
                // that is not breathing costs exactly what it did before any of
                // this, which is nothing.
                TimelineView(.animation(paused: started == nil)) { frame in
                    VectorIconShape(icon: vector,
                                    phase: phase(at: frame.date),
                                    amplitude: depth(at: frame.date))
                        .fill(tint)
                }
                // An arm at full stretch reaches a point or so past the frame
                // the mark was given — the mark is drawn to fill that frame, and
                // the breath is on top of it. Overflowing is ordinary in SwiftUI
                // and was harmless while the only breathing mark sat inside a
                // roomier glyph, but in a panel row the frame is the tight one,
                // and there the overflowing half of every cycle was dropped on
                // the floor: the second row's mark vanished for half of each
                // breath and came back for the other half, which is a mark
                // blinking about once a second. Drawing into a group of its own
                // first means what leaves the frame is still part of one
                // finished image, and it is composited or not as a whole.
                //
                // Measured off the screen rather than off the view: 24 window
                // captures during a breath, second mark missing in 12 of them
                // without this and none with it.
                .compositingGroup()
            } else {
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.82, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .onAppear { if wants { begin() } }
        .onChange(of: wants) { _, now in now ? begin() : end() }
    }

    /// Where in the cycle this frame falls. Counted from `started` rather than
    /// accumulated frame by frame, so it cannot drift and a dropped frame costs
    /// nothing.
    private func phase(at now: Date) -> CGFloat {
        guard let started else { return 0 }
        let turns = now.timeIntervalSince(started) / Self.period
        return CGFloat(turns - turns.rounded(.down))
    }

    private func depth(at now: Date) -> CGFloat {
        if let stopping {
            let left = 1 - now.timeIntervalSince(stopping) / Self.settle
            return stoppingFrom * CGFloat(min(1, max(0, left)))
        }
        guard let rising else { return 0 }
        let up = now.timeIntervalSince(rising) / Self.settle
        return Self.breathDepth * CGFloat(min(1, max(0, up)))
    }

    private func begin() {
        let now = Date()
        // Starting again mid-fade picks the depth up where the fade left it,
        // and keeps the cycle it already had. Only a breath that had fully
        // settled starts over from nothing.
        let resume = Double(depth(at: now) / Self.breathDepth)
        if started == nil { started = now }
        rising = now.addingTimeInterval(-Self.settle * resume)
        stopping = nil
    }

    private func end() {
        guard started != nil, stopping == nil else { return }
        stoppingFrom = depth(at: Date())
        stopping = Date()
        // Cleared once the fade is over, which is what lets the timeline pause.
        // If the turn started again in the meantime, `stopping` is nil by now
        // and this has nothing to do.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.settle))
            guard stopping != nil else { return }
            started = nil
            rising = nil
            stopping = nil
            stoppingFrom = 0
        }
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
        // share a baseline. The highlights sit in the gutter rather than being
        // pulled out of it to line the labels up with the rows above: the
        // gutter is only nine points of black wide once the shoulders are
        // taken off it, so cancelling the style's padding left the highlight
        // two points from the panel's edge, overshooting the hairline it sits
        // under and running into the corner. Aligned to the hairline instead,
        // the labels give up seven points of agreement with the marks above
        // and the footer gains an edge the eye can find.
        .font(.system(size: 12))
        .buttonStyle(MenuItemStyle())
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
