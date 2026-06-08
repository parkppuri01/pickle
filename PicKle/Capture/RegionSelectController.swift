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

    /// Frozen screenshot of this view's screen, captured the instant the shortcut
    /// fired. When set it's drawn as the backdrop and the crop is taken from it, so
    /// what gets captured is exactly the screen at shortcut-press time (not later).
    var freezeImage: CGImage?
    var freezeScale: CGFloat = 2

    private var startPoint: NSPoint?
    private var selection: NSRect = .zero
    /// Hold Space mid-drag to reposition the whole selection (⇧⌘5 behaviour).
    private var isMoving = false
    private var lastDragPoint: NSPoint?

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
        lastDragPoint = p
        isMoving = false             // each drag starts by resizing; Space re-enables move
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
        needsDisplay = true

        // Space held → slide the whole rectangle by the mouse delta instead of
        // resizing it. The anchor moves too, so releasing Space resumes resizing
        // from the new position. (Matches macOS ⇧⌘5.)
        if isMoving, let last = lastDragPoint {
            var dx = p.x - last.x
            var dy = p.y - last.y
            // Clamp the move so the selection can't be pushed off this screen.
            dx = min(max(dx, -selection.minX), bounds.width - selection.maxX)
            dy = min(max(dy, -selection.minY), bounds.height - selection.maxY)
            selection.origin.x += dx
            selection.origin.y += dy
            startPoint = NSPoint(x: s.x + dx, y: s.y + dy)
            // Advance the anchor by the *applied* (clamped) delta, not the raw
            // cursor, so pushing past a screen edge doesn't desync cursor↔selection.
            lastDragPoint = NSPoint(x: last.x + dx, y: last.y + dy)
            return
        }
        selection = NSRect(x: min(s.x, p.x), y: min(s.y, p.y),
                           width: abs(p.x - s.x), height: abs(p.y - s.y))
        lastDragPoint = p
    }
    override func mouseUp(with event: NSEvent) {
        let r = selection
        startPoint = nil
        lastDragPoint = nil
        selection = .zero
        needsDisplay = true
        if r.width >= 5, r.height >= 5 { onCommit?(r) } else { onCancel?() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    /// Toggle "move the selection" mode. Driven by the controller's Space key
    /// monitor: Space events land on the key overlay, which may differ from the
    /// overlay being dragged, so the controller broadcasts this to all of them.
    func setMoving(_ moving: Bool) { isMoving = moving }

    override func draw(_ dirtyRect: NSRect) {
        // Frozen backdrop: the screen exactly as it was when the shortcut fired, so
        // the user selects on a still image. With no freeze (e.g. macOS 13) the view
        // stays transparent over the live screen, matching the old behaviour.
        if let frozen = freezeImage {
            NSImage(cgImage: frozen, size: bounds.size).draw(in: bounds)
        }
        // Dim everything.
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()
        guard selection.width > 0, selection.height > 0,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Reveal the selection: redraw the frozen image sharp inside it; with no
        // freeze, punch the dim out so the live screen shows through there.
        if let frozen = freezeImage {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).setClip()
            NSImage(cgImage: frozen, size: bounds.size).draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            ctx.setBlendMode(.clear)
            ctx.fill(selection)
            ctx.setBlendMode(.normal)
        }
        // Pickle-green outline.
        let path = NSBezierPath(rect: selection)
        path.lineWidth = 2
        NSColor(srgbRed: 0.43, green: 0.68, blue: 0.31, alpha: 1).setStroke()
        path.stroke()

        // Live pixel dimensions near the cursor, like the macOS screenshot HUD.
        // selection is in points; multiply by the screen's backing scale for the
        // actual captured pixel count (Retina = ×2).
        if let cursor = lastDragPoint {
            let scale = freezeImage != nil ? freezeScale : (window?.backingScaleFactor ?? 2)
            let wpx = Int((selection.width * scale).rounded())
            let hpx = Int((selection.height * scale).rounded())
            drawDimensionBadge("\(wpx) × \(hpx)", near: cursor)
        }
    }

    /// Crop the frozen screenshot to `rectInView` (this view's coords, bottom-left
    /// origin), converting to the image's pixel space (top-left origin). Returns nil
    /// when there's no freeze (the caller then falls back to a live re-capture).
    func croppedImage(for rectInView: NSRect) -> CGImage? {
        guard let frozen = freezeImage else { return nil }
        let s = freezeScale
        let px = CGRect(x: rectInView.minX * s,
                        y: (bounds.height - rectInView.maxY) * s,
                        width: rectInView.width * s,
                        height: rectInView.height * s).integral
        let clamped = px.intersection(CGRect(x: 0, y: 0, width: frozen.width, height: frozen.height))
        guard clamped.width >= 1, clamped.height >= 1 else { return nil }
        return frozen.cropping(to: clamped)
    }

    /// A small rounded "W × H" badge near the cursor. Clamped to the view so it
    /// never spills off the screen edge while dragging.
    private func drawDimensionBadge(_ text: String, near point: NSPoint) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let padX: CGFloat = 8, padY: CGFloat = 4
        let boxW = textSize.width + padX * 2, boxH = textSize.height + padY * 2
        // Sit just below-right of the cursor (view is bottom-left origin).
        var x = point.x + 14
        var y = point.y - boxH - 14
        x = min(max(x, 4), bounds.width - boxW - 4)
        y = min(max(y, 4), bounds.height - boxH - 4)
        let box = NSRect(x: x, y: y, width: boxW, height: boxH)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        str.draw(at: NSPoint(x: x + padX, y: y + padY))
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

    private var onComplete: ((CaptureMode, CGImage?, CGRect) -> Void)?
    private var onCancel: (() -> Void)?

    var isActive: Bool { !overlays.isEmpty }

    /// Start a selection with `preselect` highlighted. If one's already running,
    /// just move the highlight (pressing another capture shortcut re-targets).
    func begin(preselect: CaptureMode,
               anchorRect: NSRect?,
               frozen: [CGDirectDisplayID: CGImage],
               onComplete: @escaping (CaptureMode, CGImage?, CGRect) -> Void,
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
            // Hand this screen's frozen snapshot to its overlay (if we have one).
            if let sid = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
               let img = frozen[sid] {
                view.freezeImage = img
                view.freezeScale = screen.backingScaleFactor
            }
            view.onDragBegan = { [weak self] in self?.hideToolbar() }
            view.onCommit = { [weak self, weak view] rectInView in
                let cropped = view?.croppedImage(for: rectInView)
                self?.commit(rectInView: rectInView, screenOrigin: screenOrigin, image: cropped)
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

    private func commit(rectInView: NSRect, screenOrigin: NSPoint, image: CGImage?) {
        guard !overlays.isEmpty else { return }
        let mode = barModel?.selected ?? .save
        // View coords (origin = this screen's bottom-left) → global Cocoa coords.
        let global = CGRect(x: rectInView.minX + screenOrigin.x,
                            y: rectInView.minY + screenOrigin.y,
                            width: rectInView.width, height: rectInView.height)
        let cb = onComplete
        teardown()
        if image != nil {
            // Frozen crop already in hand → deliver right away (no re-capture).
            cb?(mode, image, global)
        } else {
            // No freeze (macOS 13): let the compositor drop the overlay before the
            // caller live-captures the rect.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { cb?(mode, nil, global) }
        }
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            // Space toggles "move the selection" on whichever overlay is mid-drag.
            // Key events go to the key overlay, which may not be the dragged one,
            // so broadcast to every overlay (only the dragging one actually moves).
            if event.keyCode == 49 {
                let moving = event.type == .keyDown
                for win in self.overlays {
                    (win.contentView as? SelectionOverlayView)?.setMoving(moving)
                }
                return nil
            }
            guard event.type == .keyDown, let model = self.barModel else { return event }
            switch event.keyCode {
            case 53: self.cancel(); return nil          // Esc
            case 123: model.move(-1); return nil         // ←
            case 124: model.move(1); return nil          // →
            default: return event
            }
        }
    }
}
