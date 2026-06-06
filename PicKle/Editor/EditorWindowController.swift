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
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
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
