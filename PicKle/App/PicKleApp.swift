import SwiftUI

@main
struct PICkleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A real Settings scene so macOS's ⌘, accelerator opens the right window.
        // 0.1.0 ships a placeholder; tabs (General / Shortcuts / Storage) come later.
        Settings { SettingsView() }
    }
}
