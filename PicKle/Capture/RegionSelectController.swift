import AppKit
import SwiftUI
import CoreGraphics

/// A borderless, transparent **non-activating** panel that can become key (so it
/// receives the mouse drag and Esc) WITHOUT the app having to become active.
/// Accessory (LSUIElement) apps can't reliably activate themselves over another
/// app, so a plain NSWindow never gets the drag; a `.nonactivatingPanel` does.
final class SelectionOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The selection layer: the standard macOS crosshair cursor, drag to draw a
/// rectangle, dim outside the selection. Reports the chosen rect (in this view's
/// coordinates) on mouse-up, or cancels on Esc / a too-small drag.
final class SelectionOverlayView: NSView {
    var onDragBegan: (() -> Void)?
    var onCommit: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var selection: NSRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self))
    }
    // Use the system's standard crosshair (the same one ⇧⌘5 shows), managed via
    // cursor rects + cursorUpdate so macOS shows/hides it for us — no custom
    // push/pop (which got unbalanced when an overlay never appeared on a screen).
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        startPoint = p
        selection = NSRect(origin: p, size: .zero)
        onDragBegan?()
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let s = startPoint else { return }
        var p = convert(event.locationInWindow, from: nil)
        // Clamp to this screen's bounds: AppKit keeps delivering the drag to the
        // window that received mouseDown even after the cursor crosses onto another
        // monitor, which would push the selection off-screen and capture black.
        p.x = min(max(p.x, 0), bounds.width)
        p.y = min(max(p.y, 0), bounds.height)
        selection = NSRect(x: min(s.x, p.x), y: min(s.y, p.y),
                           width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let r = selection
        startPoint = nil
        selection = .zero
        needsDisplay = true
        if r.width >= 5, r.height >= 5 { onCommit?(r) } else { onCancel?() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim this screen.
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()
        guard selection.width > 0, selection.height > 0,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Punch the selection clear (no dim there → see the real screen).
        ctx.setBlendMode(.clear)
        ctx.fill(selection)
        ctx.setBlendMode(.normal)
        // Pickle-green outline.
        let path = NSBezierPath(rect: selection)
        path.lineWidth = 2
        NSColor(srgbRed: 0.43, green: 0.68, blue: 0.31, alpha: 1).setStroke()
        path.stroke()
    }
}

/// Drives the ⇧⌘5-style capture flow. One overlay window **per screen** (a single
/// union-frame window only ever rendered on one monitor, so the main display
/// couldn't be captured at all), plus the compact mode bar floating on top.
/// Switching mode = click the bar; capturing = drag on any screen's overlay (the
/// bar hides the moment the drag starts so it never blocks the capture area).
final class RegionSelectController {
    private var overlays: [SelectionOverlayWindow] = []
    private var toolbar: FocusablePanel?
    private var barModel: CaptureModeBarModel?
    private var keyMonitor: Any?

    private var onComplete: ((CaptureMode, CGRect) -> Void)?
    private var onCancel: (() -> Void)?

    var isActive: Bool { !overlays.isEmpty }

