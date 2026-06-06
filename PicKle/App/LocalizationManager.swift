import Foundation
import SwiftUI

/// The user-selectable app language. `system` follows the macOS language order.
enum AppLanguage: String, CaseIterable {
    case system
    case ko
    case en

    /// The localized label shown for this option in the language picker.
    var labelKey: String {
        switch self {
        case .system: return "settings.language.system"
        case .ko:     return "settings.language.korean"
        case .en:     return "settings.language.english"
        }
    }
}

/// Runtime language switching for PICkle. SwiftUI roots observe `shared` so a
/// language change redraws them immediately; AppKit windows pick up the new
/// strings the next time they're opened (both read through `L(_:)`).
///
/// We resolve a per-language `.lproj` bundle and look strings up in it directly,
/// instead of relying on the process-wide `Bundle.main` localization (which is
/// fixed at launch). That's what makes "switch without restart" possible.
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let defaultsKey = "appLanguage"

    /// The user's chosen language. Persisted, and recomputes `bundle` on change.
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            bundle = Self.resolveBundle(for: language)
        }
    }

    /// The `.lproj` bundle the current language resolves to. Strings are looked
    /// up here; falls back to `.main` if a specific language bundle is missing.
    private(set) var bundle: Bundle

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        let lang = stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.language = lang
        self.bundle = Self.resolveBundle(for: lang)
    }

    /// Look up a localized string for `key` in the current language bundle.
    /// Returns the key itself if no translation is found (so missing keys are
    /// visible rather than crashing).
    func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// Map an `AppLanguage` to a concrete `.lproj` bundle.
    private static func resolveBundle(for language: AppLanguage) -> Bundle {
        let code: String
        switch language {
        case .system:
            // Honor the user's macOS language order, restricted to what we ship.
            code = Bundle.main.preferredLocalizations.first ?? "en"
        case .ko:
            code = "ko"
        case .en:
            code = "en"
        }
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return .main
    }
}

/// Global shorthand for a localized string. Use everywhere user-facing text is
/// produced: `Text(L("history.title"))`, `NSMenuItem(title: L("menu.quit"))`.
func L(_ key: String) -> String {
    LocalizationManager.shared.string(key)
}
