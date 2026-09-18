import AppKit
import SwiftUI

// MARK: - Status glyph

/// Small state indicator: a spinner while running, a pulse while waiting,
/// a check when finished, a bang when it failed.
///
/// Every state has a distinct silhouette, so the glyph stays readable when the
/// colour does not (PRODUCT.md: never color-only).
struct StatusGlyph: View {
    let state: SessionState
    var size: CGFloat = 12
    /// When set and the client has a mark of its own, that mark turns instead
    /// of the generic spinner.
    var style: SourceStyle?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false

    /// Generic indicators always speak state. Only a client's own mark gets
    /// to be its own colour, so the arc and the elapsed time never disagree.
    private var color: Color { Palette.color(for: state) }
    private var markColor: Color { style?.accent ?? color }

    var body: some View {
        Group {
            switch state {
            case .running: runningMark
            case .waiting: waitingMark
            case .done:    symbol("checkmark", scale: 0.82)
            case .error:   symbol("exclamationmark", scale: 0.88)
            case .idle:    Circle().fill(Palette.idle.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .id("\(state.rawValue)-\(style?.id ?? "")-\(reduceMotion)")
    }

    @ViewBuilder
    private var runningMark: some View {
        Group {
            if let vector = style?.vector {
                VectorIconShape(icon: vector).fill(markColor)
            } else {
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(color, style: StrokeStyle(lineWidth: max(1.6, size * 0.15),
                                                      lineCap: .round))
            }
        }
        .rotationEffect(.degrees(spin ? 360 : 0))
        .onAppear {
            guard !reduceMotion else { return }
            let turn = style?.vector != nil ? 2.6 : 0.85
            withAnimation(.linear(duration: turn).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }

    /// Reduce Motion drops the pulse but keeps the dot, which is already the
    /// one silhouette no other state uses.
    private var waitingMark: some View {
        Circle()
            .fill(color)
            .scaleEffect(pulse ? 1.0 : 0.62)
            .opacity(pulse ? 1.0 : 0.45)
            .onAppear {
                guard !reduceMotion else { pulse = true; return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }

    private func symbol(_ name: String, scale: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * scale, weight: .bold))
            .foregroundStyle(color)
    }
}

/// A client's identifying mark: its own vector if it has one, else its
/// SF Symbol, else the generic fallback.
struct SourceMark: View {
    let style: SourceStyle

    @Environment(\.ink) private var ink

    var body: some View {
        let tint = style.accent ?? Palette.ink(ink.tertiary)
        if let vector = style.vector {
            VectorIconShape(icon: vector).fill(tint)
        } else {
            Image(systemName: style.symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Panel furniture

struct Hairline: View {
    @Environment(\.ink) private var ink

    var body: some View {
        Rectangle().fill(Palette.ink(ink.rule)).frame(height: 1)
    }
}

struct PanelFooter: View {
    @ObservedObject var ui: NotchUIModel

    @Environment(\.ink) private var ink

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { ui.launchAtLogin },
                set: { ui.launchAtLogin = LoginItem.set($0) }
            )) {
                Text("Open at login").font(.system(size: 10))
            }
            .toggleStyle(.checkbox)
            .foregroundStyle(Palette.ink(ink.tertiary))

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.ink(ink.tertiary))
        }
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: - Shared formatting

enum Label {
    /// Elapsed for live states, duration for finished ones; nil when neither
    /// applies, so callers can drop the column entirely.
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

    /// What a session is doing, in the system's voice: plain and short.
    static func detail(_ session: Session, _ state: SessionState, _ now: Date) -> String {
        switch state {
        case .running:
            guard let started = session.started else { return "running" }
            return Format.elapsed(now.timeIntervalSince(started))
        case .waiting:
            return "waiting for you"
        case .done:
            if let d = session.lastDuration { return "done in \(Format.elapsed(d))" }
            return "done"
        case .error:
            if let d = session.lastDuration { return "failed after \(Format.elapsed(d))" }
            return "failed"
        case .idle:
            return "idle"
        }
    }
}
