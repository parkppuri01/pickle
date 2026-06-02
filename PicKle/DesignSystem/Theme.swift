import CoreGraphics

/// Shape tokens — inherited from pizzaClip so the two apps feel like siblings.
/// The history panel keeps the same corner radii; the panel itself is a touch
/// wider to host a screenshot thumbnail grid (vs. clipboard text rows).
enum Theme {
    static let panelRadius: CGFloat = 14
    static let rowRadius: CGFloat = 8
    static let panelWidth: CGFloat = 460
    static let panelHeight: CGFloat = 500
}
