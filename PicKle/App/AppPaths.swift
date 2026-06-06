import Foundation

/// Filesystem locations for PICkle.
///
/// - `supportDirectory`: app-private data (DB/metadata in later versions),
///   under ~/Library/Application Support/PICkle. Mirrors pizzaClip's pattern.
/// - `bottleDirectory`: the user-visible **`PICkle bottle`** folder created in
///   the user's Documents on first run. Captured screenshots live here so they
///   land in a tidy folder instead of cluttering the Desktop (see HANDOFF §1).
enum AppPaths {
    static let storageDirectoryDefaultsKey = "storageDirectory"
    static let bottleFolderName = "PICkle bottle"

    /// App-private support directory (auto-created).
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PICkle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// User-facing `PICkle bottle` folder. Honors a custom override path if the
    /// user picked one in Settings; otherwise defaults to ~/Documents/PICkle bottle.
    static var bottleDirectory: URL {
        let dir: URL
        if let custom = UserDefaults.standard.string(forKey: storageDirectoryDefaultsKey),
           !custom.isEmpty {
            dir = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first!
            dir = documents.appendingPathComponent(bottleFolderName, isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
