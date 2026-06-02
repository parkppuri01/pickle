import KeyboardShortcuts

/// Global, user-customizable shortcuts (pizzaClip's KeyboardShortcuts pattern).
///
/// Defaults chosen to avoid clobbering macOS system capture shortcuts:
///   - normal capture:    ⇧⌥S  (the "replacement" for ⇧⌘4 → saved to the bottle)
///   - feature capture:   ⇧⌥D  (capture → editor → saved to the bottle)
///   - clipboard capture: ⇧⌥A  (capture straight to the clipboard; NOT saved to
///                              the bottle. If pizzaClip is running it catches it.)
///
/// All three are user-customizable in Settings → 단축키.
extension KeyboardShortcuts.Name {
    static let captureNormal = Self("captureNormal", default: .init(.s, modifiers: [.option, .shift]))
    static let captureFeature = Self("captureFeature", default: .init(.d, modifiers: [.option, .shift]))
    static let captureClipboard = Self("captureClipboard", default: .init(.a, modifiers: [.option, .shift]))
}
