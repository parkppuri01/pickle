import SwiftUI
import AppKit

/// The history panel content. Shows a thumbnail grid of the `PICkle bottle`
/// folder, or a friendly empty state when there's nothing yet.
struct HistoryView: View {
    @ObservedObject var vm: HistoryViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selectedID: String?

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 10)]

    var body: some View {
        ZStack {
            VisualEffectBackground()
            VStack(spacing: 0) {
                titleBar
                Divider().overlay(AppColors.separator)
                content
                Divider().overlay(AppColors.separator)
                footer
            }
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(alignment: .bottom) { toast }
        .animation(.easeInOut(duration: 0.2), value: vm.toast)
    }

    @ViewBuilder
    private var toast: some View {
        if let message = vm.toast {
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(AppColors.accent, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .padding(.bottom, 54)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image("MenuBarIcon").resizable().frame(width: 18, height: 18)
            Text(L("history.title"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !vm.screenshots.isEmpty {
                Text("\(vm.screenshots.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.inkOnAmber)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(AppColors.amberFill, in: Capsule())
            }
            lockButton
            closeButton
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Pin toggle. Unlocked = faded open padlock (default): the panel closes when
    /// you click away. Locked = solid white padlock: the panel stays open until
    /// you press ✕.
    private var lockButton: some View {
        Button { vm.isLocked.toggle() } label: {
            Image(systemName: vm.isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(vm.isLocked ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.4)))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(vm.isLocked ? L("history.lock.lockedHelp")
                          : L("history.lock.unlockedHelp"))
    }

    private var closeButton: some View {
        Button { NotificationCenter.default.post(name: .pickleCloseHistoryPanel, object: nil) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(L("history.close"))
    }

    @ViewBuilder
    private var content: some View {
        if vm.screenshots.isEmpty {
            Spacer()
            emptyState
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(vm.screenshots) { shot in
                        ThumbnailCell(
                            shot: shot,
                            isSelected: shot.id == selectedID,
                            onSelect: { selectedID = shot.id },
                            onEdit: { vm.requestEdit(shot) },
                            onCopy: { vm.copyToClipboard(shot) },
                            onDelete: { vm.delete(shot) }
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("HistoryEmptyArt")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
            Text(L("history.empty.title"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L("history.empty.hint"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            Button(L("history.clearAll")) {
                NotificationCenter.default.post(name: .pickleClearAll, object: nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(vm.screenshots.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(AppColors.accent))
            .disabled(vm.screenshots.isEmpty)
            Spacer()
            Button(L("history.settings")) {
                NotificationCenter.default.post(name: .pickleOpenSettings, object: nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.accent)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// A single screenshot thumbnail. Double-click opens the editor, single-click
/// selects, the 🍕 button (hover) copies to the clipboard, and it's draggable
/// out to any app as a real file.
private struct ThumbnailCell: View {
    let shot: Screenshot
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var image: NSImage?
    @State private var copyFlash = false

    var body: some View {
        VStack(spacing: 4) {
            thumbnail
                // Delete (top-right) and copy (bottom-right) appear on hover.
                .overlay(alignment: .topTrailing) {
                    if hovering { deleteButton.padding(4) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if hovering { copyButton.padding(4) }
                }
            Text(shot.date, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        // Double-click opens the editor; single-click selects; the 🍕 button copies.
        .onTapGesture(count: 2) { onEdit() }
        .onTapGesture(count: 1) { onSelect() }
        .help(L("history.thumb.help"))
        // Key on date too so an edit (new mtime) reloads the thumbnail even
        // though the path (cell identity) is unchanged.
        .task(id: "\(shot.id)|\(shot.date.timeIntervalSince1970)") {
            image = await ThumbnailLoader.thumbnail(for: shot.url)
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help(L("history.thumb.delete"))
    }

    /// 🍕 copy button — copies to the clipboard (PizzaClip catches it if running),
    /// with the pickle-green focus flash. Pizza emoji nods to the sibling app.
    private var copyButton: some View {
        Button {
            onCopy()
            copyFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { copyFlash = false }
        } label: {
            Text("🍕")
                .font(.system(size: 11))
                .padding(5)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help(L("history.thumb.copy"))
    }

    private var thumbnail: some View {
        ZStack {
            // 1:1 square tile. A subtle dark backing makes the letterboxed edges
            // (when the capture isn't square) look intentional.
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(Color.black.opacity(0.12))
            if let image {
                // .scaledToFit → the WHOLE capture is visible inside the square,
                // never cropped.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .stroke(AppColors.separator, lineWidth: 0.5)
        )
        // Single-click selection: calm persistent pickle-green border.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .stroke(AppColors.accent.opacity(isSelected ? 0.85 : 0), lineWidth: isSelected ? 2 : 0)
        )
        // Double-click copy: brighter ring + glow + slight pop.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .stroke(AppColors.accent, lineWidth: copyFlash ? 3.5 : 0)
        )
        .shadow(color: AppColors.accent.opacity(copyFlash ? 0.55 : 0), radius: 6)
        .scaleEffect(copyFlash ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.25), value: copyFlash)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

/// Translucent HUD material behind the panel (matches pizzaClip's popup feel).
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
