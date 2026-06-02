import SwiftUI

/// Drives the history panel. Reloads the screenshot list from the `pickle
/// bottle` folder on demand (panel open, capture finished, clear-all).
/// Always used from the main thread.
final class HistoryViewModel: ObservableObject {
    @Published private(set) var screenshots: [Screenshot] = []
    /// Pinned ("자물쇠") state: when true the panel stays open even after it
    /// loses focus; only the ✕ button closes it. Persisted so the panel reopens
    /// in whatever lock state the user last left it in.
    @Published var isLocked = UserDefaults.standard.bool(forKey: "historyPanelLocked") {
        didSet { UserDefaults.standard.set(isLocked, forKey: Self.lockedDefaultsKey) }
    }
    private static let lockedDefaultsKey = "historyPanelLocked"
    /// Transient confirmation banner text (auto-clears).
    @Published var toast: String?
    private var toastToken = 0

    func reload() {
        screenshots = ScreenshotStore.all()
    }

    func delete(_ shot: Screenshot) {
        ScreenshotStore.delete(shot)
        reload()
    }

    /// Copy-button action: copy the screenshot to the clipboard and confirm.
    func copyToClipboard(_ shot: Screenshot) {
        ClipboardService.copy(shot.url)
        showToast(ClipboardService.copyConfirmation)
    }

    /// Double-click action: open the editor on this screenshot.
    func requestEdit(_ shot: Screenshot) {
        NotificationCenter.default.post(name: .pickleEditScreenshot, object: shot.url)
    }

    private func showToast(_ message: String) {
        toast = message
        toastToken += 1
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toast = nil
        }
    }
}
