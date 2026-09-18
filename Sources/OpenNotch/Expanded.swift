import SwiftUI

/// The hover panel: every live session, whatever needs a human first.
struct ExpandedPanel: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var registry: SourceRegistry
    @ObservedObject var ui: NotchUIModel
    let m: NotchMetrics
    let flare: CGFloat

    @Environment(\.ink) private var ink

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            Spacer(minLength: 0)
            PanelFooter(ui: ui)
                .frame(height: m.footerHeight)
        }
        .padding(.horizontal, m.expandedPadding + 4)
        .padding(.bottom, m.expandedPadding)
        .frame(width: m.expandedWidth + flare * 2)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                StatusGlyph(state: store.overall.asSessionState, size: 12, style: nil)
                Text(headline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.ink(ink.secondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: m.notchWidth - 8)   // the physical cutout

            Text(clientLabel)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink(ink.tertiary))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: m.notchHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("OpenNotch. \(headline). \(clientLabel).")
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
                .font(.system(size: 12))
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
                        .overlay(alignment: .top) { if index > 0 { Hairline() } }
                }
            }
        }
    }
}

// MARK: - Row

/// Two lines: what it is, and where it is. Two sessions in folders called
/// `api` are indistinguishable without the second line.
private struct SessionRow: View {
    let session: Session
    let style: SourceStyle
    let state: SessionState
    let now: Date
    let showsClient: Bool

    @Environment(\.ink) private var ink

    private var detail: String { Label.detail(session, state, now) }
    private var location: String { Label.home(session.cwd) }

    var body: some View {
        HStack(spacing: 9) {
            StatusGlyph(state: state, size: 11, style: style)
                .frame(width: 13)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink(ink.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(location)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.ink(ink.tertiary))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 1) {
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.color(for: state))
                    .lineLimit(1)

                if showsClient {
                    Text(style.name)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.ink(ink.tertiary))
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.name). \(session.title) in \(location). \(detail).")
    }
}
