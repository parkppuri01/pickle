import AppKit

/// Status-bar icon — the pickle jar ("bottle") that ties to the `pickle bottle`
/// storage folder. Mirrors pizzaClip's `PizzaIcon` pattern.
///
/// Loaded as `template-rendering-intent: original` so the painted green/yellow
/// jar survives instead of being collapsed by the menu-bar template tint.
///
/// Two states by screenshot count:
///   - count == 0 → **empty jar** (`MenuBarIconEmpty`)
///   - count  > 0 → **pickle-filled jar** (`MenuBarIcon`)
enum PickleIcon {
    static let defaultPointSize: CGFloat = 18

    static func image(forCount count: Int = 0, size: CGFloat = defaultPointSize) -> NSImage {
        // Empty bottle when there's nothing saved, filled bottle once it has
        // pickles (screenshots).
        let assetName = count > 0 ? "MenuBarIcon" : "MenuBarIconEmpty"
        // Fall back to a visible SF Symbol (not a blank transparent image) if the
        // asset is ever missing, so a packaging slip-up never yields an invisible
        // menu-bar item that's maddening to debug.
        let image = NSImage(named: assetName)
            ?? NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: size, height: size))
        image.size = NSSize(width: size, height: size)
        image.isTemplate = false
        image.accessibilityDescription = "PIC.kle — \(count) screenshots"
        return image
    }
}
