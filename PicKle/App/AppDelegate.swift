import AppKit
import KeyboardShortcuts

/// Composition root — the single wiring hub (pizzaClip pattern). Owns the status
/// item, the history panel, the capture shortcuts, and the loosely-coupled
/// notification observers.
///
/// 0.3.0 scope: ⇧⌥S normal capture, ⇧⌥D feature capture → editor (pen tool).
/// Both save into the `pickle bottle` folder shown as a thumbnail grid.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var contextMenu: NSMenu!
    private let viewModel = HistoryViewModel()
    private lazy var panelController = HistoryPanelController(viewModel: viewModel)
    private let editorController = EditorWindowController()
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the user-facing `pickle bottle` folder on first run.
        _ = AppPaths.bottleDirectory

        setUpStatusItem()
        setUpShortcuts()
        registerObservers()
        runRetentionSweep()
        scheduleRetentionSweep()
        refreshStatusIcon()
    }

    // MARK: - Retention (auto-delete)

    /// Trash screenshots older than the user's retention period, then refresh the
    /// UI if anything was removed. Runs on launch, daily, and after the user
    /// changes the period in Settings.
    private func runRetentionSweep() {
        if RetentionService.sweep() > 0 {
            viewModel.reload()
            refreshStatusIcon()
        }
    }

    /// Re-check once a day while the app stays open (most Macs aren't restarted
    /// daily). Tolerant timing is fine — this is housekeeping, not real-time.
    private func scheduleRetentionSweep() {
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            self?.runRetentionSweep()
        }
        retentionTimer?.tolerance = 3_600
    }

    // MARK: - Capture

    private func setUpShortcuts() {
        // ⇧⌥S: normal capture → save straight to the bottle folder.
        KeyboardShortcuts.onKeyDown(for: .captureNormal) { [weak self] in
            self?.performCapture(openEditor: false)
        }
        // ⇧⌥D: feature capture → save, then open the editor on the result.
        KeyboardShortcuts.onKeyDown(for: .captureFeature) { [weak self] in
            self?.performCapture(openEditor: true)
        }
        // ⇧⌥A: clipboard capture → straight to the clipboard, NOT saved to the
        // bottle. pizzaClip (if running) catches it off the clipboard.
        KeyboardShortcuts.onKeyDown(for: .captureClipboard) {
            CaptureService.shared.captureInteractiveToClipboard { _ in }
        }
    }

    /// Captures interactively. The file lands in `pickle bottle` immediately
    /// (so it's never lost even if the editor is cancelled); when `openEditor`
    /// is true we then open the editor on it.
    private func performCapture(openEditor: Bool) {
        CaptureService.shared.captureInteractive { [weak self] url in
            guard let self, let url else { return }   // nil = user cancelled
            NotificationCenter.default.post(name: .pickleScreenshotsChanged, object: nil)
            if openEditor { self.editorController.open(url: url) }
        }
    }

    private func refreshStatusIcon() {
        let count = ScreenshotStore.count()
        statusItem.button?.image = PickleIcon.image(forCount: count)
        // Keep the bottle folder's Finder icon in sync (empty jar ↔ pickle jar).
        FolderIcon.apply(forCount: count)
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = PickleIcon.image(forCount: 0)
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: "Open Bottle History",
                                       action: #selector(openPanel), keyEquivalent: ""))
        contextMenu.addItem(NSMenuItem(title: "Settings…",
                                       action: #selector(openSettings), keyEquivalent: ","))
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: "Open pickle bottle Folder",
                                       action: #selector(openBottleFolder), keyEquivalent: ""))
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: "Quit PIC.kle",
                                       action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private var statusItemFrame: NSRect? { statusItem.button?.window?.frame }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let isContextClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isContextClick {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            panelController.toggle(anchorRect: statusItemFrame)
        }
    }

    // MARK: - Actions

    @objc private func openPanel() { panelController.toggle(anchorRect: statusItemFrame) }
    @objc private func openSettings() { showSettingsWindow() }
    @objc private func openBottleFolder() {
        NSWorkspace.shared.open(AppPaths.bottleDirectory)
    }

    /// Confirm before clearing — folder-as-truth means Clear all sweeps every
    /// image in the bottle folder to the Trash, so we never do it silently.
    private func confirmAndClearAll() {
        let count = ScreenshotStore.count()
        guard count > 0 else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "스크린샷 \(count)개를 모두 휴지통으로 보낼까요?"
        alert.informativeText = "‘pickle bottle’ 폴더의 이미지가 휴지통으로 이동합니다. (휴지통에서 복구 가능)"
        alert.addButton(withTitle: "모두 비우기")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ScreenshotStore.deleteAll()
        viewModel.reload()
        refreshStatusIcon()
    }

    // MARK: - Observers

    private func registerObservers() {
        NotificationCenter.default.addObserver(forName: .pickleOpenSettings, object: nil, queue: .main) { [weak self] _ in
            self?.showSettingsWindow()
        }
        NotificationCenter.default.addObserver(forName: .pickleClearAll, object: nil, queue: .main) { [weak self] _ in
            self?.confirmAndClearAll()
        }
        // Single refresh path for both captures and editor saves.
        NotificationCenter.default.addObserver(forName: .pickleScreenshotsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.viewModel.reload()
            self?.refreshStatusIcon()
        }
        // Double-clicking a thumbnail opens the editor on that file.
        NotificationCenter.default.addObserver(forName: .pickleEditScreenshot, object: nil, queue: .main) { [weak self] note in
            guard let url = note.object as? URL else { return }
            self?.panelController.close()
            self?.editorController.open(url: url)
        }
        // Retention period changed → sweep right away with the new value.
        NotificationCenter.default.addObserver(forName: .pickleRetentionChanged, object: nil, queue: .main) { [weak self] _ in
            self?.runRetentionSweep()
        }
        // Storage folder changed → the bottle now points elsewhere; reload.
        NotificationCenter.default.addObserver(forName: .pickleStorageLocationChanged, object: nil, queue: .main) { [weak self] _ in
            self?.viewModel.reload()
            self?.refreshStatusIcon()
        }
        // History panel ✕ button → close it.
        NotificationCenter.default.addObserver(forName: .pickleCloseHistoryPanel, object: nil, queue: .main) { [weak self] _ in
            self?.panelController.close()
        }
    }

    /// Opens the SwiftUI `Settings` scene by synthesizing ⌘, (pizzaClip trick:
    /// recent macOS treats `showSettingsWindow:` as a no-op with a warning).
    private func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 0x2B
            ) else { return }
            NSApp.postEvent(event, atStart: false)
        }
    }
}
