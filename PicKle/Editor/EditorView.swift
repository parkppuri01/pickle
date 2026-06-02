import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Screenshot editor — 0.4.0 ① pen · ② blur · ③ watermark (text + logo, each
/// independently draggable). ⌘Z undoes pen/blur in draw order.
struct EditorView: View {
    @ObservedObject var model: EditorModel
    var onClose: () -> Void

    @State private var textDragStart: CGPoint?
    @State private var logoDragStart: CGPoint?
    @State private var hoverLocation: CGPoint?   // for the blur brush/area guide
    /// Watermark font family chosen in Settings ("" = system bold).
    @AppStorage(EditorModel.fontDefaultsKey) private var watermarkFontFamily = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbarTop
            toolbarTools
            Divider()
            canvas
        }
        .frame(width: max(model.displaySize.width, 600))
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
        }
        .frame(width: model.displaySize.width, height: model.displaySize.height)
        .background(Color.black.opacity(0.04))
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
                model.textWM.center = CGPoint(x: start.x + value.translation.width,
                                              y: start.y + value.translation.height)
            }
            .onEnded { _ in textDragStart = nil }
    }

    private var logoDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                if logoDragStart == nil { logoDragStart = model.logoWM?.center }
                guard let start = logoDragStart else { return }
                model.logoWM?.center = CGPoint(x: start.x + value.translation.width,
                                               y: start.y + value.translation.height)
            }
            .onEnded { _ in logoDragStart = nil }
    }

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

    // MARK: - Toolbar (row 1: tool picker + actions)

    private var toolbarTop: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.tool) {
                Text("펜").tag(EditorModel.Tool.pen)
                Text("블러").tag(EditorModel.Tool.blur)
                Text("워터마크").tag(EditorModel.Tool.watermark)
            }
            .pickerStyle(.segmented)
            .frame(width: 230, alignment: .leading)
            .labelsHidden()

            Spacer()

            // Unified ⌘Z undo: removes the most recent pen stroke or blur region
            // in the order they were drawn, regardless of the current tool.
            Button { model.undoLast() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .help("되돌리기 (⌘Z)")
                .keyboardShortcut("z", modifiers: .command)

            Button("취소", role: .cancel) { onClose() }
            Button("저장") {
                if model.save() {
                    NotificationCenter.default.post(name: .pickleScreenshotsChanged, object: nil)
                }
                onClose()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Toolbar (row 2: tool-specific controls)

    @ViewBuilder
    private var toolbarTools: some View {
        Divider()
        Group {
            switch model.tool {
            case .pen: penControls
            case .blur: blurControls
            case .watermark: watermarkControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
            Spacer()
        }
    }

    // MARK: Watermark controls — two rows: text, then logo (independent).

    private var watermarkControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text row.
            HStack(spacing: 10) {
                Text("글자").font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                TextField("워터마크 텍스트", text: $model.textWM.text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                if !model.textWM.text.isEmpty {
                    Button(role: .destructive) { model.textWM.text = "" } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help("텍스트 지우기")
                }

                Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                Slider(value: $model.textWM.opacity, in: 0.2...1).frame(width: 70).help("글자 투명도")

                Image(systemName: "textformat.size").foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(model.textWM.scale) },
                                      set: { model.textWM.scale = CGFloat($0) }),
                       in: 0.4...3).frame(width: 70).help("글자 크기")
                Spacer()
            }

            // Logo row.
            HStack(spacing: 10) {
                Text("로고").font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                logoMenu

                if model.logoWM != nil {
                    Button(role: .destructive) { model.removeLogo() } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .help("로고 지우기")

                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { model.logoWM?.opacity ?? 0.85 },
                                          set: { model.logoWM?.opacity = $0 }),
                           in: 0.2...1).frame(width: 70).help("로고 투명도")

                    Image(systemName: "textformat.size").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(model.logoWM?.scale ?? 1) },
                                          set: { model.logoWM?.scale = CGFloat($0) }),
                           in: 0.4...3).frame(width: 70).help("로고 크기")
                }
                Spacer()
            }
        }
    }

    /// Logo picker: choose a file, or pick one of the saved presets (Settings).
    private var logoMenu: some View {
        Menu {
            Button("파일에서 선택…") { pickLogoFromFile() }
            let presets = WatermarkPresets.all()
            if !presets.isEmpty {
                Divider()
                Section("저장된 로고") {
                    ForEach(presets, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            if let img = NSImage(contentsOf: url) { model.setLogo(img) }
                        }
                    }
                }
            }
        } label: {
            Label(model.logoWM == nil ? "로고 추가…" : "로고 변경…", systemImage: "photo")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var blurControls: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.blurStyle) {
                Text("블러").tag(EditorModel.BlurStyle.gaussian)
                Text("모자이크").tag(EditorModel.BlurStyle.mosaic)
            }
            .pickerStyle(.segmented).frame(width: 130, alignment: .leading).labelsHidden()

            Picker("", selection: $model.blurApply) {
                Text("브러시").tag(EditorModel.BlurApply.brush)
                Text("영역").tag(EditorModel.BlurApply.area)
            }
            .pickerStyle(.segmented).frame(width: 120, alignment: .leading).labelsHidden()

            if model.blurApply == .brush {
                Image(systemName: "paintbrush").foregroundStyle(.secondary)
                Slider(value: $model.blurBrushWidth, in: 12...90).frame(width: 80)
                    .help("브러시 크기")
            }

            Divider().frame(height: 18)
            Image(systemName: "drop.fill").foregroundStyle(.secondary)
            Slider(value: $model.blurIntensity, in: 0...1).frame(width: 90)
                .help("블러 강도")

            Spacer()
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
