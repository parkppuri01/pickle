import AppKit

/// Sets a custom Finder icon on the `PICkle bottle` folder so it stands out, and
/// flips between the empty jar and the pickle-filled jar to mirror whether the
/// folder holds any screenshots.
///
/// `NSWorkspace.setIcon` is a little heavy (it writes the folder's icon
/// resource), so we only re-apply when the path or the empty/filled state
/// actually changes — not on every single capture.
enum FolderIcon {
    private static var appliedKey: String?

    /// Apply the jar icon matching the screenshot count to the bottle folder.
    static func apply(forCount count: Int, path: String = AppPaths.bottleDirectory.path) {
        let isEmpty = count == 0
        let key = "\(path)|\(isEmpty)"
        guard appliedKey != key else { return }
        appliedKey = key

        let name = isEmpty ? "FolderIconEmpty" : "FolderIconFull"
        guard let icon = NSImage(named: name) else { return }
        NSWorkspace.shared.setIcon(icon, forFile: path, options: [])
    }
}
