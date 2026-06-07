import SwiftUI

/// What to do with the region the user is about to capture. The capture-ready
/// bar (캡쳐레디.png) floats over the live selection overlay; the user can switch
/// mode by clicking a button, then drag on the overlay to capture.
///
/// Bar order (left→right) matches the default shortcuts:
///   clipboard = ⇧⌥A · save = ⇧⌥S · editor = ⇧⌥D
enum CaptureMode: CaseIterable {
    case clipboard   // → straight to the clipboard, NOT saved to the bottle
    case save        // → saved to the bottle folder
    case editor      // → saved, then opened in the editor

    var symbol: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .save:      return "square.and.arrow.down"
        case .editor:    return "pencil.tip.crop.circle"
        }
    }

    var labelKey: String {
        switch self {
        case .clipboard: return "capture.mode.clipboard"
        case .save:      return "capture.mode.save"
        case .editor:    return "capture.mode.editor"
        }
    }
}

/// Shared selection state between the bar view and its controller, so the
/// controller's arrow-key handling and the view's highlight stay in sync.
final class CaptureModeBarModel: ObservableObject {
    @Published var selected: CaptureMode
    init(selected: CaptureMode) { self.selected = selected }

    /// Move the highlight left (−1) / right (+1), clamped to the ends.
    func move(_ delta: Int) {
        let all = CaptureMode.allCases
        guard let i = all.firstIndex(of: selected) else { return }
        selected = all[min(max(i + delta, 0), all.count - 1)]
    }
}

/// Compact "capture-ready" bar: ✕ to cancel, then one icon button per mode with
/// the active mode highlighted. Clicking a mode just switches it (the actual
/// capture happens by dragging on the selection overlay underneath).
struct CaptureModeBar: View {
    @ObservedObject var model: CaptureModeBarModel
    @ObservedObject private var loc = LocalizationManager.shared
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            cancelButton
            ForEach(CaptureMode.allCases, id: \.self) { modeButton($0) }
        }
        .padding(7)
        .background(.regularMaterial)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.secondary))
        }
        .buttonStyle(.plain)
        .help(L("capture.mode.cancel"))
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        let selected = model.selected == mode
        return Button {
            model.selected = mode
        } label: {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? AppColors.accent.opacity(0.18) : Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(selected ? AppColors.accent : Color.secondary.opacity(0.35),
                                lineWidth: selected ? 2 : 1))
                .overlay(
                    Image(systemName: mode.symbol)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(selected ? AppColors.accent : Color.primary))
                .frame(width: 44, height: 34)
        }
        .buttonStyle(.plain)
        .help(L(mode.labelKey))
    }
}
