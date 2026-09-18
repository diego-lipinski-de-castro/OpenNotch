import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SessionStore?
    private var registry: SourceRegistry?
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SessionStore(directory: StatePaths.sessionsDirectory)
        let registry = SourceRegistry(file: StatePaths.sourcesFile)
        self.store = store
        self.registry = registry
        self.controller = NotchController(store: store, registry: registry)
    }
}

enum StatePaths {
    /// Everything OpenNotch owns lives under one directory so a client only
    /// ever needs to know `OPENNOTCH_DIR`.
    static var root: URL {
        if let override = ProcessInfo.processInfo.environment["OPENNOTCH_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opennotch", isDirectory: true)
    }

    static var sessionsDirectory: URL {
        root.appendingPathComponent("sessions", isDirectory: true)
    }

    static var sourcesFile: URL {
        root.appendingPathComponent("sources.json")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
