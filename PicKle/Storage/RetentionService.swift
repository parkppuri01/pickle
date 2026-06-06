import Foundation

/// Auto-deletes old screenshots so the `PICkle bottle` folder doesn't grow
/// forever. Folder-as-truth (no DB), so we judge age by each file's
/// modification date and move expired ones to the Trash (recoverable).
///
/// The retention period lives in UserDefaults under `autoDeleteDays`:
///   - `0` (the "off" sentinel) = keep everything, never auto-delete.
///   - any positive N = delete files older than N days.
/// Default is 30 days (see `defaultDays`), applied when the key was never set.
enum RetentionService {
    static let defaultsKey = "autoDeleteDays"
    static let defaultDays = 30

    /// Selectable periods for the Settings picker. `0` = off.
    static let options: [Int] = [0, 7, 14, 30, 60, 90]

    /// Current retention in days (0 = off). Falls back to `defaultDays` when the
    /// user has never touched the setting.
    static var retentionDays: Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: defaultsKey) == nil { return defaultDays }
        return defaults.integer(forKey: defaultsKey)
    }

    /// Sweep the bottle folder, trashing anything older than the retention
    /// period. No-op when retention is off. Returns the number of files removed.
    @discardableResult
    static func sweep() -> Int {
        let days = retentionDays
        guard days > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)

        var removed = 0
        for shot in ScreenshotStore.all() where shot.date < cutoff {
            ScreenshotStore.delete(shot)
            removed += 1
        }
        if removed > 0 {
            NSLog("PICkle retention: trashed \(removed) screenshot(s) older than \(days) day(s).")
        }
        return removed
    }
}
