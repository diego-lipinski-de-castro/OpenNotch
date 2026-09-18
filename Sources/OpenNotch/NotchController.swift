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
    private var hoverIntent: DispatchWorkItem?
    private var intendedHover: Bool?
    /// The drawn shape inside the window. The window is wider and deeper than
    /// this so the expanded panel has room for a shadow, and that margin must
    /// not behave like part of the notch.
    private var contentSize: CGSize = .zero
    /// Last frame asked for, so the once-a-second check can do nothing cheaply.
    private var placed: CGRect?
    /// Horizontal centre of the physical cutout, which is not always the
    /// centre of the screen. Everything is anchored to this.
    private var anchorX: CGFloat = 0
    /// How far the drawn shape sits from the middle of the window.
    private var shapeOffset: CGFloat = 0

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
        // Nothing is clickable until the panel is open, and hover is polled
        // from the window server rather than delivered, so while collapsed the
        // panel wants no mouse events at all. Without this the transparent
        // margin it carries for its shadow would sit over live menu bar items
        // and quietly eat clicks on them.
        panel.ignoresMouseEvents = true
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

        // The badge is a clock, so the shape can need to change width without
        // anything having happened: `42s` becomes `1:00` on a tick and nothing
        // else about the session moves. `updateLayout` does nothing at all when
        // the geometry works out the same, which is almost every second.
        store.onTick = { [weak self] in self?.updateLayout() }

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
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
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

    /// The shape's own rectangle: centred in the window, flush with its top.
    private func hotRect() -> CGRect {
        let f = panel.frame
        return CGRect(x: f.midX + shapeOffset - contentSize.width / 2,
                      y: f.maxY - contentSize.height,
                      width: contentSize.width,
                      height: contentSize.height)
    }

    private func pollHover() {
        guard panel.isVisible else { return }
        let mouse = currentMouseLocation()
        // Once open, allow a margin so the panel does not flicker when the
        // cursor grazes its edge.
        let hot = ui.hovered ? hotRect().insetBy(dx: -8, dy: -8) : hotRect()
        let inside = hot.contains(mouse)

        // Crossing the edge is not the same as meaning to.
        //
        // The panel used to open the instant the cursor touched the notch,
        // which meant that reaching for a menu on the far side of the screen
        // threw a 436pt panel open on the way past. Every menu on the system
        // waits to be sure first. Opening waits longer than closing, because a
        // panel that opens by accident is in the way and a panel that closes a
        // beat late is not.
        guard inside != ui.hovered else {
            if intendedHover != nil {
                hoverIntent?.cancel()
                hoverIntent = nil
                intendedHover = nil
            }
            return
        }
        guard intendedHover != inside else { return }

        hoverIntent?.cancel()
        intendedHover = inside
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.intendedHover = nil
            self.hoverIntent = nil
            if Debug.enabled {
                NSLog("hover \(inside) mouse=\(self.currentMouseLocation()) hot=\(self.hotRect())")
            }
            // Resize first, then flip the flag.
            //
            // These used to run the other way round, and `setFrame(display:)`
            // forces a synchronous layout and draw. Doing that in the same turn
            // that `hovered` changed made SwiftUI render the new value outside
            // its animation transaction, so the panel snapped to full size and
            // the spring never visibly ran. Growing the window first leaves the
            // content untouched, and the flag then changes cleanly.
            self.updateLayout(hovered: inside)
            self.ui.hovered = inside
            self.panel.ignoresMouseEvents = !inside
        }
        hoverIntent = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.1 : 0.16), execute: work)
    }

    // MARK: - Layout

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
            ?? NSScreen.main
    }

    /// `hovered` overrides the model's current value, for the one case where the
    /// window has to be resized before the model catches up.
    private func updateLayout(hovered: Bool? = nil) {
        guard let screen = notchScreen() else { return }
        let hovered = hovered ?? ui.hovered

        var m = NotchMetrics()
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            m.notchWidth = screen.frame.width - left.width - right.width
            m.notchHeight = screen.safeAreaInsets.top
            m.hasNotch = true
            anchorX = (left.maxX + right.minX) / 2
        } else {
            // No cutout: idle is an invisible hover strip at the top centre.
            // Nothing is being blended into here, so the active shape has to
            // stand on its own — it gets its height from the lip rather than
            // from a cutout that is not there.
            m.notchWidth = 150
            m.notchHeight = 10
            m.depth = 18
            m.wing = 24
            m.hasNotch = false
            anchorX = screen.frame.midX
        }
        if ui.metrics != m { ui.metrics = m }

        let rows = max(store.activeSessions.count, 1)
        let active = store.overall.isVisible
        let trailing = m.trailingWing(for: store.badge)
        contentSize = m.contentSize(expanded: hovered, active: active,
                                    rows: rows, trailing: trailing)
        shapeOffset = m.cutoutOffset(expanded: hovered, active: active, trailing: trailing)
        setWindowSize(m.windowSize(expanded: hovered, active: active,
                                   rows: rows, trailing: trailing), on: screen)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.settle, execute: work)
        }
    }

    private func place(_ size: CGSize, on screen: NSScreen) {
        let f = screen.frame
        let rect = CGRect(origin: CGPoint(x: (anchorX - size.width / 2).rounded(),
                                          y: f.maxY - size.height),
                          size: size)
        guard rect != placed || panel.frame != rect else { return }
        placed = rect
        panel.setFrame(rect, display: true)
        if Debug.enabled {
            NSLog("place screen=\(f) want=\(rect) got=\(panel.frame)")
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
