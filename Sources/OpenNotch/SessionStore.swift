import Foundation
import Combine

enum SessionState: String, Codable {
    case idle, running, waiting, done, error
}

/// One agent session, as reported by any client through `opennotch report`.
struct Session: Identifiable, Equatable {
    /// Namespaced by client, so two clients can use the same session id.
    let id: String
    let source: String
    let sessionID: String
    var label: String
    var cwd: String
    var state: SessionState
    var updated: Date
    var started: Date?
    var lastDuration: TimeInterval?
    var pid: pid_t?
    var activity: String?

    var title: String {
        if !label.isEmpty { return label }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? sessionID : name
    }
}

/// Aggregate of every live session, in priority order.
enum OverallState {
    case idle, running, waiting, done, error

    var isVisible: Bool { self != .idle }

    var asSessionState: SessionState {
        switch self {
        case .idle: return .idle
        case .running: return .running
        case .waiting: return .waiting
        case .done: return .done
        case .error: return .error
        }
    }
}

private struct SessionFile: Decodable {
    var v: Int?
    var source: String?
    var session_id: String
    var label: String?
    var cwd: String?
    var activity: String?
    var state: String?
    var ts: Double?
    var started: Double?
    var duration: Double?
    var pid: Int32?
}

@MainActor
final class SessionStore: ObservableObject {
    /// How long a finished session keeps showing its result.
    static let doneLinger: TimeInterval = 9
    /// An interrupted turn may never report a closing state, so a session that
    /// has neither updated nor touched its activity file for this long stops
    /// being shown.
    static let staleAfter: TimeInterval = 30 * 60
    /// How long a blocked session's transcript has to have outlived the report
    /// that blocked it before we conclude the human already answered.
    /// Deliberately generous: wrongly clearing this state hides the one thing
    /// the product exists to show.
    static let resumedAfter: TimeInterval = 10

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var overall: OverallState = .idle
    /// Ticks every second so elapsed-time labels stay live.
    @Published private(set) var now: Date = Date()

    /// Called after the store has finished mutating. `@Published` emits in
    /// `willSet`, so a Combine subscriber would read the previous state —
    /// anything that needs the committed values hangs off this instead.
    var onChange: (() -> Void)?

    /// Called once a second, after `now` has moved. Separate from `onChange`
    /// because that one reloads the client registry off disk, and a clock
    /// ticking is not a reason to go and read a file.
    var onTick: (() -> Void)?

    private let directory: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var dirFD: CInt = -1
    private var reloadWork: DispatchWorkItem?
    private var ticker: Timer?
    /// Activity-file mtimes, refreshed on the tick rather than on every render.
    private var activity: [String: Date] = [:]

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        startWatching()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit {
        watcher?.cancel()
    }

    // MARK: - Derived state

    /// The state actually worth showing: results decay to idle, and a session
    /// whose process is gone stops counting.
    func displayState(for session: Session) -> SessionState {
        switch session.state {
        case .idle:
            return .idle
        case .done, .error:
            return now.timeIntervalSince(session.updated) > Self.doneLinger ? .idle : session.state
        case .running:
            guard isAlive(session.pid) else { return .idle }
            return isStale(session) ? .idle : .running
        case .waiting:
            guard isAlive(session.pid) else { return .idle }
            // Clients say when they start waiting on a human. None of them say
            // when the human answered: Claude Code has no event for a granted
            // permission, so an approved prompt left the session amber for the
            // rest of the turn, which teaches the user to distrust the one
            // colour that matters. The transcript is the tell. If it has been
            // written well after the session said it was blocked, the turn is
            // moving again and nobody is being waited on.
            if let touched = activity[session.id],
               touched.timeIntervalSince(session.updated) > Self.resumedAfter {
                return .running
            }
            return isStale(session) ? .idle : .waiting
        }
    }

