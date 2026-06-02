import AppKit

/// Saved watermark logo images the user wants to reuse across edits. PNG/JPEG
/// files copied into an app-private folder so they survive even if the original
/// is moved. Managed from Settings → 워터마크; picked from in the editor.
enum WatermarkPresets {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff"]

    /// `~/Library/Application Support/PicKle/watermark-logos` (auto-created).
    static var directory: URL {
        let dir = AppPaths.supportDirectory.appendingPathComponent("watermark-logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Saved logo files, newest first.
    static func all() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
    }

    /// Copy a chosen image into the presets folder (non-colliding name).
    /// Returns the saved URL, or nil on failure.
    @discardableResult
    static func add(from source: URL) -> URL? {
        let dest = uniqueURL(forName: source.lastPathComponent)
        do { try FileManager.default.copyItem(at: source, to: dest); return dest }
        catch { NSLog("PicKle preset add failed: \(error)"); return nil }
    }

    /// Remove a saved preset (permanently — these are app-private copies).
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func uniqueURL(forName name: String) -> URL {
        let ns = name as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "png" : ns.pathExtension
        var url = directory.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}
