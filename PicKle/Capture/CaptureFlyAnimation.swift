import AppKit

/// The save-capture flourish: the just-captured image appears, then shrinks and
/// flies up into the menu-bar icon ("sucked in"), after which the caller opens
/// the history popup.
///
/// With the custom selection overlay we know the captured region's on-screen
/// rect (global Cocoa coords), so the image starts *exactly where it was
/// captured* and shrinks toward the icon. If the rect is missing we fall back to
/// the center of the menu-bar screen. If anything's missing we skip straight to
/// `completion` so the popup still opens.
enum CaptureFlyAnimation {
    static func play(imageURL: URL, startRect: CGRect?, anchorRect: NSRect?,
                     completion: @escaping () -> Void) {
        guard let anchor = anchorRect, let image = NSImage(contentsOf: imageURL),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) }) ?? NSScreen.main
        else { completion(); return }

        let visible = screen.visibleFrame

        // Start from the real captured region when we have it; otherwise an image-
        // aspect box centered on the menu-bar screen.
        let startFrame: NSRect
        if let r = startRect, r.width > 1, r.height > 1 {
            startFrame = r
        } else {
            let maxBox: CGFloat = 360
            let aspect = image.size.width > 0 ? image.size.height / image.size.width : 0.66
            var startW = maxBox, startH = maxBox * aspect
            if startH > maxBox { startH = maxBox; startW = maxBox / max(aspect, 0.01) }
            startFrame = NSRect(x: visible.midX - startW / 2, y: visible.midY - startH / 2,
                                width: startW, height: startH)
        }

        // End: a tiny square centered on the menu-bar icon.
        let endSize: CGFloat = 22
        let endFrame = NSRect(x: anchor.midX - endSize / 2, y: anchor.midY - endSize / 2,
                              width: endSize, height: endSize)

        let win = NSWindow(contentRect: startFrame, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false            // smoother: no per-frame shadow recompute
        win.ignoresMouseEvents = true
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        win.contentView = imageView

        win.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.45
            // easeIn = accelerate as it's "sucked" into the bar.
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().setFrame(endFrame, display: true)
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)            // closure retains `win` through the animation
            completion()
        })
    }
}
