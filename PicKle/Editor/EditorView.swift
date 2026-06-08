import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Reports the canvas's live fit-scale (set in canvasArea's GeometryReader) up to
/// the view, so the crop handles can stay a constant on-screen size no matter how
/// far the canvas is scaled down to fit the window.
private struct CanvasScaleKey: PreferenceKey {
    static let defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A crop-box handle the user can drag: 4 corners, 4 edge midpoints, or the whole
/// box (move). Drives the crop-rect math in `applyCropDrag`.
private enum CropHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case move
}

/// A small left-pointing triangle: the floating option popover's tail, aimed at
/// the active tool icon in the rail.
private struct PopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Screenshot editor — 0.5.0 ① pen · ② blur · ③ watermark. Options for the
/// selected tool float in a popover by its rail icon (design "B"); the text
/// watermark is typed directly on the canvas. ⌘Z undoes pen/blur in draw order.
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
    /// The canvas's live fit-scale (displaySize → on-screen), reported up from the
    /// canvas GeometryReader. Keeps the crop handles a constant on-screen size no
    /// matter how far the canvas is scaled down.
    @State private var canvasScale: CGFloat = 1
    /// The floating tool-option popover shows on tool select and fades out ~2s
    /// after the pointer leaves it, so it stops covering the canvas.
    @State private var popoverVisible = true
    @State private var popoverHideTask: DispatchWorkItem?
    /// Crop tool: the kept-region rectangle, in display-space (top-left origin).
    /// nil = crop tool not active yet; it's seeded to the full image on entry.
    @State private var cropRect: CGRect?
    /// Which crop handle (corner/edge/move) the current drag grabbed, plus the
    /// crop rect captured at drag start — each frame is computed from that start,
    /// not accumulated, so resizing stays stable.
    @State private var cropDragHandle: CropHandle?
    @State private var cropDragStartRect: CGRect?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.15)
            HStack(spacing: 0) {
                toolRail
                canvasArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.windowBG)
        // The selected tool's options float next to its rail icon (design "B").
        // Crop is the exception — it has no popover; its control is the on-canvas
        // Crop button that appears once the box is changed.
        .overlay(alignment: .topLeading) { if model.tool != .crop { optionsPopover } }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Layout / palette tokens (editor-local, dark theme)

    private enum Layout {
        static let railWidth: CGFloat = 56
        static let canvasPadding: CGFloat = 24
        static let topBarHeight: CGFloat = 54
        static let railTopInset: CGFloat = 12     // the rail's own top padding
        static let toolSlot: CGFloat = 48         // one tool = 40pt icon + 8pt gap
    }
    private enum Palette {
        static let windowBG = Color(red: 0.13, green: 0.13, blue: 0.14)
        static let canvasBG = Color(red: 0.075, green: 0.075, blue: 0.085)
        static let railBG = Color(red: 0.10, green: 0.10, blue: 0.11)
        static let popoverBG = Color(red: 0.17, green: 0.17, blue: 0.19)
        static let icon = Color.white.opacity(0.85)
        static let iconDim = Color.white.opacity(0.40)
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

                // Crop tool: dim everything outside the kept rect, with a thirds
                // grid + bright border inside; a crosshair guide before dragging.
                if model.tool == .crop { drawCropOverlay(in: ctx) }
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
                        case .crop:
                            // Resize/move the existing crop box by whichever handle
                            // the drag started on (corner, edge, or inside = move).
                            if cropDragHandle == nil {
                                let r = cropRect ?? CGRect(origin: .zero, size: model.displaySize)
                                cropDragStartRect = r
                                cropDragHandle = cropHandle(at: value.startLocation, in: r) ?? .move
                            }
                            if let h = cropDragHandle, let start = cropDragStartRect {
                                cropRect = applyCropDrag(h, startRect: start,
                                                         dx: value.translation.width,
                                                         dy: value.translation.height)
                            }
                        }
                    }
                    .onEnded { _ in
                        switch model.tool {
                        case .pen: model.commit()
                        case .blur: model.commitBlur()
                        case .watermark: break
                        case .crop: cropDragHandle = nil; cropDragStartRect = nil
                        }
                    }
            )
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let loc):
                    hoverLocation = loc
                    if model.tool == .crop { updateCropCursor(at: loc) }
                case .ended:
                    hoverLocation = nil
                    if model.tool == .crop { NSCursor.arrow.set() }
                }
            }

            // While typing the watermark, a tap anywhere else on the canvas
            // commits the text — focus-loss alone is unreliable over the canvas.
            if model.isEditingText {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: model.displaySize.width, height: model.displaySize.height)
                    .onTapGesture { endTextEditing() }
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
        // Switching away from the watermark tool ends any text editing; leaving
        // the crop tool drops the pending (un-applied) crop selection.
        .onChange(of: model.tool) { newTool in
            if newTool != .watermark { endTextEditing() }
            if newTool != .crop { cropRect = nil }
        }
    }

    @ViewBuilder
    private var textOverlay: some View {
        let size = EditorModel.watermarkBaseFont * model.textWM.scale
        let wmFont: Font = watermarkFontFamily.isEmpty
            ? .system(size: size, weight: .bold)
            : .custom(watermarkFontFamily, size: size)
        let kern = model.textWM.tracking * model.textWM.scale     // 자간
        let lineGap = model.textWM.lineSpacing * model.textWM.scale // 줄간격
        if model.isEditingText {
            // Type the watermark straight on the canvas via an AppKit NSTextView
            // (SwiftUI's TextField submits on Return and won't grow sideways). It
            // self-sizes to the text via sizeThatFits — real newlines, sideways
            // growth, a stable caret, and solid Korean IME.
            let editFont = EditorModel.watermarkNSFont(size: size)
            CanvasTextEditor(text: $model.textWM.text, font: editFont, kern: kern,
                             lineSpacing: lineGap, alignment: model.textWM.alignment,
                             onCommit: endTextEditing)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.32))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(AppColors.accent.opacity(0.9), lineWidth: 1.5))
                )
                .position(model.textWM.center)
        } else if model.textWM.isActive {
            Text(model.textWM.text)
                .font(wmFont)
                .kerning(kern)
                .lineSpacing(lineGap)
                .multilineTextAlignment(model.textWM.alignment.swiftUITextAlignment)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                .fixedSize()
                .opacity(model.textWM.opacity)
                .position(model.textWM.center)
                .allowsHitTesting(model.tool == .watermark)
                .onTapGesture(count: 2) { beginTextEditing() }   // double-click to edit
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
                model.textWM.center = applySnap(to: raw, size: textWatermarkDisplaySize)
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
                model.logoWM?.center = applySnap(to: raw, size: model.logoDisplaySize())
            }
            .onEnded { _ in logoDragStart = nil; clearSnapGuides() }
    }

    // MARK: - Watermark snapping (magnetic alignment guides)

    /// The text watermark's current display-space bounding size (for snapping).
    private var textWatermarkDisplaySize: CGSize {
        let s = EditorModel.watermarkBaseFont * model.textWM.scale
        return CanvasTextEditor.measure(model.textWM.text,
                                        font: EditorModel.watermarkNSFont(size: s),
                                        kern: model.textWM.tracking * model.textWM.scale,
                                        lineSpacing: model.textWM.lineSpacing * model.textWM.scale)
    }

    /// Snap a dragged watermark to the 3×3 margin grid. Edge targets snap by the
    /// item's OWN edge — left edge → left margin, right edge → right margin, top →
    /// top, bottom → bottom — so the guide line marks where that side lands (not
    /// the centre); the centre target still snaps the centre. Each axis snaps
    /// independently. `size` is the dragged item's display-space size; coordinates
    /// are in displaySize space, matching `textWM.center` / `logoWM.center`.
    private func applySnap(to center: CGPoint, size: CGSize) -> CGPoint {
        let inset: CGFloat = 24
        let threshold: CGFloat = 12
        let w = model.displaySize.width, h = model.displaySize.height
        let halfW = size.width / 2, halfH = size.height / 2
        // (snapped center, guide-line position) per axis target.
        let xTargets: [(c: CGFloat, guide: CGFloat)] = [
            (inset + halfW, inset),          // left edge → left margin
            (w / 2, w / 2),                  // centre
            (w - inset - halfW, w - inset),  // right edge → right margin
        ]
        let yTargets: [(c: CGFloat, guide: CGFloat)] = [
            (inset + halfH, inset),          // top edge → top margin
            (h / 2, h / 2),                  // middle
            (h - inset - halfH, h - inset),  // bottom edge → bottom margin
        ]
        var cx = center.x, cy = center.y
        var gv: CGFloat? = nil, gh: CGFloat? = nil
        if let best = xTargets.min(by: { abs($0.c - center.x) < abs($1.c - center.x) }),
           abs(best.c - center.x) <= threshold { cx = best.c; gv = best.guide }
        if let best = yTargets.min(by: { abs($0.c - center.y) < abs($1.c - center.y) }),
           abs(best.c - center.y) <= threshold { cy = best.c; gh = best.guide }
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

    /// Draw the crop tool's overlay: dim outside the kept rect, a rule-of-thirds
    /// grid + thin border inside, and grab handles (corner L-shapes + edge bars)
    /// like the macOS crop UI. Handle/line sizes are divided by `canvasScale` so
    /// they stay a constant size on screen no matter how scaled-down the canvas is.
    private func drawCropOverlay(in ctx: GraphicsContext) {
        guard let r = cropRect, r.width > 1, r.height > 1 else { return }
        let full = CGRect(origin: .zero, size: model.displaySize)
        let s = max(canvasScale, 0.05)
        // Dim outside: fill the whole canvas, punch out the kept rect (even-odd).
        var outside = Path(full)
        outside.addPath(Path(r))
        ctx.fill(outside, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        // Rule-of-thirds grid inside the kept rect.
        var grid = Path()
        for i in 1...2 {
            let x = r.minX + r.width * CGFloat(i) / 3
            grid.move(to: CGPoint(x: x, y: r.minY)); grid.addLine(to: CGPoint(x: x, y: r.maxY))
            let y = r.minY + r.height * CGFloat(i) / 3
            grid.move(to: CGPoint(x: r.minX, y: y)); grid.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.3)), lineWidth: 0.5 / s)
        ctx.stroke(Path(r), with: .color(.white.opacity(0.9)), lineWidth: 1 / s)
        drawCropHandles(r, scale: s, in: ctx)
    }

    /// Corner L-handles + edge mid-bars, in solid white. Sizes are in on-screen
    /// points via `1/scale`, so handles look the same regardless of canvas zoom.
    private func drawCropHandles(_ r: CGRect, scale s: CGFloat, in ctx: GraphicsContext) {
        let len: CGFloat = 16 / s      // corner arm length
        let bar: CGFloat = 22 / s      // edge handle length
        let th: CGFloat  = 3 / s       // thickness
        let o = th / 2                 // center the handle on the border line
        let white = GraphicsContext.Shading.color(.white)
        func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: white)
        }
        // Corners (two arms each).
        fill(r.minX - o, r.minY - o, len, th); fill(r.minX - o, r.minY - o, th, len)            // TL
        fill(r.maxX + o - len, r.minY - o, len, th); fill(r.maxX - o, r.minY - o, th, len)      // TR
        fill(r.minX - o, r.maxY - o, len, th); fill(r.minX - o, r.maxY + o - len, th, len)      // BL
        fill(r.maxX + o - len, r.maxY - o, len, th); fill(r.maxX - o, r.maxY + o - len, th, len) // BR
        // Edge midpoints.
        fill(r.midX - bar / 2, r.minY - o, bar, th)   // top
        fill(r.midX - bar / 2, r.maxY - o, bar, th)   // bottom
        fill(r.minX - o, r.midY - bar / 2, th, bar)   // left
        fill(r.maxX - o, r.midY - bar / 2, th, bar)   // right
    }

    /// Which handle the point is on, in display-space. Tolerance is in on-screen
    /// points (÷ canvasScale) so handles stay easy to grab at any canvas zoom.
    private func cropHandle(at p: CGPoint, in r: CGRect) -> CropHandle? {
        let tol = 18 / max(canvasScale, 0.05)
        let nearL = abs(p.x - r.minX) <= tol, nearR = abs(p.x - r.maxX) <= tol
        let nearT = abs(p.y - r.minY) <= tol, nearB = abs(p.y - r.maxY) <= tol
        let spanX = p.x >= r.minX - tol && p.x <= r.maxX + tol
        let spanY = p.y >= r.minY - tol && p.y <= r.maxY + tol
        if nearL && nearT { return .topLeft }
        if nearR && nearT { return .topRight }
        if nearL && nearB { return .bottomLeft }
        if nearR && nearB { return .bottomRight }
        if nearT && spanX { return .top }
        if nearB && spanX { return .bottom }
        if nearL && spanY { return .left }
        if nearR && spanY { return .right }
        if r.contains(p) { return .move }
        return nil
    }

    /// Show a resize/move cursor while hovering a crop handle (or the box interior),
    /// so it reads like a normal crop UI. Reverts to the arrow off the box.
    private func updateCropCursor(at p: CGPoint) {
        guard let r = cropRect, let h = cropHandle(at: p, in: r) else { NSCursor.arrow.set(); return }
        switch h {
        case .left, .right:          NSCursor.resizeLeftRight.set()
        case .top, .bottom:          NSCursor.resizeUpDown.set()
        case .topLeft, .bottomRight: NSCursor.resizeNWSE.set()
        case .topRight, .bottomLeft: NSCursor.resizeNESW.set()
        case .move:                  NSCursor.openHand.set()
        }
    }

    /// New crop rect from a handle drag: corners/edges move the matching sides,
    /// `.move` slides the whole box. Clamped to the canvas with a minimum size.
    private func applyCropDrag(_ h: CropHandle, startRect r: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        let bounds = CGRect(origin: .zero, size: model.displaySize)
        let minSize: CGFloat = 24
        if h == .move {
            var nr = r.offsetBy(dx: dx, dy: dy)
            nr.origin.x = min(max(0, nr.origin.x), bounds.width - nr.width)
            nr.origin.y = min(max(0, nr.origin.y), bounds.height - nr.height)
            return nr
        }
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch h {
        case .topLeft:     minX += dx; minY += dy
        case .topRight:    maxX += dx; minY += dy
        case .bottomLeft:  minX += dx; maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        case .top:         minY += dy
        case .bottom:      maxY += dy
        case .left:        minX += dx
        case .right:       maxX += dx
        case .move:        break
        }
        // Clamp to the canvas.
        minX = max(0, minX); minY = max(0, minY)
        maxX = min(bounds.width, maxX); maxY = min(bounds.height, maxY)
        // Keep a minimum size: push the dragged edge back, opposite edge stays put.
        let movesLeft = (h == .topLeft || h == .bottomLeft || h == .left)
        let movesTop  = (h == .topLeft || h == .topRight || h == .top)
        if maxX - minX < minSize { if movesLeft { minX = maxX - minSize } else { maxX = minX + minSize } }
        if maxY - minY < minSize { if movesTop  { minY = maxY - minSize } else { maxY = minY + minSize } }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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
            railWatermarkTool()
            railTool(.crop, system: "crop")
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
        return Button { selectTool(tool) } label: {
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

    /// Watermark tool button — a tiny "water mark" text label instead of an SF
    /// Symbol (the `textformat` glyph renders localized sample letters, e.g.
    /// "가가" on Korean macOS). Selection state mirrors `railTool`.
    private func railWatermarkTool() -> some View {
        let selected = model.tool == .watermark
        return Button { selectTool(.watermark) } label: {
            VStack(spacing: 0) {
                Text("water")
                Text("mark")
            }
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(selected ? Color.black.opacity(0.85) : Palette.icon)
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AppColors.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(toolHelp(.watermark))
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
        case .crop: return L("editor.tool.crop")
        }
    }

    // MARK: - Top bar (selected tool's options + Cancel / Save)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Spacer(minLength: 8)
            imageInfoBadge
            cancelButton
            saveButton
        }
        .padding(.horizontal, 16)
        .frame(height: Layout.topBarHeight)
    }

    /// Cancel discards the edit. While typing on the canvas we drop its Esc
    /// shortcut so Esc finishes the text instead of closing the whole editor.
    @ViewBuilder
    private var cancelButton: some View {
        if model.isEditingText {
            Button(L("editor.cancel")) { onClose() }
        } else {
            Button(L("editor.cancel"), role: .cancel) { onClose() }
        }
    }

    /// Save commits the edit. No Return shortcut on purpose: the editor opens with
    /// no focused button (see EditorWindowController), so Enter can't accidentally
    /// close it — and in the crop tool Enter is reserved for applying the crop.
    private var saveButton: some View {
        Button(L("editor.save")) {
            if model.save() {
                NotificationCenter.default.post(name: .pickleScreenshotsChanged, object: nil)
            }
            onClose()
        }
    }

    // MARK: - Floating tool-option popover (anchored at the active rail icon)

    @ViewBuilder
    private var optionsPopover: some View {
        HStack(alignment: .top, spacing: 0) {
            PopoverArrow()
                .fill(Palette.popoverBG)
                .frame(width: 7, height: 13)
                .padding(.top, 16)
            VStack(alignment: .leading, spacing: 12) {
                Text(toolHelp(model.tool))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.iconDim)
                    .textCase(.uppercase)
                Group {
                    switch model.tool {
                    case .pen: penControls
                    case .blur: blurControls
                    case .watermark: watermarkControls
                    case .crop: EmptyView()   // crop has no popover (on-canvas button)
                    }
                }
            }
            .padding(13)
            .background(Palette.popoverBG, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
            // Keep it up while hovered; fade ~2s after the pointer leaves.
            .onHover { hovering in
                if hovering { keepPopover() } else { scheduleHidePopover() }
            }
        }
        .padding(.leading, Layout.railWidth - 1)
        .padding(.top, Layout.topBarHeight + 1 + Layout.railTopInset
                 + activeToolIndex * Layout.toolSlot - 2)
        .opacity(popoverVisible ? 1 : 0)
        .allowsHitTesting(popoverVisible)
        .animation(.easeOut(duration: 0.12), value: model.tool)
        .onAppear { scheduleHidePopover() }   // fade the initial popover too
    }

    private var activeToolIndex: CGFloat {
        CGFloat(EditorModel.Tool.allCases.firstIndex(of: model.tool) ?? 0)
    }

    // MARK: - On-canvas text-watermark editing

    /// Begin typing the text watermark directly on the canvas. A fresh caret
    /// lands at the default spot when there's no text yet.
    private func beginTextEditing() {
        if model.textWM.text.trimmingCharacters(in: .whitespaces).isEmpty {
            model.textWM.center = CGPoint(x: model.displaySize.width / 2,
                                          y: model.displaySize.height * 0.85)
        }
        model.tool = .watermark
        model.isEditingText = true
    }

    /// Finish editing (Esc / outside tap / focus loss / tool switch). Return
    /// inserts a newline; committing happens by clicking outside the field.
    private func endTextEditing() {
        if model.isEditingText { model.isEditingText = false }
    }

    // MARK: - Popover show / auto-hide

    /// Select a tool. Re-clicking the active tool while its popover is showing
    /// hides the popover immediately (toggle); otherwise selects + shows it.
    private func selectTool(_ tool: EditorModel.Tool) {
        if model.tool == tool && popoverVisible {
            hidePopoverNow()
        } else {
            model.tool = tool
            // Entering crop: start with a full-image box the user shrinks via handles.
            if tool == .crop && cropRect == nil {
                cropRect = CGRect(origin: .zero, size: model.displaySize)
            }
            showPopover()
        }
    }

    /// Show the popover and arm the auto-hide (used on tool select / open).
    private func showPopover() {
        popoverHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { popoverVisible = true }
        scheduleHidePopover()
    }

    /// Keep the popover up while the pointer is over it (cancels the pending hide).
    private func keepPopover() {
        popoverHideTask?.cancel(); popoverHideTask = nil
        if !popoverVisible { withAnimation(.easeOut(duration: 0.15)) { popoverVisible = true } }
    }

    /// Fade the popover out after `delay` seconds unless cancelled (re-shown).
    private func scheduleHidePopover(after delay: Double = 2) {
        popoverHideTask?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.4)) { popoverVisible = false }
        }
        popoverHideTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func hidePopoverNow() {
        popoverHideTask?.cancel(); popoverHideTask = nil
        withAnimation(.easeOut(duration: 0.2)) { popoverVisible = false }
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
            .preference(key: CanvasScaleKey.self, value: s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(CanvasScaleKey.self) { canvasScale = $0 }
        // The crop tool's only control: a Crop button floating at the canvas center.
        .overlay(alignment: .center) { cropApplyOverlay }
    }

    /// One labelled slider row, used across the vertical popover controls.
    private func sliderRow(_ icon: String, _ value: Binding<Double>,
                           _ range: ClosedRange<Double>, help: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(value: value, in: range)
        }
        .help(help)
    }

    /// One pen-colour swatch. Extracted from penControls so the LazyVGrid's
    /// closure stays simple enough for the Swift type-checker (was borderline).
    private func colorSwatch(_ hex: UInt32) -> some View {
        let selected = model.colorHex == hex
        return Circle()
            .fill(Color(hex: Int(hex)))
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.primary.opacity(selected ? 0.95 : 0.25),
                                     lineWidth: selected ? 2.5 : 1))
            .contentShape(Circle())
            .onTapGesture { model.colorHex = hex }
    }

    /// One pen line-width dot (bigger dot = thicker line).
    private func widthDot(_ w: CGFloat) -> some View {
        Circle()
            .fill(Color.primary.opacity(model.lineWidth == w ? 0.95 : 0.3))
            .frame(width: w + 10, height: w + 10)
            .contentShape(Circle())
            .onTapGesture { model.lineWidth = w }
    }

    private var penControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 8), count: 5),
                      alignment: .leading, spacing: 9) {
                ForEach(EditorModel.palette, id: \.self) { colorSwatch($0) }
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack(spacing: 14) {
                ForEach(EditorModel.widths, id: \.self) { widthDot($0) }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 176)
    }

    // MARK: Watermark controls — add/edit text on the canvas, plus logo options.

    private var watermarkControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { beginTextEditing() } label: {
                Label(model.textWM.isActive ? L("editor.text.edit") : L("editor.text.add"),
                      systemImage: model.textWM.isActive ? "pencil" : "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)

            if model.textWM.isActive {
                Picker("", selection: $model.textWM.alignment) {
                    Image(systemName: "text.alignleft").tag(NSTextAlignment.left)
                    Image(systemName: "text.aligncenter").tag(NSTextAlignment.center)
                    Image(systemName: "text.alignright").tag(NSTextAlignment.right)
                }
                .pickerStyle(.segmented).labelsHidden()
                sliderRow("circle.lefthalf.filled", $model.textWM.opacity, 0.2...1,
                          help: L("editor.text.opacity.help"))
                sliderRow("textformat.size",
                          Binding(get: { Double(model.textWM.scale) },
                                  set: { model.textWM.scale = CGFloat($0) }),
                          0.2...6, help: L("editor.text.size.help"))
                sliderRow("arrow.left.and.right",
                          Binding(get: { Double(model.textWM.tracking) },
                                  set: { model.textWM.tracking = CGFloat($0) }),
                          -12...20, help: L("editor.text.tracking.help"))
                sliderRow("arrow.up.and.down",
                          Binding(get: { Double(model.textWM.lineSpacing) },
                                  set: { model.textWM.lineSpacing = CGFloat($0) }),
                          0...24, help: L("editor.text.linespacing.help"))
                Button(role: .destructive) {
                    model.textWM.text = ""
                    endTextEditing()
                } label: {
                    Label(L("editor.text.clear.help"), systemImage: "trash").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack { logoMenu; Spacer(minLength: 0) }
            if model.logoWM != nil {
                sliderRow("circle.lefthalf.filled",
                          Binding(get: { model.logoWM?.opacity ?? 0.85 },
                                  set: { model.logoWM?.opacity = $0 }),
                          0.2...1, help: L("editor.logo.opacity.help"))
                sliderRow("textformat.size",
                          Binding(get: { Double(model.logoWM?.scale ?? 1) },
                                  set: { model.logoWM?.scale = CGFloat($0) }),
                          0.2...6, help: L("editor.logo.size.help"))
                Button(role: .destructive) { model.removeLogo() } label: {
                    Label(L("editor.logo.clear.help"), systemImage: "trash").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 176)
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
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $model.blurStyle) {
                Text(L("editor.blur.gaussian")).tag(EditorModel.BlurStyle.gaussian)
                Text(L("editor.blur.mosaic")).tag(EditorModel.BlurStyle.mosaic)
            }
            .pickerStyle(.segmented).labelsHidden()

            Picker("", selection: $model.blurApply) {
                Text(L("editor.blur.brush")).tag(EditorModel.BlurApply.brush)
                Text(L("editor.blur.area")).tag(EditorModel.BlurApply.area)
            }
            .pickerStyle(.segmented).labelsHidden()

            if model.blurApply == .brush {
                sliderRow("paintbrush",
                          Binding(get: { Double(model.blurBrushWidth) },
                                  set: { model.blurBrushWidth = CGFloat($0) }),
                          12...90, help: L("editor.blur.brushSize.help"))
            }
            Divider().overlay(Color.white.opacity(0.08))
            sliderRow("drop.fill", $model.blurIntensity, 0...1,
                      help: L("editor.blur.intensity.help"))
        }
        .frame(width: 176)
    }

    // MARK: Crop — on-canvas "Crop" button (no popover)

    /// True when the crop box differs from the full image (so cropping would
    /// actually do something). Drives the floating Crop button + its Return key.
    private var cropIsModified: Bool {
        guard model.tool == .crop, let r = cropRect else { return false }
        let full = CGRect(origin: .zero, size: model.displaySize)
        return r.minX > 0.5 || r.minY > 0.5
            || r.width < full.width - 0.5 || r.height < full.height - 0.5
    }

    /// Floating "Crop" button over the canvas center, shown once the box is changed
    /// from the full image. Return also applies it (it owns the .return shortcut).
    @ViewBuilder
    private var cropApplyOverlay: some View {
        if cropIsModified {
            Button { applyCropSelection() } label: {
                Label(L("editor.crop.apply"), systemImage: "crop")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
            .keyboardShortcut(.return, modifiers: [])
            .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        }
    }

    /// Apply the current crop to the image, then re-arm a full-image box on the
    /// freshly cropped image (which hides the Crop button until it changes again).
    private func applyCropSelection() {
        guard let r = cropRect else { return }
        model.applyCrop(r)
        cropRect = CGRect(origin: .zero, size: model.displaySize)
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

private extension NSCursor {
    /// Diagonal resize cursors for the crop box corners. AppKit has no *public*
    /// diagonal cursor, but the window-resize ones exist as internal selectors;
    /// we look them up defensively and fall back to the public crosshair if the
    /// selector ever goes away (so it can never crash).
    static var resizeNWSE: NSCursor { internalCursor("_windowResizeNorthWestSouthEastCursor") }
    static var resizeNESW: NSCursor { internalCursor("_windowResizeNorthEastSouthWestCursor") }

    private static func internalCursor(_ name: String) -> NSCursor {
        let sel = NSSelectorFromString(name)
        // These are class methods on NSCursor; dispatch through AnyObject so the
        // metatype message compiles, and fall back to crosshair if it's ever gone.
        let cls = NSCursor.self as AnyObject
        if cls.responds(to: sel), let result = cls.perform(sel) {
            return (result.takeUnretainedValue() as? NSCursor) ?? .crosshair
        }
        return .crosshair
    }
}

private extension NSTextAlignment {
    /// Map to SwiftUI's Text alignment for the on-canvas preview.
    var swiftUITextAlignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .right: return .trailing
        default: return .center
        }
    }
}

/// AppKit-backed multi-line editor for typing the watermark directly on the
/// canvas. SwiftUI's TextField treats Return as *submit* on macOS and only soft-
/// wraps, so it can't do real newlines or grow sideways; NSTextView gives real
/// Return-newlines, horizontal growth, and solid Korean IME. The caller sizes it
/// via `measure(...)` so the frame hugs the text.
private struct CanvasTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var kern: CGFloat
    var lineSpacing: CGFloat
    var alignment: NSTextAlignment
    var onCommit: () -> Void

    /// Natural size of the watermark text: width = the widest *actual* line,
    /// height = line count × line height (+ spacing). Measuring per line avoids
    /// the empty line a trailing newline leaves behind from ballooning the width
    /// to the (huge) text-container width. Used for both the editor box and snapping.
    static func measure(_ text: String, font: NSFont, kern: CGFloat, lineSpacing: CGFloat) -> CGSize {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let lines = text.components(separatedBy: "\n")
        let maxWidth = lines.reduce(CGFloat(0)) { acc, line in
            let probe = line.isEmpty ? " " : line
            let s = NSAttributedString(string: probe, attributes: [
                .font: font, .kern: kern, .paragraphStyle: para,
            ])
            return max(acc, s.size().width)
        }
        let n = CGFloat(max(1, lines.count))
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let height = n * lineHeight + (n - 1) * lineSpacing
        return CGSize(width: ceil(maxWidth) + 6, height: ceil(height) + 2)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = CanvasNSTextView(frame: .zero)
        tv.delegate = context.coordinator
        tv.onEscape = onCommit
        tv.isRichText = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = .zero
        tv.insertionPointColor = .white
        // AppKit handles vertical growth (the standard self-sizing setup): the text
        // view grows its OWN height, so SwiftUI's per-keystroke frame change no
        // longer resets the container/caret (the root cause of the caret jumping to
        // the front). Width is fixed by the scroll view (= our hug width), so long
        // lines never wrap and a trailing newline's empty line can't balloon the
        // width to the container size.
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.string = text
        context.coordinator.applyStyle(to: tv, font: font, kern: kern,
                                       lineSpacing: lineSpacing, alignment: alignment, force: true)

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.borderType = .noBorder

        // Focus once it's in a window so the caret is ready to type, at the end.
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            let end = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: end, length: 0))
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? CanvasNSTextView else { return }
        tv.onEscape = onCommit
        // Leave the text view untouched mid-composition — it scrambles Korean IME.
        guard !tv.hasMarkedText() else { return }
        // Sync genuinely external text changes (e.g. the Clear button).
        if tv.string != text { tv.string = text }
        // Restyle ONLY when a style prop actually changed (size / spacing / align).
        context.coordinator.applyStyle(to: tv, font: font, kern: kern,
                                       lineSpacing: lineSpacing, alignment: alignment, force: false)
    }

    /// Self-size to the text. Width = longest actual line (per-line measure).
    /// Height = line count × line height — with the container width fixed to the
    /// hug width nothing wraps, so visual lines == newline count and the scroll
    /// view's text view grows to fit exactly (no scrolling, no clipping).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView,
                      context: Context) -> CGSize? {
        if let tv = scroll.documentView as? CanvasNSTextView, tv.hasMarkedText() {
            return context.coordinator.lastSize   // freeze the box while composing (IME)
        }
        let size = CanvasTextEditor.measure(text, font: font, kern: kern, lineSpacing: lineSpacing)
        context.coordinator.lastSize = size
        return size
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CanvasTextEditor
        var lastSize: CGSize?
        private var lastStyle: StyleKey?
        init(_ parent: CanvasTextEditor) { self.parent = parent }

        /// Apply font / colour / kern / line-spacing / alignment. Skips work when
        /// nothing changed, so plain typing never triggers a caret-resetting restyle.
        func applyStyle(to tv: NSTextView, font: NSFont, kern: CGFloat,
                        lineSpacing: CGFloat, alignment: NSTextAlignment, force: Bool) {
            let key = StyleKey(fontName: font.fontName, fontSize: font.pointSize,
                               kern: kern, lineSpacing: lineSpacing, alignment: alignment)
            guard force || key != lastStyle else { return }
            lastStyle = key
            let para = NSMutableParagraphStyle()
            para.alignment = alignment
            para.lineSpacing = lineSpacing
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor.white, .kern: kern, .paragraphStyle: para,
            ]
            tv.typingAttributes = attrs
            tv.defaultParagraphStyle = para
            tv.font = font
            tv.alignment = alignment
            if !tv.hasMarkedText() {
                let sel = tv.selectedRange()
                tv.textStorage?.setAttributes(
                    attrs, range: NSRange(location: 0, length: (tv.string as NSString).length))
                tv.setSelectedRange(sel)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
        func textDidEndEditing(_ notification: Notification) {
            parent.onCommit()
        }
    }
}

private struct StyleKey: Equatable {
    let fontName: String
    let fontSize: CGFloat
    let kern: CGFloat
    let lineSpacing: CGFloat
    let alignment: NSTextAlignment
}

/// NSTextView that reports Esc so the editor can commit the watermark text.
private final class CanvasNSTextView: NSTextView {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
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
