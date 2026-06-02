import AppKit

/// Copies a screenshot to the system clipboard, and knows whether the sibling
/// app pizzaClip is installed (so we can tailor the confirmation message —
/// pizzaClip watches the clipboard, so a copy effectively lands in its history).
enum ClipboardService {
    /// Bundle id of the sibling clipboard-history app.
    static let pizzaClipBundleID = "com.jekeun.pizzaClip"

    /// Write the screenshot to the general pasteboard as both an image and a
    /// file URL, so target apps can take whichever they prefer.
    static func copy(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        var objects: [NSPasteboardWriting] = []
        if let image = NSImage(contentsOf: url) { objects.append(image) }
        objects.append(url as NSURL)
        pb.writeObjects(objects)
    }

    /// True only if pizzaClip is **currently running** on this Mac — i.e. it's
    /// actually watching the clipboard and will catch this copy. Evaluated live
    /// on each user's machine, so every user gets the right message.
    static var isPizzaClipRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == pizzaClipBundleID
        }
    }

    /// The confirmation message to show after a copy.
    static var copyConfirmation: String {
        isPizzaClipRunning
            ? "PizzaClip으로 복사되었습니다"
            : "클립보드(복사)에 저장되었습니다"
    }
}
