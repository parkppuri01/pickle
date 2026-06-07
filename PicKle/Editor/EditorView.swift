import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Screenshot editor — 0.4.0 ① pen · ② blur · ③ watermark (text + logo, each
/// independently draggable). ⌘Z undoes pen/blur in draw order.
struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var loc = LocalizationManager.shared
    var onClose: () -> Void

    @State private var textDragStart: CGPoint?
    @State private var logoDragStart: CGPoint?
    @State private var hoverLocation: CGPoint?   // for the blur brush/area guide
    @State private var snapGuideV: CGFloat?      // x of the vertical guide line while snapping
    @State private var snapGuideH: CGFloat?      // y of the horizontal guide line while snapping
    /// Watermark font family chosen in Settings ("" = system bold).
    @AppStorage(EditorModel.fontDefaultsKey) private var watermarkFontFamily = ""

    var body: some View {
        HStack(spacing: 0) {
            toolRail
            VStack(spacing: 0) {
                topBar
                Divider().opacity(0.15)
                canvasArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.windowBG)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Layout / palette tokens (editor-local, dark theme)

    private enum Layout {
        static let railWidth: CGFloat = 56
        static let canvasPadding: CGFloat = 24
    }
    private enum Palette {
        static let windowBG = Color(red: 0.13, green: 0.13, blue: 0.14)
        static let canvasBG = Color(red: 0.075, green: 0.075, blue: 0.085)
        static let railBG = Color(red: 0.10, green: 0.10, blue: 0.11)
        static let icon = Color.white.opacity(0.85)
        static let iconDim = Color.white.opacity(0.28)
    }

    // MARK: - Canvas

    private var canvas: some View {
        ZStack {
            Image(nsImage: model.baseImage)
                .resizable()
                .frame(width: model.displaySize.width, height: model.displaySize.height)

            Canvas { ctx, _ in
                // Blur sits under the pen strokes (it affects the base content).
                for region in model.blurRegions { drawBlur(region.kind, style: region.style, in: ctx) }
                if let pts = model.currentBlurStroke {
                    drawBlur(.stroke(points: pts, width: model.blurBrushWidth), style: model.blurStyle, in: ctx)
                }
                if let r = model.currentBlurRect {
                    drawBlur(.rect(r), style: model.blurStyle, in: ctx)
                }
                for stroke in model.strokes { draw(stroke, in: ctx) }
                if let current = model.current { draw(current, in: ctx) }

                // Pre-draw guides (like the capture region guide): show WHERE the
                // brush/area will apply, before and while you draw.
                if model.tool == .blur {
                    switch model.blurApply {
                    case .brush:
                        // Dashed circle = brush footprint, follows the cursor (or
                        // the live drag point while painting).
                        if let p = model.currentBlurStroke?.last ?? hoverLocation {
                            let d = model.blurBrushWidth
                            let circle = Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
                            strokeGuide(circle, in: ctx, emphasized: true)
                        }
                    case .area:
                        if let r = model.currentBlurRect {
                            // Dragging → dashed selection rectangle.
                            strokeGuide(Path(roundedRect: r, cornerRadius: 2), in: ctx, emphasized: true)
                        } else if let p = hoverLocation {
                            // Hovering (before drag) → crosshair guide lines.
                            var v = Path(); v.move(to: CGPoint(x: p.x, y: 0)); v.addLine(to: CGPoint(x: p.x, y: model.displaySize.height))
                            var h = Path(); h.move(to: CGPoint(x: 0, y: p.y)); h.addLine(to: CGPoint(x: model.displaySize.width, y: p.y))
                            strokeGuide(v, in: ctx, emphasized: false)
                            strokeGuide(h, in: ctx, emphasized: false)
                        }
                    }
                }

                // Watermark snap guides: the edge/center line the dragged
                // watermark is currently snapping to (set by applySnap).
                if let vx = snapGuideV {
                    var v = Path(); v.move(to: CGPoint(x: vx, y: 0)); v.addLine(to: CGPoint(x: vx, y: model.displaySize.height))
                    strokeGuide(v, in: ctx, emphasized: true)
                }
                if let hy = snapGuideH {
                    var h = Path(); h.move(to: CGPoint(x: 0, y: hy)); h.addLine(to: CGPoint(x: model.displaySize.width, y: hy))
                    strokeGuide(h, in: ctx, emphasized: true)
                }
            }
            .frame(width: model.displaySize.width, height: model.displaySize.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        switch model.tool {
                        case .pen:
                            if model.current == nil { model.begin(at: value.location) }
                            else { model.extend(to: value.location) }
                        case .blur:
                            if model.blurApply == .brush { model.extendBlurBrush(to: value.location) }
                            else { model.updateBlurRect(from: value.startLocation, to: value.location) }
                        case .watermark:
                            break   // handled by each watermark overlay's own drag
                        }
                    }
                    .onEnded { _ in
                        switch model.tool {
                        case .pen: model.commit()
                        case .blur: model.commitBlur()
                        case .watermark: break
                        }
                    }
            )
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let loc): hoverLocation = loc
                case .ended: hoverLocation = nil
                }
            }

            // Logo sits under the text (matches the save pipeline order).
            logoOverlay
            textOverlay

            // Easter egg: 🥒 confetti when the watermark text is exactly
            // "pickle"/"피클". Sits on top of everything but ignores hits so the
            // canvas stays interactive while pickles fly.
            PickleBurst(trigger: model.pickleBurstID)
                .frame(width: model.displaySize.width, height: model.displaySize.height)
                .allowsHitTesting(false)
        }
        .frame(width: model.displaySize.width, height: model.displaySize.height)
        .background(Color.black.opacity(0.04))
        .clipped()   // keep flying pickles inside the canvas
        // Fire the burst the moment the text becomes exactly a trigger word.
        .onChange(of: model.textWM.text) { newValue in
            model.maybeTriggerBurst(for: newValue)
        }
    }

    @ViewBuilder
    private var textOverlay: some View {
        if model.textWM.isActive {
            let size = EditorModel.watermarkBaseFont * model.textWM.scale
            Text(model.textWM.text)
                .font(watermarkFontFamily.isEmpty
                      ? .system(size: size, weight: .bold)
                      : .custom(watermarkFontFamily, size: size))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                .fixedSize()
                .opacity(model.textWM.opacity)
                .position(model.textWM.center)
                .allowsHitTesting(model.tool == .watermark)
                .gesture(textDrag)
        }
    }

    @ViewBuilder
    private var logoOverlay: some View {
        if let logo = model.logoWM {
            Image(nsImage: logo.image)
                .resizable()
                .frame(width: model.logoDisplaySize().width, height: model.logoDisplaySize().height)
                .opacity(logo.opacity)
                .position(logo.center)
                .allowsHitTesting(model.tool == .watermark)
                .gesture(logoDrag)
        }
    }

    private var textDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                if textDragStart == nil { textDragStart = model.textWM.center }
                guard let start = textDragStart else { return }
                let raw = CGPoint(x: start.x + value.translation.width,
                                  y: start.y + value.translation.height)
                model.textWM.center = applySnap(to: raw)
            }
            .onEnded { _ in textDragStart = nil; clearSnapGuides() }
    }

    private var logoDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                if logoDragStart == nil { logoDragStart = model.logoWM?.center }
                guard let start = logoDragStart else { return }
                let raw = CGPoint(x: start.x + value.translation.width,
                                  y: start.y + value.translation.height)
                model.logoWM?.center = applySnap(to: raw)
            }
            .onEnded { _ in logoDragStart = nil; clearSnapGuides() }
    }

    // MARK: - Watermark snapping (magnetic alignment guides)

    /// Snap a dragged watermark center to the nearest of the 9 anchor points —
    /// the three x's {inset, middle, width−inset} × three y's {inset, middle,
    /// height−inset} (corners, edge-midpoints, center). Each axis snaps
    /// independently: if the center is within `threshold` of an anchor's x (or y),
    /// that coordinate snaps and the matching guide line is shown. Coordinates are
    /// in displaySize space, matching `textWM.center` / `logoWM.center`.
    private func applySnap(to center: CGPoint) -> CGPoint {
        let inset: CGFloat = 24
        let threshold: CGFloat = 12
        let w = model.displaySize.width, h = model.displaySize.height
        let xs: [CGFloat] = [inset, w / 2, w - inset]
        let ys: [CGFloat] = [inset, h / 2, h - inset]

        var cx = center.x, cy = center.y
        var gv: CGFloat? = nil, gh: CGFloat? = nil
        if let nx = xs.min(by: { abs($0 - center.x) < abs($1 - center.x) }),
           abs(nx - center.x) <= threshold { cx = nx; gv = nx }
        if let ny = ys.min(by: { abs($0 - center.y) < abs($1 - center.y) }),
           abs(ny - center.y) <= threshold { cy = ny; gh = ny }
        snapGuideV = gv
        snapGuideH = gh
        return CGPoint(x: cx, y: cy)
    }

    private func clearSnapGuides() { snapGuideV = nil; snapGuideH = nil }

    /// Reveal the blurred/pixellated image only inside a region's shape.
    private func drawBlur(_ kind: BlurRegion.Kind, style: EditorModel.BlurStyle, in ctx: GraphicsContext) {
        guard let proc = model.processed(style) else { return }
        let clip = blurPath(kind)
        ctx.drawLayer { layer in
            layer.clip(to: clip)
            layer.draw(Image(nsImage: proc),
                       in: CGRect(origin: .zero, size: model.displaySize))
        }
    }

    /// Dashed outline so the user can see the blur region clearly. Two passes
    /// (dark underlay + pickle-green dashes) keep it visible over any image.
    private func strokeGuide(_ path: Path, in ctx: GraphicsContext, emphasized: Bool) {
        let dash: [CGFloat] = [6, 4]
        ctx.stroke(path, with: .color(.black.opacity(emphasized ? 0.55 : 0.35)),
                   style: StrokeStyle(lineWidth: emphasized ? 2.5 : 2, dash: dash))
        ctx.stroke(path, with: .color(AppColors.accent.opacity(emphasized ? 1 : 0.75)),
                   style: StrokeStyle(lineWidth: emphasized ? 1.5 : 1, dash: dash))
    }

    private func blurPath(_ kind: BlurRegion.Kind) -> Path {
        switch kind {
        case .rect(let r):
            return Path(roundedRect: r, cornerRadius: 2)
        case .stroke(let pts, let width):
            var p = Path()
            guard let first = pts.first else { return p }
            p.move(to: first)
            for q in pts.dropFirst() { p.addLine(to: q) }
            return p.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }

    private func draw(_ stroke: PenStroke, in ctx: GraphicsContext) {
        guard let first = stroke.points.first else { return }
        var path = Path()
        path.move(to: first)
        for p in stroke.points.dropFirst() { path.addLine(to: p) }
        ctx.stroke(
            path,
            with: .color(Color(hex: Int(stroke.colorHex))),
            style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
        )
    }

    // MARK: - Left tool rail (vertical icons)

    private var toolRail: some View {
        VStack(spacing: 8) {
            railTool(.pen, system: "pencil.tip")
            railTool(.blur, system: "drop.fill")
            railTool(.watermark, system: "textformat")
            Spacer()
            // Unified ⌘Z undo: removes the most recent pen stroke or blur region
            // in the order they were drawn, regardless of the current tool.
            railIcon(system: "arrow.uturn.backward", enabled: model.canUndo,
                     help: L("editor.undo.help")) { model.undoLast() }
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.vertical, 12)
        .frame(width: Layout.railWidth)
        .frame(maxHeight: .infinity)
        .background(Palette.railBG)
        .noFocusRing()   // no blue keyboard-focus ring on the first tool button
    }

    /// A tool selector in the rail — filled with the accent when active.
    private func railTool(_ tool: EditorModel.Tool, system: String) -> some View {
        let selected = model.tool == tool
        return Button { model.tool = tool } label: {
            Image(systemName: system)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(selected ? Color.black.opacity(0.85) : Palette.icon)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? AppColors.accent : Color.clear))
                .contentShape(Rectangle())   // whole 40×40 box is clickable, not just the glyph
        }
        .buttonStyle(.plain)
        .help(toolHelp(tool))
    }

    /// A plain action icon in the rail (e.g. undo).
    private func railIcon(system: String, enabled: Bool, help: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(enabled ? Palette.icon : Palette.iconDim)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())   // whole 40×40 box is clickable, not just the glyph
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private func toolHelp(_ tool: EditorModel.Tool) -> String {
        switch tool {
        case .pen: return L("editor.tool.pen")
        case .blur: return L("editor.tool.blur")
        case .watermark: return L("editor.tool.watermark")
        }
    }

    // MARK: - Top bar (selected tool's options + Cancel / Save)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                switch model.tool {
                case .pen: penControls
                case .blur: blurControls
                case .watermark: watermarkControls
                }
            }
            Spacer(minLength: 8)
            imageInfoBadge
            Button(L("editor.cancel"), role: .cancel) { onClose() }
            Button(L("editor.save")) {
                if model.save() {
                    NotificationCenter.default.post(name: .pickleScreenshotsChanged, object: nil)
                }
                onClose()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    /// Top-right info: original pixel size · file size · extension.
    private var imageInfoBadge: some View {
        let px = model.imagePixelSize
        let ext = model.fileURL.pathExtension.uppercased()
        let bytes = model.originalByteCount
        return VStack(alignment: .trailing, spacing: 1) {
            Text("\(Int(px.width)) × \(Int(px.height)) px")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) · \(ext)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    // MARK: - Canvas area (dark backdrop, image centered, auto-scaled to fit)

    /// The canvas is authored at `model.displaySize` (fixed editing coordinates),
    /// then scaled with `.scaleEffect` to fit the available area. scaleEffect is a
    /// render/hit-test transform, so the pen/blur gesture coordinates inside
    /// `canvas` stay in displaySize units — no coordinate math changes needed.
    private var canvasArea: some View {
        GeometryReader { geo in
            let availW = max(geo.size.width - Layout.canvasPadding * 2, 1)
            let availH = max(geo.size.height - Layout.canvasPadding * 2, 1)
            let s = max(min(availW / model.displaySize.width,
                            availH / model.displaySize.height, 1), 0.05)
            ZStack {
                CheckerboardBackground()
                canvas
                    .scaleEffect(s)
                    .frame(width: model.displaySize.width * s,
                           height: model.displaySize.height * s)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 14, y: 5)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var penControls: some View {
        HStack(spacing: 10) {
            ForEach(EditorModel.palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: Int(hex)))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(
                            Color.primary.opacity(model.colorHex == hex ? 0.9 : 0.25),
                            lineWidth: model.colorHex == hex ? 2.5 : 1)
                    )
                    .onTapGesture { model.colorHex = hex }
            }
            Divider().frame(height: 20)
            ForEach(EditorModel.widths, id: \.self) { w in
                Circle()
                    .fill(Color.primary.opacity(model.lineWidth == w ? 0.9 : 0.3))
                    .frame(width: w + 8, height: w + 8)
                    .onTapGesture { model.lineWidth = w }
            }
        }
    }

    // MARK: Watermark controls — two rows: text, then logo (independent).

    private var watermarkControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text row.
            HStack(spacing: 10) {
                Text(L("editor.text.label")).font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                TextField(L("editor.text.placeholder"), text: $model.textWM.text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                if !model.textWM.text.isEmpty {
                    Button(role: .destructive) { model.textWM.text = "" } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help(L("editor.text.clear.help"))
                }

                Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                Slider(value: $model.textWM.opacity, in: 0.2...1).frame(width: 70).help(L("editor.text.opacity.help"))

                Image(systemName: "textformat.size").foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(model.textWM.scale) },
                                      set: { model.textWM.scale = CGFloat($0) }),
                       in: 0.2...6).frame(width: 70).help(L("editor.text.size.help"))
            }

            // Logo row.
            HStack(spacing: 10) {
                Text(L("editor.logo.label")).font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                logoMenu

                if model.logoWM != nil {
                    Button(role: .destructive) { model.removeLogo() } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .help(L("editor.logo.clear.help"))

                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { model.logoWM?.opacity ?? 0.85 },
                                          set: { model.logoWM?.opacity = $0 }),
                           in: 0.2...1).frame(width: 70).help(L("editor.logo.opacity.help"))

                    Image(systemName: "textformat.size").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(model.logoWM?.scale ?? 1) },
                                          set: { model.logoWM?.scale = CGFloat($0) }),
                           in: 0.2...6).frame(width: 70).help(L("editor.logo.size.help"))
                }
            }
        }
    }

    /// Logo picker: choose a file, or pick one of the saved presets (Settings).
    private var logoMenu: some View {
        Menu {
            Button(L("editor.logo.pickFile")) { pickLogoFromFile() }
            let presets = WatermarkPresets.all()
            if !presets.isEmpty {
                Divider()
                Section(L("editor.logo.savedSection")) {
                    ForEach(presets, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            if let img = NSImage(contentsOf: url) { model.setLogo(img) }
                        }
                    }
                }
            }
        } label: {
            Label(model.logoWM == nil ? L("editor.logo.add") : L("editor.logo.change"), systemImage: "photo")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var blurControls: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.blurStyle) {
                Text(L("editor.blur.gaussian")).tag(EditorModel.BlurStyle.gaussian)
                Text(L("editor.blur.mosaic")).tag(EditorModel.BlurStyle.mosaic)
            }
            .pickerStyle(.segmented).frame(width: 130, alignment: .leading).labelsHidden()

            Picker("", selection: $model.blurApply) {
                Text(L("editor.blur.brush")).tag(EditorModel.BlurApply.brush)
                Text(L("editor.blur.area")).tag(EditorModel.BlurApply.area)
            }
            .pickerStyle(.segmented).frame(width: 120, alignment: .leading).labelsHidden()

            if model.blurApply == .brush {
                Image(systemName: "paintbrush").foregroundStyle(.secondary)
                Slider(value: $model.blurBrushWidth, in: 12...90).frame(width: 80)
                    .help(L("editor.blur.brushSize.help"))
            }

            Divider().frame(height: 18)
            Image(systemName: "drop.fill").foregroundStyle(.secondary)
            Slider(value: $model.blurIntensity, in: 0...1).frame(width: 90)
                .help(L("editor.blur.intensity.help"))
        }
    }

    private func pickLogoFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            model.setLogo(img)
        }
    }
}

private extension View {
    /// Remove SwiftUI's blue keyboard-focus ring (macOS 14+; no-op on 13).
    @ViewBuilder func noFocusRing() -> some View {
        if #available(macOS 14.0, *) { focusEffectDisabled() } else { self }
    }
}

/// A dark checkerboard drawn behind the editor image so a fully-black (or fully
/// white) screenshot stays visually distinct from the canvas backdrop
/// (matches guide/편집팝업예시.png).
struct CheckerboardBackground: View {
    var tile: CGFloat = 14
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.16)))
            let cols = Int((size.width / tile).rounded(.up))
            let rows = Int((size.height / tile).rounded(.up))
            guard cols > 0, rows > 0 else { return }
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * tile, y: CGFloat(r) * tile,
                                         width: tile, height: tile)),
                             with: .color(Color(white: 0.22)))
                }
            }
        }
    }
}
