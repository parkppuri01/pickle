import AppKit
import KeyboardShortcuts
import Sparkle

/// Composition root — the single wiring hub (pizzaClip pattern). Owns the status
/// item, the history panel, the capture shortcuts, and the loosely-coupled
/// notification observers.
///
/// 0.3.0 scope: ⇧⌥S normal capture, ⇧⌥D feature capture → editor (pen tool).
/// Both save into the `PICkle bottle` folder shown as a thumbnail grid.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var contextMenu: NSMenu!
    private let viewModel = HistoryViewModel()
    private lazy var panelController = HistoryPanelController(viewModel: viewModel)
    private let editorController = EditorWindowController()
    private let regionSelect = RegionSelectController()
    private var retentionTimer: Timer?
    // Auto-update (pizzaClip pattern). One updater instance for the app's whole
    // lifetime — starts immediately, checks every SUScheduledCheckInterval (24h)
    // against SUFeedURL. The context menu is rebuilt on every open, but the
    // "Check for Updates…" item always targets this single controller.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the user-facing `PICkle bottle` folder on first run.
        _ = AppPaths.bottleDirectory

        setUpStatusItem()
        setUpShortcuts()
        registerObservers()
        runRetentionSweep()
        scheduleRetentionSweep()
        refreshStatusIcon()
        CaptureService.shared.warmUp()
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
        // Each shortcut now opens the capture-ready bar with its own mode
        // pre-highlighted; the user confirms (or switches) before the region
        // drag. ⇧⌥S → save, ⇧⌥D → editor, ⇧⌥A → clipboard.
        KeyboardShortcuts.onKeyDown(for: .captureNormal) { [weak self] in
            self?.presentCaptureMenu(.save)
        }
        KeyboardShortcuts.onKeyDown(for: .captureFeature) { [weak self] in
            self?.presentCaptureMenu(.editor)
        }
        KeyboardShortcuts.onKeyDown(for: .captureClipboard) { [weak self] in
            self?.presentCaptureMenu(.clipboard)
        }
    }

    /// Start the ⇧⌘5-style selection overlay with `mode` pre-highlighted. The
    /// crosshair is live immediately; the floating bar lets the user switch mode
    /// before dragging. On commit we capture the chosen rect for the chosen mode.
    private func presentCaptureMenu(_ mode: CaptureMode) {
        regionSelect.begin(
            preselect: mode,
            anchorRect: statusItemFrame,
            onComplete: { [weak self] chosen, cocoaRect in self?.runRegionCapture(chosen, cocoaRect) },
            onCancel: {})
    }

    /// Capture the selected rectangle for the chosen mode. Save/editor land in
    /// `PICkle bottle`; clipboard writes nothing to the bottle.
    private func runRegionCapture(_ mode: CaptureMode, _ cocoaRect: CGRect) {
        switch mode {
        case .clipboard:
            CaptureService.shared.captureRegionToClipboard(cocoaRect: cocoaRect) { _ in }
        case .save:
            CaptureService.shared.captureRegionToFile(cocoaRect: cocoaRect) { [weak self] url in
                guard let self, let url else { return }
                NotificationCenter.default.post(name: .pickleScreenshotsChanged, object: nil)
                self.flourishAfterSave(url: url, startRect: cocoaRect)
            }
        case .editor:
            CaptureService.shared.captureRegionToFile(cocoaRect: cocoaRect) { [weak self] url in
                guard let self, let url else { return }
                NotificationCenter.default.post(name: .pickleScreenshotsChanged, object: nil)
                self.editorController.open(url: url)
            }
        }
    }

    /// Save-capture flourish: the captured image shrinks from where it was
    /// captured up into the menu-bar icon, then the history popup opens.
    private func flourishAfterSave(url: URL, startRect: CGRect) {
        CaptureFlyAnimation.play(imageURL: url, startRect: startRect, anchorRect: statusItemFrame) { [weak self] in
            guard let self else { return }
            self.panelController.openIfNeeded(anchorRect: self.statusItemFrame)
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

        buildContextMenu()
    }

    /// (Re)build the status-item context menu in the current language. Called on
    /// launch and again each time the menu is about to open, so a language change
    /// in Settings is reflected the next time the menu appears.
    private func buildContextMenu() {
        contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: L("menu.openHistory"),
                                       action: #selector(openPanel), keyEquivalent: ""))
        contextMenu.addItem(NSMenuItem(title: L("menu.settings"),
                                       action: #selector(openSettings), keyEquivalent: ","))
        // Target = the updater controller; it auto-enables/disables this item via
        // canCheckForUpdates (greyed out while a check is already in flight).
        let checkForUpdatesItem = NSMenuItem(
            title: L("menu.checkForUpdates"),
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: "")
        checkForUpdatesItem.target = updaterController
        contextMenu.addItem(checkForUpdatesItem)
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: L("menu.openBottleFolder"),
                                       action: #selector(openBottleFolder), keyEquivalent: ""))
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: L("menu.quit"),
                                       action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private var statusItemFrame: NSRect? { statusItem.button?.window?.frame }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let isContextClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isContextClick {
            // Rebuild so the menu reflects the current language each time it opens.
            buildContextMenu()
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
        alert.messageText = String(format: L("alert.clearAll.message"), count)
        alert.informativeText = L("alert.clearAll.info")
        alert.addButton(withTitle: L("alert.clearAll.confirm"))
        alert.addButton(withTitle: L("common.cancel"))
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