    /// Start a selection with `preselect` highlighted. If one's already running,
    /// just move the highlight (pressing another capture shortcut re-targets).
    func begin(preselect: CaptureMode,
               anchorRect: NSRect?,
               onComplete: @escaping (CaptureMode, CGRect) -> Void,
               onCancel: @escaping () -> Void) {
        if !overlays.isEmpty, let barModel {
            self.onComplete = onComplete
            self.onCancel = onCancel
            barModel.selected = preselect
            return
        }

        let model = CaptureModeBarModel(selected: preselect)
        self.barModel = model
        self.onComplete = onComplete
        self.onCancel = onCancel

        let shield = Int(CGShieldingWindowLevel())
        // One overlay per screen so EVERY monitor (incl. the main display) gets
        // the dim + crosshair + drag.
        for screen in NSScreen.screens {
            let win = SelectionOverlayWindow(contentRect: screen.frame,
                                             styleMask: [.borderless, .nonactivatingPanel],
                                             backing: .buffered, defer: false)
            win.isFloatingPanel = true
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.level = NSWindow.Level(rawValue: shield)
            win.sharingType = .none          // keep the overlay out of the screenshot
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let screenOrigin = screen.frame.origin
            view.onDragBegan = { [weak self] in self?.hideToolbar() }
            view.onCommit = { [weak self] rectInView in
                self?.commit(rectInView: rectInView, screenOrigin: screenOrigin)
            }
            view.onCancel = { [weak self] in self?.cancel() }
            win.contentView = view
            win.orderFrontRegardless()
            overlays.append(win)
        }
        // Activate so keyDown (Esc / ← / →) is routed into our local monitor: an
        // accessory app launched by a global hotkey is otherwise still in the
        // background and never sees key events. The mouse drag works regardless
        // via acceptsFirstMouse. (Matches every other window path in the app.)
        NSApp.activate(ignoringOtherApps: true)
        overlays.first?.makeKeyAndOrderFront(nil)

        showToolbar(anchorRect: anchorRect, shieldLevel: shield, model: model)
        installKeyMonitor()
    }

    // MARK: - Toolbar

    private func showToolbar(anchorRect: NSRect?, shieldLevel: Int, model: CaptureModeBarModel) {
        let bar = CaptureModeBar(model: model, onCancel: { [weak self] in self?.cancel() })
        let hosting = NSHostingView(rootView: bar)
        hosting.layout()
        let size = hosting.fittingSize

        let panel = FocusablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Buttons work without key status; never let the bar take key away from
        // the selection overlays (otherwise the drag never reaches them).
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: shieldLevel + 1)   // above the overlays
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true

        panel.setFrame(toolbarFrame(anchorRect: anchorRect, size: size), display: false)
        panel.orderFront(nil)
        self.toolbar = panel
    }

    private func hideToolbar() {
        toolbar?.orderOut(nil)
        toolbar = nil
    }

    /// Anchor the bar just below the menu-bar icon, clamped to the screen.
    private func toolbarFrame(anchorRect: NSRect?, size: CGSize) -> NSRect {
        let w = size.width, h = size.height
        let fallback = NSScreen.main ?? NSScreen.screens.first
        if let anchor = anchorRect {
            let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) }) ?? fallback
            let visible = screen?.visibleFrame ?? .zero
            var x = anchor.midX - w / 2
            x = min(max(x, visible.minX + 8), visible.maxX - w - 8)
            return NSRect(x: x, y: anchor.minY - h - 6, width: w, height: h)
        }
        let visible = fallback?.visibleFrame ?? .zero
        return NSRect(x: visible.midX - w / 2, y: visible.maxY - h - 12, width: w, height: h)
    }

    // MARK: - Outcomes

    private func commit(rectInView: NSRect, screenOrigin: NSPoint) {
        guard !overlays.isEmpty else { return }
        let mode = barModel?.selected ?? .save
        // View coords (origin = this screen's bottom-left) → global Cocoa coords.
        let global = CGRect(x: rectInView.minX + screenOrigin.x,
                            y: rectInView.minY + screenOrigin.y,
                            width: rectInView.width, height: rectInView.height)
        let cb = onComplete
        teardown()
        // Let the compositor drop the (now-removed) overlay before capturing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { cb?(mode, global) }
    }

    private func cancel() {
        guard !overlays.isEmpty || toolbar != nil else { return }
        let cb = onCancel
        teardown()
        cb?()
    }

    private func teardown() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        toolbar?.orderOut(nil); toolbar = nil
        for win in overlays { win.orderOut(nil) }
        overlays.removeAll()
        barModel = nil
        onComplete = nil
        onCancel = nil
    }

    // MARK: - Keyboard (single source of truth for Esc / arrows)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let model = self.barModel else { return event }
            switch event.keyCode {
            case 53: self.cancel(); return nil          // Esc
            case 123: model.move(-1); return nil         // ←
            case 124: model.move(1); return nil          // →
            default: return event
            }
        }
    }
}
