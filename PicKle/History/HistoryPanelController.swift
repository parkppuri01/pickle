import AppKit
import SwiftUI

/// Borderless NSPanel that *can* accept key + main status. A styleMask-less
/// NSPanel is too restrictive — SwiftUI inputs (TextField, onTapGesture,
/// onHover) need a key window with main status to behave. Inherited from
/// pizzaClip's `FocusablePanel` so the 0.2.0 thumbnail grid gets working input.
final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosts the history panel in a borderless NSPanel anchored under the status
/// icon. Mirrors pizzaClip's PopupPanelController, trimmed to the 0.1.0 skeleton:
/// the key-monitor / paste-engine wiring arrives with the grid, but the panel
/// lifecycle (focusable, drop-down animation, click-outside dismiss, observer
/// cleanup) is in place now so later versions aren't a dead-end.
final class HistoryPanelController {
    private var panel: FocusablePanel?
    private var resignKeyObserver: NSObjectProtocol?
    private let viewModel: HistoryViewModel

    init(viewModel: HistoryViewModel) {
        self.viewModel = viewModel
    }

    deinit {
        if let o = resignKeyObserver { NotificationCenter.default.removeObserver(o) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// Show if hidden, hide if visible.
    func toggle(anchorRect: NSRect?) {
        if let panel, panel.isVisible { close(); return }
        show(anchorRect: anchorRect)
    }

    /// Open the panel only if it isn't already showing (avoids stacking a second
    /// panel when something — e.g. a save-capture — wants it open).
    func openIfNeeded(anchorRect: NSRect?) {
        guard !isVisible else { return }
        show(anchorRect: anchorRect)
    }

    func show(anchorRect: NSRect?) {
        viewModel.reload()
        let hosting = NSHostingView(rootView: HistoryView(vm: viewModel))

        let panel = FocusablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: Theme.panelHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.contentView = hosting
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = Theme.panelRadius
        panel.contentView?.layer?.masksToBounds = true

        let target = targetFrame(anchorRect: anchorRect)
        // Start a touch above the target and transparent so the panel "drops
        // down" from the menu bar icon.
        panel.setFrame(target.offsetBy(dx: 0, dy: 24), display: false)
        panel.alphaValue = 0

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Don't auto-focus any control (the lock/✕ buttons) — avoids an initial
        // blue focus ring when the panel opens.
        panel.makeFirstResponder(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }

        self.panel = panel

        // Clicking another window resigns the panel's key status; treat that as
        // "user moved on" and dismiss — UNLESS the user pinned it (자물쇠 잠금),
        // in which case it stays until the ✕ button closes it.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, !self.viewModel.isLocked else { return }
            self.close()
        }
    }

    func close() {
        if let o = resignKeyObserver {
            NotificationCenter.default.removeObserver(o)
            resignKeyObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    /// Anchor the panel under the status item, on the screen that actually holds
    /// the icon (multi-monitor correct), clamped to that screen's visible frame.
    private func targetFrame(anchorRect: NSRect?) -> NSRect {
        let w = Theme.panelWidth, h = Theme.panelHeight
        if let anchor = anchorRect {
            let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) })
                ?? NSScreen.main!
            let visible = screen.visibleFrame
            var x = anchor.midX - w / 2
            x = min(max(x, visible.minX + 8), visible.maxX - w - 8)
            let y = anchor.minY - h - 4
            return NSRect(x: x, y: y, width: w, height: h)
        }
        // Fallback — screen center, biased upward (Spotlight style).
        let visible = NSScreen.main!.visibleFrame
        return NSRect(x: visible.midX - w / 2,
                      y: visible.midY - h / 2 + visible.height * 0.10,
                      width: w, height: h)
    }
}
