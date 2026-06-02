import AppKit
import CoreGraphics

/// Screen Recording (TCC) permission helper.
///
/// Interactive `screencapture -i` is user-initiated through Apple's own tool, so
/// it generally works even without the host app holding Screen Recording
/// permission. We still expose a preflight check + a guided alert so that if a
/// future silent/full-screen capture path needs it, users have a clear route to
/// grant it. Mirrors pizzaClip's `Accessibility` helper shape.
enum ScreenRecordingPermission {
    /// True if the app already holds Screen Recording permission.
    static func isAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system permission request (adds the app to the Screen
    /// Recording list). Returns the resulting authorization state.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Opens System Settings → Privacy & Security → Screen Recording.
    static func openSystemSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
