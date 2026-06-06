import AppKit

/// Wraps macOS's built-in `/usr/sbin/screencapture` tool (HANDOFF decision:
/// reuse Apple's capture UI rather than building our own selection overlay).
///
/// `-i` = interactive: the user drags a region, or presses Space to switch to
/// window mode, or Esc to cancel. On cancel no file is written, so we report
/// `nil` and the caller does nothing.
///
/// This is a `class` (not an `enum`) on purpose: an interactive capture runs for
/// several seconds while the user drags, and we must keep the `Process` alive
/// the whole time so its `terminationHandler` actually fires. We retain each
/// in-flight process and drop it only once it finishes.
final class CaptureService {
    static let shared = CaptureService()
    private init() {}

    private var inFlight: [Process] = []

    /// Run an interactive capture, saving a PNG into the `PICkle bottle` folder.
    /// Calls `completion` on the main queue with the saved file URL, or `nil` if
    /// the user cancelled / the capture failed.
    func captureInteractive(completion: @escaping (URL?) -> Void) {
        let url = uniqueURL()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive, -o no window shadow (window mode), then destination.
        task.arguments = ["-i", "-o", url.path]
        task.terminationHandler = { [weak self] proc in
            // Success = clean exit AND a file actually landed (Esc → no file).
            let ok = proc.terminationStatus == 0
                && FileManager.default.fileExists(atPath: url.path)
            DispatchQueue.main.async {
                self?.inFlight.removeAll { $0 === proc }
                completion(ok ? url : nil)
            }
        }

        do {
            inFlight.append(task)
            try task.run()
        } catch {
            NSLog("PICkle capture failed to launch screencapture: \(error)")
            inFlight.removeAll { $0 === task }
            DispatchQueue.main.async { completion(nil) }
        }
    }

    /// Run an interactive capture straight to the **clipboard** (`-c`), without
    /// writing any file into the bottle folder. If pizzaClip is running it will
    /// pick the image up off the clipboard. Calls `completion(true)` once the
    /// capture finishes successfully, `false` if the user cancelled / it failed.
    func captureInteractiveToClipboard(completion: @escaping (Bool) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive, -c to clipboard, -o no window shadow.
        task.arguments = ["-i", "-c", "-o"]
        task.terminationHandler = { [weak self] proc in
            let ok = proc.terminationStatus == 0
            DispatchQueue.main.async {
                self?.inFlight.removeAll { $0 === proc }
                completion(ok)
            }
        }
        do {
            inFlight.append(task)
            try task.run()
        } catch {
            NSLog("PICkle clipboard capture failed to launch screencapture: \(error)")
            inFlight.removeAll { $0 === task }
            DispatchQueue.main.async { completion(false) }
        }
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
