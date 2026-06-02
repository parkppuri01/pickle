import Foundation

/// Loosely-coupled component messaging — pizzaClip's `.pizzaClip*` pattern,
/// renamed to `.pickle*`. Components post; AppDelegate observes and acts.
extension Notification.Name {
    static let pickleClearAll = Notification.Name("pickleClearAll")
    static let pickleOpenSettings = Notification.Name("pickleOpenSettings")
    static let pickleScreenshotsChanged = Notification.Name("pickleScreenshotsChanged")
    /// Open the editor on a screenshot. `object` is the file `URL`.
    static let pickleEditScreenshot = Notification.Name("pickleEditScreenshot")
    /// The auto-delete period changed in Settings → re-run the retention sweep.
    static let pickleRetentionChanged = Notification.Name("pickleRetentionChanged")
    /// The bottle storage folder changed in Settings → reload from the new path.
    static let pickleStorageLocationChanged = Notification.Name("pickleStorageLocationChanged")
    /// The history panel's ✕ button was pressed → close the panel.
    static let pickleCloseHistoryPanel = Notification.Name("pickleCloseHistoryPanel")
}
