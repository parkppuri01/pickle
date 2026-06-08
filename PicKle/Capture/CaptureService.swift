import AppKit
import ScreenCaptureKit

/// Region capture for the custom ⇧⌘5-style overlay.
///
/// Capture path = **ScreenCaptureKit** (`SCScreenshotManager`). On modern macOS
/// (Sequoia/Tahoe+) this is the only reliable option: `CGWindowListCreateImage`
/// returns a blank image, and shelling out to `/usr/sbin/screencapture` fails
/// ("could not create image from rect") because the spawned process does NOT
/// inherit PICkle's Screen Recording grant — the in-process SCK API uses our own
/// TCC permission. macOS 13 falls back to Quartz (`captureLegacy`).
final class CaptureService {
    static let shared = CaptureService()
    private init() {}

    /// Warm up ScreenCaptureKit so the first capture after launch isn't empty —
    /// the capture daemon needs a beat to enumerate displays after the app starts.
    func warmUp() {
        if #available(macOS 14.0, *) {
            Task { _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        }
    }

    // MARK: - Freeze (snapshot every screen the instant the shortcut fires)

    /// Snapshot every screen NOW at full resolution, keyed by display ID. The
    /// selection overlay uses these as a frozen backdrop, so the user picks a
    /// region on the *still* image from the moment the shortcut was pressed —
    /// not a live screen that keeps changing while they drag. The crop is taken
    /// from this image too (no second, later capture).
    @available(macOS 14.0, *)
    func freezeScreens() async -> [CGDirectDisplayID: CGImage] {
        var out: [CGDirectDisplayID: CGImage] = [:]
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            for screen in NSScreen.screens {
                guard let sid = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                      let display = content.displays.first(where: { $0.displayID == sid }) else { continue }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                let scale = screen.backingScaleFactor
                config.width = Int((screen.frame.width * scale).rounded())
                config.height = Int((screen.frame.height * scale).rounded())
                config.showsCursor = false
                config.ignoreShadowsDisplay = true
                config.captureResolution = .best
                if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                    out[sid] = img
                }
            }
        } catch {
            NSLog("PICkle freeze error: \(error)")
        }
        return out
    }

    /// Save an already-captured CGImage (e.g. a crop from the frozen screen) to the
    /// bottle folder. PNG encode + write happen off the main thread.
    func saveImageToFile(_ cg: CGImage, completion: @escaping (URL?) -> Void) {
        let url = uniqueURL()
        DispatchQueue.global(qos: .userInitiated).async {
            let rep = NSBitmapImageRep(cgImage: cg)
            var saved = false
            if let png = rep.representation(using: .png, properties: [:]) {
                do { try png.write(to: url); saved = true }
                catch { NSLog("PICkle capture write failed: \(error)") }
            }
            DispatchQueue.main.async { completion(saved ? url : nil) }
        }
    }

    /// Copy an already-captured CGImage straight to the clipboard (NOT saved).
    /// `pointSize` is the logical selection size so a Retina crop pastes 1× sized.
    func copyImageToClipboard(_ cg: CGImage, pointSize: CGSize, completion: @escaping (Bool) -> Void) {
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: pointSize.width, height: pointSize.height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        let pb = NSPasteboard.general
        pb.clearContents()
        completion(pb.writeObjects([image]))
    }

    // MARK: - Region capture (custom selection overlay → ScreenCaptureKit)

    /// Capture a fixed rectangle (no interaction) into the bottle folder.
    /// `cocoaRect` is in global Cocoa coordinates (bottom-left origin).
    func captureRegionToFile(cocoaRect: CGRect, completion: @escaping (URL?) -> Void) {
        captureRegionImage(cocoaRect: cocoaRect) { [weak self] cg in
            guard let self else { completion(nil); return }
            guard let cg else { completion(nil); return }
            let url = self.uniqueURL()
            // PNG encode + disk write off the main thread — a large Retina capture
            // can otherwise block the UI for a noticeable beat. Result back on main.
            DispatchQueue.global(qos: .userInitiated).async {
                let rep = NSBitmapImageRep(cgImage: cg)
                var saved = false
                if let png = rep.representation(using: .png, properties: [:]) {
                    do { try png.write(to: url); saved = true }
                    catch { NSLog("PICkle capture write failed: \(error)") }
                }
                DispatchQueue.main.async { completion(saved ? url : nil) }
            }
        }
    }

    /// Capture a fixed rectangle straight to the clipboard (NOT saved).
    func captureRegionToClipboard(cocoaRect: CGRect, completion: @escaping (Bool) -> Void) {
        captureRegionImage(cocoaRect: cocoaRect) { cg in
            guard let cg else { completion(false); return }
            let rep = NSBitmapImageRep(cgImage: cg)
            // The rep is in PIXELS; set its POINT size to the logical selection so
            // a Retina capture pastes at the right physical size (not 2×). It's the
            // rep's own size that survives the pasteboard round-trip, not NSImage's.
            rep.size = NSSize(width: cocoaRect.width, height: cocoaRect.height)
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            let pb = NSPasteboard.general
            pb.clearContents()
            completion(pb.writeObjects([image]))
        }
    }

    /// Capture `cocoaRect` (global Cocoa, bottom-left origin) to a CGImage,
    /// delivering the result on the main queue.
    private func captureRegionImage(cocoaRect: CGRect, completion: @escaping (CGImage?) -> Void) {
        if #available(macOS 14.0, *) {
            Task { @MainActor in completion(await Self.captureSCK(cocoaRect: cocoaRect)) }
        } else {
            completion(Self.captureLegacy(cocoaRect: cocoaRect))
        }
    }

    /// ScreenCaptureKit path (macOS 14+) — the only one that yields real pixels on
    /// modern macOS, using PICkle's own Screen Recording grant.
    @available(macOS 14.0, *)
    private static func captureSCK(cocoaRect: CGRect) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // The screen the selection's CENTER lands on (intersects can pick the
            // wrong one when a rect straddles a monitor edge).
            let center = CGPoint(x: cocoaRect.midX, y: cocoaRect.midY)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
                    ?? NSScreen.screens.first(where: { $0.frame.intersects(cocoaRect) })
                    ?? NSScreen.main else { return nil }
            // NSScreenNumber is an NSNumber; a direct `as? CGDirectDisplayID`
            // (UInt32) cast returns nil — go through uint32Value. Match the EXACT
            // SCDisplay; never fall back to the first display (that captured a blank
            // rect from the wrong monitor — the original main-display bug).
            let sid = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            guard let display = content.displays.first(where: { $0.displayID == sid }) else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            // sourceRect: display-local, top-left origin, in points.
            let local = CGRect(x: cocoaRect.minX - screen.frame.minX,
                               y: screen.frame.maxY - cocoaRect.maxY,
                               width: cocoaRect.width, height: cocoaRect.height)
            let scale = screen.backingScaleFactor
            config.sourceRect = local
            config.width = Int((local.width * scale).rounded())
            config.height = Int((local.height * scale).rounded())
            config.showsCursor = false
            config.ignoreShadowsDisplay = true
            config.captureResolution = .best
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            NSLog("PICkle SCK capture error: \(error)")
            return nil
        }
    }

    /// Legacy fallback for macOS 13 (Quartz still returns real pixels there).
    private static func captureLegacy(cocoaRect: CGRect) -> CGImage? {
        let scRect = screencaptureRect(fromCocoaGlobal: cocoaRect)
        return CGWindowListCreateImage(scRect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
    }

    /// Convert a global Cocoa rect (origin bottom-left of the primary screen, y up)
    /// to top-left origin space for the macOS 13 Quartz fallback.
    private static func screencaptureRect(fromCocoaGlobal rect: CGRect) -> CGRect {
        let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? rect.maxY
        return CGRect(x: rect.minX.rounded(), y: (primaryH - rect.maxY).rounded(),
                      width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// A timestamped path in the bottle folder, guaranteed not to collide with an
    /// existing file (two captures in the same second get ` (2)`, ` (3)`, …).
    private func uniqueURL() -> URL {
        let dir = AppPaths.bottleDirectory
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "PICkle \(df.string(from: Date()))"

        var url = dir.appendingPathComponent("\(base).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(n)).png")
            n += 1
        }
        return url
    }
}
