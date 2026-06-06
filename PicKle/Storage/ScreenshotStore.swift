import Foundation

/// A screenshot file living in the `PICkle bottle` folder.
struct Screenshot: Identifiable, Equatable {
    let url: URL
    let date: Date
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// Folder-as-truth store: the `PICkle bottle` folder *is* the database. We just
/// list its image files, newest first. No SQLite needed — screenshots are real
/// user files, so drag-out and Finder integration come for free. (A metadata DB
/// can be added later if editing/search needs it — see HANDOFF §3.)
enum ScreenshotStore {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

    /// All screenshots in the bottle folder, sorted newest → oldest.
    static func all() -> [Screenshot] {
        let dir = AppPaths.bottleDirectory
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return Screenshot(url: url, date: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
    }

    static func count() -> Int { all().count }

    /// Move a single screenshot to the Trash (recoverable).
    static func delete(_ shot: Screenshot) {
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
    }

    /// Move every screenshot to the Trash.
    static func deleteAll() {
        for shot in all() { delete(shot) }
    }
}
