import SwiftUI

/// The hover panel: every live session, whatever needs a human first.
struct ExpandedPanel: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var registry: SourceRegistry
    @ObservedObject var ui: NotchUIModel
    let m: NotchMetrics

    @Environment(\.ink) private var ink

    var body: some View {
        VStack(spacing: 0) {
            header
            list.padding(.horizontal, m.inset)
            Spacer(minLength: 0)
            PanelFooter(ui: ui)
                .frame(height: m.footerHeight)
                .padding(.horizontal, m.inset)
                .overlay(alignment: .top) { Hairline().padding(.horizontal, m.inset) }
        }
        .padding(.bottom, m.expandedPadding)
    }

    // MARK: - Header

    /// The header is measured from the cutout, not from the panel's edges.
    ///
    /// Pushed out to the corners, the two labels leave 185pt of nothing between
    /// them and the panel reads as a row that failed to load. Pulled in against
    /// the cutout, the same gap stops being a hole in the layout and starts
    /// being the thing the layout is arranged around — and the summary lands
    /// within a few points of where the collapsed glyph already was, so opening
    /// the panel grows the black around the status rather than replacing it.
    private var header: some View {
        HStack(spacing: 0) {
            headlineText
                .frame(maxWidth: .infinity, alignment: m.hasNotch ? .trailing : .leading)
                .padding(.trailing, m.hasNotch ? 13 : 0)

            // The physical cutout. On a display without one there is nothing to
            // arrange around, so the header becomes an ordinary title row.
            if m.hasNotch { Color.clear.frame(width: m.notchWidth) }

            Text(clientLabel)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink(ink.tertiary))
                .lineLimit(1)
                // Hugging the cutout where there is one, out at the corner
                // where there is not.
                .frame(maxWidth: .infinity, alignment: m.hasNotch ? .leading : .trailing)
                .padding(.leading, m.hasNotch ? 13 : 8)
        }
        .padding(.horizontal, m.inset)
        .frame(height: m.headerHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("OpenNotch. \(headline). \(clientLabel).")
    }

    /// No glyph. The headline already names the state in words, every row below
    /// carries its own, and a spinner turning up here was the fourth thing
    /// moving in a panel you opened to read.
    private var headlineText: some View {
        Text(headline)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Palette.ink(ink.secondary))
            .lineLimit(1)
            .fixedSize()
    }

    /// Names the client when there is exactly one, counts them otherwise.
    private var clientLabel: String {
        let sources = store.activeSources
        guard let first = sources.first else { return "OpenNotch" }
        return sources.count == 1 ? registry.style(for: first).name : "\(sources.count) clients"
    }

    private var headline: String {
        func count(_ state: SessionState) -> Int {
            store.activeSessions.filter { store.displayState(for: $0) == state }.count
        }
        let waiting = count(.waiting), running = count(.running), failed = count(.error)
        if waiting > 0 { return waiting == 1 ? "Needs you" : "\(waiting) need you" }
        if failed > 0 { return failed == 1 ? "Failed" : "\(failed) failed" }
        if running > 0 { return running == 1 ? "Running" : "\(running) running" }
        if count(.done) > 0 { return "Finished" }
        return "Idle"
    }

    // MARK: - List

    /// Whatever needs a human goes to the top. In a list this short, sorting by
    /// urgency is the entire information design.
    private var ordered: [Session] {
        store.activeSessions.sorted { a, b in
            let ua = Palette.urgency(for: store.displayState(for: a))
            let ub = Palette.urgency(for: store.displayState(for: b))
            if ua != ub { return ua > ub }
            return a.updated > b.updated
        }
    }

    @ViewBuilder
    private var list: some View {
        let sessions = ordered
        if sessions.isEmpty {
            Text("No active sessions")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink(ink.tertiary))
                .frame(height: m.rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    SessionRow(session: session,
                               style: registry.style(for: session.source),
                               state: store.displayState(for: session),
                               now: store.now,
                               showsClient: store.activeSources.count > 1)
                        .frame(height: m.rowHeight)
                        // Inset to the text column, the way the system insets a
                        // list's separators rather than a menu's: these rows are
                        // records, and the mark column is a gutter.
                        .overlay(alignment: .top) {
                            if index > 0 { Hairline().padding(.leading, SessionRow.gutter) }
                        }
                }
            }
            // Held to exactly the rows it now has, and clipped.
            //
            // A row that leaves is animated out where it stood rather than
            // removed instantly, so for as long as that takes the list is
            // taller than the panel shrinking around it — and the footer, which
            // has already moved up, was drawn straight through it. Clipping
            // means the departing row is swallowed by the list closing over it.
            .frame(height: CGFloat(sessions.count) * m.rowHeight, alignment: .top)
            .clipped()
        }
    }
}

// MARK: - Row

/// Three columns, each answering one question. Whose turn this is, what it is
/// working on, and how it is going.
///
/// The mark column used to carry both identity and state — the client's mark
/// while running, a state glyph otherwise — so the column changed meaning
/// underneath you the moment a session needed something, and the one time you
/// most needed to know *which* client was asking was the one time it stopped
/// saying. Identity leads, state trails, and neither borrows the other's slot.
private struct SessionRow: View {
    let session: Session
    let style: SourceStyle
    let state: SessionState
    let now: Date
    let showsClient: Bool

    @Environment(\.ink) private var ink

    /// Mark column plus its gap: what separators and the second line align to.
    static let gutter: CGFloat = 16 + 11

    private var location: String { Label.home(session.cwd) }

    var body: some View {
        HStack(spacing: 11) {
            SourceMark(style: style, size: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink(ink.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(location)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink(ink.tertiary))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 6) {
                    StatusGlyph(state: state, size: 10, style: style)

                    if let time = Label.timer(for: session, state: state, now: now) {
                        Text(time)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Palette.color(for: state))
                    }
                }

                if showsClient {
                    Text(style.name)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.ink(ink.tertiary))
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.name). \(session.title) in \(location). \(Label.detail(session, state, now)).")
    }
}