    /// Neither the client nor its transcript has said anything in a long time,
    /// which is what an interrupted turn looks like from out here.
    private func isStale(_ session: Session) -> Bool {
        let last = max(session.updated, activity[session.id] ?? .distantPast)
        return now.timeIntervalSince(last) > Self.staleAfter
    }

    /// Sessions that have something to say, most recently active first.
    var activeSessions: [Session] {
        sessions
            .filter { displayState(for: $0) != .idle }
            .sorted { $0.updated > $1.updated }
    }

    /// Distinct clients currently showing something.
    var activeSources: [String] {
        var seen: [String] = []
        for session in activeSessions where !seen.contains(session.source) {
            seen.append(session.source)
        }
        return seen
    }

    private func isAlive(_ pid: pid_t?) -> Bool {
        guard let pid, pid > 0 else { return true } // unknown pid: don't prune
        return kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Loading

    private func tick() {
        now = Date()
        refreshActivity()
        // A client that reports a final state leaves its file behind. Once the
        // process is gone the file is garbage; reload() deletes it. This fires
        // at most once per dead session, so it does not spin.
        if sessions.contains(where: { isDead($0.pid) }) {
            reload()
            return
        }
        if recomputeOverall() { onChange?() } else { onTick?() }
    }

    private func isDead(_ pid: pid_t?) -> Bool {
        guard let pid, pid > 0 else { return false }
        return kill(pid, 0) != 0 && errno != EPERM
    }

    /// Stat the activity file of anything still claiming to be busy, so a turn
    /// that was interrupted eventually stops spinning.
    private func refreshActivity() {
        for session in sessions where session.state == .running || session.state == .waiting {
            guard let path = session.activity, !path.isEmpty else { continue }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modified = attrs[.modificationDate] as? Date else { continue }
            activity[session.id] = modified
        }
        let live = Set(sessions.map(\.id))
        activity = activity.filter { live.contains($0.key) }
    }

    /// Returns whether the aggregate state actually changed.
    @discardableResult
    private func recomputeOverall() -> Bool {
        let states = sessions.map(displayState(for:))
        let next: OverallState
        // Being blocked on the human outranks everything: it is the only state
        // that needs the human to do something.
        if states.contains(.waiting) { next = .waiting }
        else if states.contains(.error) { next = .error }
        else if states.contains(.running) { next = .running }
        else if states.contains(.done) { next = .done }
        else { next = .idle }
        guard next != overall else { return false }
        overall = next
        return true
    }

    func reload() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory,
                                                includingPropertiesForKeys: nil,
                                                options: [.skipsHiddenFiles])) ?? []
        let decoder = JSONDecoder()
        var loaded: [Session] = []

        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let raw = try? decoder.decode(SessionFile.self, from: data) else { continue }

            let updated = Date(timeIntervalSince1970: raw.ts ?? 0)
            let pid = raw.pid

            // Drop anything whose process is gone or that is simply ancient.
            let ancient = Date().timeIntervalSince(updated) > 60 * 60 * 24
            if ancient || (pid.map { kill($0, 0) != 0 && errno != EPERM } ?? false) {
                try? fm.removeItem(at: url)
                continue
            }

            let source = raw.source ?? "unknown"
            loaded.append(Session(
                id: "\(source)/\(raw.session_id)",
                source: source,
                sessionID: raw.session_id,
                label: raw.label ?? "",
                cwd: raw.cwd ?? "",
                state: SessionState(rawValue: raw.state ?? "idle") ?? .idle,
                updated: updated,
                started: raw.started.map { Date(timeIntervalSince1970: $0) },
                lastDuration: raw.duration,
                pid: pid,
                activity: raw.activity?.isEmpty == false ? raw.activity : nil
            ))
        }

        sessions = loaded
        now = Date()
        refreshActivity()
        recomputeOverall()
        // Fired unconditionally: the session count changes the panel's height
        // even when the aggregate state does not.
        onChange?()
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    // MARK: - Directory watching

    private func startWatching() {
        dirFD = open(directory.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { [dirFD] in close(dirFD) }
        source.resume()
        watcher = source
    }
}
