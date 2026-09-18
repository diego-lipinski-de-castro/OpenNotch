import AppKit
import Combine
import SwiftUI

/// Owns the panel that sits over the notch: geometry, hover, and visibility.
@MainActor
final class NotchController {
    private let store: SessionStore
    private let registry: SourceRegistry
    private let ui = NotchUIModel()

    private var panel: NSPanel!
    private var cancellables = Set<AnyCancellable>()
    private var shrinkWork: DispatchWorkItem?
    private var hoverTimer: Timer?
    /// Horizontal centre of the physical cutout, which is not always the
    /// centre of the screen. Everything is anchored to this.
    private var anchorX: CGFloat = 0

    init(store: SessionStore, registry: SourceRegistry) {
        self.store = store
        self.registry = registry
        buildPanel()
        observe()
        updateLayout()
    }

    // MARK: - Panel

    private func buildPanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        // Above the menu bar and its status items, below alerts.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let host = NSHostingView(rootView: NotchRootView(store: store, registry: registry, ui: ui))
        host.autoresizingMask = [.width, .height]
        // The controller owns the window's geometry; without this the hosting
        // view resizes the panel to its fitting size behind our back.
        host.sizingOptions = []
        panel.contentView = host

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func observe() {
        store.onChange = { [weak self] in
            guard let self else { return }
            // Cheap, and it means registering a new client's branding shows up
            // without restarting the app.
            self.registry.reload()
            self.updateLayout()
        }

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.updateLayout() }
            .store(in: &cancellables)

        // Hover is polled rather than tracked: a non-activating panel that
        // resizes under the cursor drops tracking-area crossings too easily.
        // The interval is the worst-case delay before the panel reacts, so it
        // is the floor on how responsive hovering can feel. A mouse-location
        // read costs microseconds; 200ms of nothing followed by everything
        // moving at once does not read as an animation at all.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollHover() }
        }
    }

    // MARK: - Hover

    /// `NSEvent.mouseLocation` goes stale in an accessory app that never
    /// receives mouse events, so ask the window server directly and convert
    /// from its flipped, primary-screen-anchored space into Cocoa coordinates.
    private func currentMouseLocation() -> CGPoint {
        guard let flipped = CGEvent(source: nil)?.location,
              let primary = NSScreen.screens.first else {
            return NSEvent.mouseLocation
        }
        return CGPoint(x: flipped.x, y: primary.frame.maxY - flipped.y)
    }

    private func pollHover() {
        guard panel.isVisible else { return }
        let mouse = currentMouseLocation()
        // Once expanded, allow a small margin so the panel does not flicker
        // when the cursor grazes its edge.
        let hot = ui.hovered ? panel.frame.insetBy(dx: -6, dy: -6) : panel.frame
        let inside = hot.contains(mouse)
        guard inside != ui.hovered else { return }
        // Logged on change only: at 20Hz, every poll is unreadable.
        if Debug.enabled {
            NSLog("hover \(inside) mouse=\(mouse) frame=\(panel.frame) hot=\(hot)")
        }
        ui.hovered = inside
        updateLayout()
    }

    // MARK: - Layout

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
            ?? NSScreen.main
    }

    private func updateLayout() {
        guard let screen = notchScreen() else { return }

        var m = NotchMetrics()
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            m.notchWidth = screen.frame.width - left.width - right.width
            m.notchHeight = screen.safeAreaInsets.top
            m.hasNotch = true
            anchorX = (left.maxX + right.minX) / 2
        } else {
            // No cutout: idle is an invisible hover strip, active is a floating pill.
            m.notchWidth = 150
            m.notchHeight = 10
            m.hasNotch = false
            anchorX = screen.frame.midX
        }
        if ui.metrics != m { ui.metrics = m }

        let rows = max(store.activeSessions.count, 1)
        let size = m.windowSize(expanded: ui.hovered,
                                active: store.overall.isVisible,
                                rows: rows)
        setWindowSize(size, on: screen)
    }

    /// Grow the window immediately so the content has room to animate into;
    /// shrink only once the animation has finished.
    private func setWindowSize(_ size: CGSize, on screen: NSScreen) {
        shrinkWork?.cancel()
        let current = panel.frame.size
        let union = CGSize(width: max(current.width, size.width),
                           height: max(current.height, size.height))

        // Always re-place: the size may already match while the origin is stale.
        place(union, on: screen)

        if union != size {
            let work = DispatchWorkItem { [weak self] in
                self?.place(size, on: screen)
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    private func place(_ size: CGSize, on screen: NSScreen) {
        let f = screen.frame
        let origin = CGPoint(x: (anchorX - size.width / 2).rounded(),
                             y: f.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        if Debug.enabled {
            NSLog("place screen=\(f) want=\(CGRect(origin: origin, size: size)) got=\(panel.frame)")
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
