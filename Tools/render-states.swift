import AppKit
import SwiftUI

/// Renders the notch into PNGs without putting it on screen, so a change to the
/// silhouette or the panel can be looked at frame by frame — including on a
/// machine whose display is asleep, and including states that are a nuisance to
/// provoke for real. Compiled by Tools/render-states.sh against the app's own
/// sources, so it is the real views, not a copy of them.
@MainActor
enum Harness {
    static let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
                         ? CommandLine.arguments[1] : "./render")

    /// A slice of desktop behind the panel, so the seam at the top of the
    /// screen and the panel's own edge can both be judged. Flat colour would
    /// flatter both.
    static func backdrop(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.31, blue: 0.42),
                                    Color(red: 0.15, green: 0.17, blue: 0.24),
                                    Color(red: 0.42, green: 0.29, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Menu-bar furniture either side of the cutout, which is what the
            // collapsed glyph has to line up with.
            HStack {
                Text("Finder   File   Edit   View   Window   Help")
                Spacer()
                Text("􀙇  􀊫  􀆨")
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
    }

    static func write(_ name: String, _ view: some View, size: CGSize) {
        let renderer = ImageRenderer(content:
            ZStack(alignment: .top) { backdrop(size); view }
                .frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render \(name) failed\n".utf8))
            return
        }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? png.write(to: out.appendingPathComponent("\(name).png"))
        print("  \(name).png")
    }

    /// Writes session files the way the CLI does, then lets the real store read
    /// them back, so the render exercises the same decoding path the app does.
    static func store(_ specs: [(String, String, String, SessionState, TimeInterval)]) -> SessionStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opennotch-render-\(UUID().uuidString)/sessions")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970
        for (i, s) in specs.enumerated() {
            let json: [String: Any] = [
                "v": 1, "source": s.0, "session_id": "render-\(i)", "label": s.1,
                "cwd": s.2, "state": s.3.rawValue, "ts": now,
                "started": now - s.4, "duration": s.4
            ]
            let data = try! JSONSerialization.data(withJSONObject: json)
            try? data.write(to: dir.appendingPathComponent("\(s.0).render-\(i).json"))
        }
        return SessionStore(directory: dir)
    }

    /// Glyphs at four times their real size, on the surface they actually sit
    /// on. Small marks hide their mistakes at small sizes.
    static func glyphSheet(_ registry: SourceRegistry) -> some View {
        let claude = registry.style(for: "claude-code")
        return VStack(alignment: .leading, spacing: 22) {
            ForEach([("collapsed, 16pt", CGFloat(16), true),
                     ("panel header, 13pt", 13, false),
                     ("row, 10pt", 10, false)], id: \.0) { label, size, identity in
                HStack(spacing: 26) {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 130, alignment: .leading)
                    ForEach([SessionState.running, .waiting, .done, .error, .idle],
                            id: \.rawValue) { state in
                        StatusGlyph(state: state, size: size,
                                    style: claude, showsIdentity: identity)
                            .scaleEffect(4, anchor: .center)
                            .frame(width: 74, height: 74)
                    }
                }
            }
        }
        .padding(28)
        .background(Color.black)
    }

    /// One breath, laid out as frames, because the thing it has to be judged
    /// against is itself a moment earlier. Each client's mark twice: once at
    /// four times size, where the deformation is easy to read, and once at the
    /// 12.8pt it is actually drawn at, where the only question is whether the
    /// change between neighbouring frames is too much or too little.
    static func breathSheet(_ registry: SourceRegistry) -> some View {
        let phases: [CGFloat] = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]
        return VStack(alignment: .leading, spacing: 18) {
            ForEach(["claude-code", "codex", "cursor", "gemini"], id: \.self) { id in
                let style = registry.style(for: id)
                if let vector = style.vector {
                    HStack(spacing: 20) {
                        ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
                            VStack(spacing: 9) {
                                VectorIconShape(icon: vector, phase: phase,
                                                amplitude: SourceMark.breathDepth)
                                    .fill(style.accent ?? .white)
                                    .frame(width: 51.2, height: 51.2)
                                VectorIconShape(icon: vector, phase: phase,
                                                amplitude: SourceMark.breathDepth)
                                    .fill(style.accent ?? .white)
                                    .frame(width: 12.8, height: 12.8)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(Color.black)
    }

    static func run() {
        let registry = SourceRegistry(file: URL(fileURLWithPath: "/nonexistent"))
        var metrics = NotchMetrics()
        metrics.notchWidth = 185
        metrics.notchHeight = 32

        let one: [(String, String, String, SessionState, TimeInterval)] = [
            ("claude-code", "opennotch", NSHomeDirectory() + "/Development/OpenNotch", .running, 98)
        ]
        let many: [(String, String, String, SessionState, TimeInterval)] = [
            ("claude-code", "opennotch", NSHomeDirectory() + "/Development/OpenNotch", .running, 98),
            ("cursor", "api", NSHomeDirectory() + "/Development/acme/services/api", .waiting, 1233),
            ("codex", "web", NSHomeDirectory() + "/Development/acme/apps/web", .done, 41),
            ("gemini", "docs", NSHomeDirectory() + "/Development/acme/docs", .running, 12)
        ]

        print("rendering into \(out.path)")

        write("glyphs", glyphSheet(registry).frame(maxHeight: .infinity, alignment: .top),
              size: CGSize(width: 620, height: 330))

        write("breath", breathSheet(registry).frame(maxHeight: .infinity, alignment: .top),
              size: CGSize(width: 620, height: 380))

        // Every client mark at the size it appears in a row, and much larger,
        // because a path that parsed wrong is obvious at 96pt and invisible
        // at 16.
        write("marks",
              HStack(spacing: 22) {
                  ForEach(["claude-code", "codex", "cursor", "gemini", "unknown-tool"], id: \.self) { id in
                      VStack(spacing: 14) {
                          SourceMark(style: registry.style(for: id), size: 96)
                          SourceMark(style: registry.style(for: id), size: 16)
                          Text(registry.style(for: id).name)
                              .font(.system(size: 10))
                              .foregroundStyle(.white.opacity(0.55))
                      }
                  }
              }
              .padding(22)
              .background(Color.black)
              .frame(maxHeight: .infinity, alignment: .top),
              size: CGSize(width: 620, height: 210))


        // Collapsed, one state per file.
        for (name, state) in [("idle", SessionState.idle), ("running", .running),
                              ("waiting", .waiting), ("done", .done), ("error", .error)] {
            let s = store([("claude-code", "opennotch",
                            NSHomeDirectory() + "/Development/OpenNotch", state, 98)])
            let ui = NotchUIModel()
            ui.metrics = metrics
            write("collapsed-\(name)",
                  NotchRootView(store: s, registry: registry, ui: ui),
                  size: CGSize(width: 620, height: 96))
        }

        // Collapsed with several sessions: the count replaces the clock.
        do {
            let s = store(many)
            let ui = NotchUIModel()
            ui.metrics = metrics
            write("collapsed-many",
                  NotchRootView(store: s, registry: registry, ui: ui),
                  size: CGSize(width: 620, height: 96))
        }

        // Expanded.
        for (name, specs) in [("one", one), ("many", many)] {
            let s = store(specs)
            let ui = NotchUIModel()
            ui.metrics = metrics
            ui.hovered = true
            write("expanded-\(name)",
                  NotchRootView(store: s, registry: registry, ui: ui),
                  size: CGSize(width: 620, height: 340))
        }

        // Expanded with nothing running, and with the raised ink scale
        // Increase Contrast switches the panel to.
        do {
            let s = store([])
            let ui = NotchUIModel()
            ui.metrics = metrics
            ui.hovered = true
            write("expanded-empty",
                  NotchRootView(store: s, registry: registry, ui: ui),
                  size: CGSize(width: 620, height: 260))
        }
        // Increase Contrast. NotchRootView resolves the ink scale from the
        // environment itself, so the panel is rendered directly to force it.
        do {
            let s = store(many)
            let ui = NotchUIModel()
            ui.metrics = metrics
            ui.hovered = true
            let shape = NotchShape(shoulder: metrics.shoulder(expanded: true, active: true),
                                   corner: metrics.corner(expanded: true, active: true))
            let size = metrics.contentSize(expanded: true, active: true, rows: 3,
                                           trailing: metrics.minTrailingWing)
            write("expanded-contrast",
                  ZStack(alignment: .top) {
                      shape.fill(Palette.body)
                      ExpandedPanel(store: s, registry: registry, ui: ui, m: metrics)
                  }
                  .frame(width: size.width, height: size.height)
                  .environment(\.ink, .increased)
                  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top),
                  size: CGSize(width: 620, height: 340))
        }

        // A display with no cutout at all.
        do {
            var ext = NotchMetrics()
            ext.notchWidth = 150
            ext.notchHeight = 10
            ext.depth = 18
            ext.wing = 24
            ext.hasNotch = false
            for (name, hovered) in [("collapsed", false), ("expanded", true)] {
                let s = store(many)
                let ui = NotchUIModel()
                ui.metrics = ext
                ui.hovered = hovered
                write("nonotch-\(name)",
                      NotchRootView(store: s, registry: registry, ui: ui),
                      size: CGSize(width: 620, height: hovered ? 340 : 96))
            }
        }
    }
}

@main
struct RenderMain {
    static func main() { MainActor.assumeIsolated { Harness.run() } }
}
