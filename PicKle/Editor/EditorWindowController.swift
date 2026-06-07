import AppKit
import SwiftUI

/// Opens the editor in a normal titled window. PICkle is an LSUIElement (menu
/// bar) app, but it can still show ordinary windows when activated.
final class EditorWindowController {
    private var window: NSWindow?

    /// Open the editor on a captured file. No-op if the image can't be loaded.
    func open(url: URL) {
        guard let model = EditorModel(fileURL: url) else {
            NSLog("PICkle editor: couldn't load \(url.lastPathComponent)")
            return
        }
        // One editor at a time — replace any existing window.
        close()

        let view = EditorView(model: model, onClose: { [weak self] in self?.close() })
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = L("editor.windowTitle")
        // Resizable + miniaturizable so the user can shrink an oversized editor.
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.isReleasedWhenClosed = false
        // Dark editor chrome (편집팝업예시.png): a transparent title bar over the
        // dark window background blends the title strip into the canvas.
        win.titlebarAppearsTransparent = true
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = NSColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)
        // NOTE: do NOT set isMovableByWindowBackground — it would steal pen/blur
        // drags on the canvas and move the whole window instead of drawing.

        // Open at a size that fits the screen; large captures scale to fit
        // (the canvas auto-scales via GeometryReader in EditorView).
        let d = model.displaySize
        let rail: CGFloat = 56, topBar: CGFloat = 56, pad: CGFloat = 24
        let visible = (NSScreen.main?.visibleFrame.size) ?? CGSize(width: 1440, height: 900)
        let wantW = rail + d.width + pad * 2
        let wantH = topBar + d.height + pad * 2
        win.setContentSize(CGSize(width: min(wantW, visible.width * 0.9),
                                  height: min(wantH, visible.height * 0.9)))
        win.contentMinSize = CGSize(width: rail + 260, height: topBar + 200)
        win.center()

        self.window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}
