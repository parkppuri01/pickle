import SwiftUI
import AppKit
import KeyboardShortcuts

/// Settings window (TabView). 0.5.0 tabs (order/icons match the reference shot):
///   - 일반:     app info + language (was "정보"/About; moved to the front).
///   - 단축키:   change the three global capture shortcuts.
///   - 워터마크: text font + saved logo presets + remember-last-text toggle.
///   - 저장공간: auto-delete period + storage folder (with a Clear-all warning).
struct SettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        TabView {
            AboutTab()
                .tabItem { Label(L("settings.tab.general"), systemImage: "gearshape") }
            ShortcutsSettingsTab()
                .tabItem { Label(L("settings.tab.shortcuts"), systemImage: "keyboard") }
            WatermarkSettingsTab()
                .tabItem { Label(L("settings.tab.watermark"), systemImage: "signature") }
            StorageSettingsTab()
                .tabItem { Label(L("settings.tab.storage"), systemImage: "internaldrive") }
        }
        .frame(width: 500, height: 420)
        // Force the whole settings tree to redraw the instant the language
        // changes, so labels everywhere swap without reopening the window.
        .id(loc.language)
    }
}

// MARK: - 단축키

private struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section(L("settings.shortcuts.section")) {
                KeyboardShortcuts.Recorder(L("settings.shortcuts.normal"), name: .captureNormal)
                KeyboardShortcuts.Recorder(L("settings.shortcuts.feature"), name: .captureFeature)
                KeyboardShortcuts.Recorder(L("settings.shortcuts.clipboard"), name: .captureClipboard)
            }
            Section {
                Text(L("settings.shortcuts.note"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 워터마크

private struct WatermarkSettingsTab: View {
    @AppStorage(EditorModel.fontDefaultsKey) private var fontFamily = ""
    @AppStorage(EditorModel.rememberTextKey) private var rememberText = false
    // Loaded once; the user's installed font families, alphabetized.
    private let families = NSFontManager.shared.availableFontFamilies.sorted()
    private let previewText = L("settings.watermark.previewSample")

    @State private var presets: [URL] = WatermarkPresets.all()

    var body: some View {
        Form {
            Section(L("settings.watermark.fontSection")) {
                Picker(L("settings.watermark.font"), selection: $fontFamily) {
                    Text(L("settings.watermark.systemFont")).tag("")
                    Divider()
                    ForEach(families, id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }
                LabeledContent(L("settings.watermark.preview")) {
                    Text(previewText)
                        .font(fontFamily.isEmpty
                              ? .system(size: 24, weight: .bold)
                              : .custom(fontFamily, size: 24))
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle(L("settings.watermark.rememberText"), isOn: $rememberText)
                if !fontFamily.isEmpty {
                    Button(L("settings.watermark.resetFont")) { fontFamily = "" }
                }
            }

            Section(L("settings.watermark.logoSection")) {
                if presets.isEmpty {
                    Text(L("settings.watermark.logoEmpty"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                        ForEach(presets, id: \.self) { url in
                            logoCell(url)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    addLogo()
                } label: {
                    Label(L("settings.watermark.addLogo"), systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func logoCell(_ url: URL) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().scaledToFit()
                    } else {
                        Image(systemName: "photo").imageScale(.large).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

                Button {
                    WatermarkPresets.remove(url)
                    presets = WatermarkPresets.all()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help(L("settings.watermark.delete"))
            }
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.caption2).lineLimit(1).truncationMode(.middle)
                .frame(width: 64)
        }
    }

    private func addLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = L("settings.watermark.pickLogoMessage")
        if panel.runModal() == .OK {
            for url in panel.urls { WatermarkPresets.add(from: url) }
            presets = WatermarkPresets.all()
        }
    }
}

// MARK: - 보관 (자동삭제 + 저장 위치)

private struct StorageSettingsTab: View {
    @AppStorage(RetentionService.defaultsKey) private var autoDeleteDays = RetentionService.defaultDays
    @AppStorage(AppPaths.storageDirectoryDefaultsKey) private var customPath = ""

    /// True when the bottle points at a user-chosen folder (not the default).
    private var isCustomLocation: Bool { !customPath.isEmpty }
    private var currentPath: String {
        isCustomLocation ? (customPath as NSString).abbreviatingWithTildeInPath
                         : "~/Documents/\(AppPaths.bottleFolderName)"
    }

    var body: some View {
        Form {
            Section(L("settings.storage.autoDeleteSection")) {
                Picker(L("settings.storage.autoDeletePicker"), selection: $autoDeleteDays) {
                    ForEach(RetentionService.options, id: \.self) { days in
                        Text(days == 0 ? L("settings.storage.autoDelete.off")
                                       : String(format: L("settings.storage.autoDelete.days"), days)).tag(days)
                    }
                }
                .onChange(of: autoDeleteDays) { _ in
                    NotificationCenter.default.post(name: .pickleRetentionChanged, object: nil)
                }
                Text(autoDeleteDays == 0
                     ? L("settings.storage.autoDelete.offNote")
                     : String(format: L("settings.storage.autoDelete.onNote"), autoDeleteDays))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("settings.storage.locationSection")) {
                LabeledContent(L("settings.storage.currentFolder")) {
                    Text(currentPath).font(.caption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button(L("settings.storage.changeFolder")) { changeFolder() }
                    if isCustomLocation {
                        Button(L("settings.storage.resetFolder")) { resetFolder() }
                    }
                }
                if isCustomLocation {
                    Label(L("settings.storage.sharedWarning"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L("settings.storage.usePanelPrompt")
        panel.message = L("settings.storage.usePanelMessage")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Warn before committing to a shared folder — Clear all is folder-wide.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("settings.storage.confirmFolder.message")
        alert.informativeText = url.path
        // The key risk sentence is colored + bold via an accessory text view,
        // since NSAlert's plain informativeText can't emphasize a substring.
        alert.accessoryView = warningAccessory()
        alert.addButton(withTitle: L("settings.storage.confirmFolder.use"))
        alert.addButton(withTitle: L("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        customPath = url.path
        NotificationCenter.default.post(name: .pickleStorageLocationChanged, object: nil)
    }

    private func resetFolder() {
        customPath = ""
        NotificationCenter.default.post(name: .pickleStorageLocationChanged, object: nil)
    }

    /// Attributed warning for the change-folder alert, with the Clear-all risk
    /// sentence in bold red so it stands out from the rest.
    private func warningAccessory() -> NSView {
        let normal: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let danger: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.systemRed,
        ]
        let text = NSMutableAttributedString(
            string: L("settings.storage.warningNormal1"), attributes: normal)
        text.append(NSAttributedString(
            string: L("settings.storage.warningDanger"), attributes: danger))
        text.append(NSAttributedString(
            string: L("settings.storage.warningNormal2"), attributes: normal))

        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = text
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false
        label.frame = NSRect(x: 0, y: 0, width: 320, height: 56)
        label.preferredMaxLayoutWidth = 320
        return label
    }
}

// MARK: - 일반 (앱 정보 + 언어)

private struct AboutTab: View {
    @ObservedObject private var loc = LocalizationManager.shared

    /// App version read from Info.plist (CFBundleShortVersionString) so it always
    /// matches MARKETING_VERSION — no more hand-editing this on every release.
    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return v.isEmpty ? "" : "v\(v)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image("MenuBarIcon").resizable().frame(width: 48, height: 48)
            Text("PICkle").font(.system(size: 18, weight: .bold))
            Text(L("settings.about.tagline")).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(appVersion).font(.system(size: 11)).foregroundStyle(.tertiary)

            Divider().padding(.horizontal, 60).padding(.top, 4)

            // Runtime language switch. Changing this redraws the settings tree
            // immediately (SettingsView observes the same manager + `.id`).
            Picker(L("settings.language"), selection: $loc.language) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(L(lang.labelKey)).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
