import AppKit
import SwiftUI

/// How a client presents itself in the panel. Clients are not compiled in:
/// anything unknown still works, it just falls back to a generic look.
struct SourceStyle: Equatable {
    var id: String
    var name: String
    /// SF Symbol, used when there is no vector mark.
    var symbol: String
    /// The client's own mark. Preferred over `symbol` wherever it is set, and
    /// the only thing that replaces the spinner while a turn is running.
    var vector: VectorIcon?
    var accent: Color?
}

@MainActor
final class SourceRegistry: ObservableObject {
    /// Shipped defaults for the clients that have an adapter in the repo.
    /// These are only conveniences — `sources.json` can override any of them,
    /// and an unlisted client gets a name derived from its id.
    private static let builtIn: [String: SourceStyle] = [
        "claude-code": SourceStyle(id: "claude-code", name: "Claude Code",
                                   symbol: "sparkle",
                                   vector: BuiltInIcons.claude,
                                   accent: Color(hex: "#D97757")),
        "codex": SourceStyle(id: "codex", name: "Codex",
                             symbol: "chevron.left.forwardslash.chevron.right",
                             vector: BuiltInIcons.openAI,
                             accent: Color(hex: "#10A37F")),
        "cursor": SourceStyle(id: "cursor", name: "Cursor",
                              symbol: "cube",
                              vector: BuiltInIcons.cursor,
                              accent: Color(hex: "#E4E4E4")),
        "gemini": SourceStyle(id: "gemini", name: "Gemini",
                              symbol: "sparkles",
                              vector: BuiltInIcons.gemini,
                              // The middle of the mark's own blue-to-violet
                              // gradient. The panel fills a mark with one
                              // colour, and the end stops are either too dim
                              // or too pale against pure black.
                              accent: Color(hex: "#8E9BFF")),
        "shell": SourceStyle(id: "shell", name: "Shell",
                             symbol: "terminal", vector: nil, accent: nil)
    ]

    @Published private(set) var overrides: [String: SourceStyle] = [:]

    private let file: URL

    init(file: URL) {
        self.file = file
        reload()
    }

    func style(for id: String) -> SourceStyle {
        if let override = overrides[id] { return override }
        if let known = Self.builtIn[id] { return known }
        return SourceStyle(id: id, name: Self.prettify(id),
                           symbol: "circle.dashed", vector: nil, accent: nil)
    }

    /// "my-tool" -> "My Tool", so a brand-new client reads sensibly with no
    /// registration at all.
    private static func prettify(_ id: String) -> String {
        id.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// A bad symbol name in sources.json would silently render nothing.
    private static func validSymbol(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "circle.dashed"
    }

    func reload() {
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sources = root["sources"] as? [String: Any] else {
            if !overrides.isEmpty { overrides = [:] }
            return
        }

        var loaded: [String: SourceStyle] = [:]
        for (id, value) in sources {
            guard let entry = value as? [String: Any] else { continue }
            let fallback = Self.builtIn[id]
            let vector: VectorIcon?
            if let data = entry["path"] as? String, !data.isEmpty {
                let box = entry["viewBox"] as? String ?? "0 0 100 100"
                vector = VectorIcon(data: data, viewBoxAttribute: box) ?? VectorIcon(data: data)
            } else {
                vector = fallback?.vector
            }

            loaded[id] = SourceStyle(
                id: id,
                name: entry["name"] as? String ?? fallback?.name ?? Self.prettify(id),
                symbol: Self.validSymbol(entry["symbol"] as? String
                                          ?? fallback?.symbol ?? "circle.dashed"),
                vector: vector,
                accent: (entry["accent"] as? String).flatMap { Color(hex: $0) } ?? fallback?.accent
            )
        }
        if loaded != overrides { overrides = loaded }
    }
}

extension Color {
    /// Accepts "#RGB", "#RRGGBB" and "#RRGGBBAA"; returns nil for anything else
    /// so a typo in sources.json degrades to the default rather than crashing.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }

        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
