import SwiftUI
import AppKit
import KeyboardShortcuts

/// Settings window (TabView). 0.4.0 tabs:
///   - 단축키:   change the three global capture shortcuts.
///   - 워터마크: text font + saved logo presets + remember-last-text toggle.
///   - 보관:     auto-delete period + storage folder (with a Clear-all warning).
///   - 정보:     about.
struct SettingsView: View {
    var body: some View {
        TabView {
            ShortcutsSettingsTab()
                .tabItem { Label("단축키", systemImage: "command") }
            WatermarkSettingsTab()
                .tabItem { Label("워터마크", systemImage: "textformat") }
            StorageSettingsTab()
                .tabItem { Label("보관", systemImage: "tray.full") }
            AboutTab()
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 420)
    }
}

// MARK: - 단축키

private struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section("전역 단축키") {
                KeyboardShortcuts.Recorder("일반 캡처 (바로 저장)", name: .captureNormal)
                KeyboardShortcuts.Recorder("기능 캡처 (편집창 열기)", name: .captureFeature)
                KeyboardShortcuts.Recorder("클립보드 복사 (저장 안 함)", name: .captureClipboard)
            }
            Section {
                Text("단축키를 클릭하고 새 조합을 누르면 바뀝니다. ‘클립보드 복사’는 pickle bottle 폴더에 저장하지 않고 클립보드로만 복사합니다 (PizzaClip이 켜져 있으면 그쪽으로 들어갑니다).")
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
    private let previewText = "PIC.kle 가나다 AaBb 123"

    @State private var presets: [URL] = WatermarkPresets.all()

    var body: some View {
        Form {
            Section("워터마크 텍스트 폰트") {
                Picker("폰트", selection: $fontFamily) {
                    Text("시스템 기본 (굵게)").tag("")
                    Divider()
                    ForEach(families, id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }
                LabeledContent("미리보기") {
                    Text(previewText)
                        .font(fontFamily.isEmpty
                              ? .system(size: 24, weight: .bold)
                              : .custom(fontFamily, size: 24))
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle("마지막에 사용한 워터마크 텍스트 기억하기", isOn: $rememberText)
                if !fontFamily.isEmpty {
                    Button("시스템 기본 폰트로 되돌리기") { fontFamily = "" }
                }
            }

            Section("저장된 로고 (반복 사용)") {
                if presets.isEmpty {
                    Text("자주 쓰는 로고 PNG를 저장해 두면 편집기 워터마크에서 바로 고를 수 있어요.")
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
                    Label("로고 PNG 추가…", systemImage: "plus")
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
                .help("삭제")
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
        panel.message = "워터마크로 반복 사용할 로고 이미지를 고르세요."
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
            Section("자동 삭제") {
                Picker("오래된 스크린샷 자동 삭제", selection: $autoDeleteDays) {
                    ForEach(RetentionService.options, id: \.self) { days in
                        Text(days == 0 ? "사용 안 함 (영구 보관)" : "\(days)일 지나면 삭제").tag(days)
                    }
                }
                .onChange(of: autoDeleteDays) { _ in
                    NotificationCenter.default.post(name: .pickleRetentionChanged, object: nil)
                }
                Text(autoDeleteDays == 0
                     ? "스크린샷을 자동으로 지우지 않습니다. 폴더가 계속 커질 수 있어요."
                     : "\(autoDeleteDays)일이 지난 스크린샷은 휴지통으로 보냅니다. (휴지통에서 복구 가능)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("저장 위치") {
                LabeledContent("현재 폴더") {
                    Text(currentPath).font(.caption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("폴더 변경…") { changeFolder() }
                    if isCustomLocation {
                        Button("기본 위치로 되돌리기") { resetFolder() }
                    }
                }
                if isCustomLocation {
                    Label("주의: 이 폴더에는 PIC.kle가 찍지 않은 다른 이미지도 그리드에 함께 보이고, ‘모두 비우기(Clear all)’ 시 그 이미지들도 함께 휴지통으로 갑니다. 전용 폴더 사용을 권장합니다.",
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
        panel.prompt = "이 폴더 사용"
        panel.message = "스크린샷을 저장할 폴더를 고르세요. (전용 폴더를 권장합니다)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Warn before committing to a shared folder — Clear all is folder-wide.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "이 폴더를 보관함으로 사용할까요?"
        alert.informativeText = url.path
        // The key risk sentence is colored + bold via an accessory text view,
        // since NSAlert's plain informativeText can't emphasize a substring.
        alert.accessoryView = warningAccessory()
        alert.addButton(withTitle: "이 폴더 사용")
        alert.addButton(withTitle: "취소")
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
            string: "이 폴더 안의 모든 이미지가 PIC.kle 히스토리에 함께 보이고, ", attributes: normal)
        text.append(NSAttributedString(
            string: "‘모두 비우기’를 누르면 함께 휴지통으로 이동합니다.", attributes: danger))
        text.append(NSAttributedString(
            string: " 다른 파일이 섞이지 않은 전용 폴더를 권장합니다.", attributes: normal))

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

// MARK: - 정보

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("MenuBarIcon").resizable().frame(width: 48, height: 48)
            Text("PIC.kle").font(.system(size: 18, weight: .bold))
            Text("스크린샷 캡처·편집·보관 🥒").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("v0.4.0").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
