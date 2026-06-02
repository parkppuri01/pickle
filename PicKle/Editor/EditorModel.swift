import AppKit
import SwiftUI
import CoreImage

/// One freehand pen stroke. Points are in **display coordinates** (top-left
/// origin). On save they're scaled to pixel size and Y-flipped for CoreGraphics.
struct PenStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var colorHex: UInt32
    var width: CGFloat
}

/// A blurred/pixellated region: either a brush stroke or a dragged rectangle.
struct BlurRegion: Identifiable {
    enum Kind {
        case stroke(points: [CGPoint], width: CGFloat)
        case rect(CGRect)
    }
    let id = UUID()
    var kind: Kind
    var style: EditorModel.BlurStyle
}

/// Text watermark — independently positioned/sized from the logo so both can be
/// used at once (0.4.0). Coordinates are display-space.
struct TextWatermark {
    var text: String = ""
    var center: CGPoint = .zero
    var scale: CGFloat = 1.0
    var opacity: Double = 0.85
    var isActive: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Logo (image) watermark — independent of the text watermark.
struct LogoWatermark {
    var image: NSImage
    var center: CGPoint = .zero
    var scale: CGFloat = 1.0
    var opacity: Double = 0.85
}

/// State + rendering for the screenshot editor.
/// 0.4.0 ① pen · ② blur/mosaic (brush + area) · ③ watermark (text AND logo,
/// each independently draggable).
///
/// Pipeline (bottom→top): base image → blur regions → pen strokes → logo → text.
final class EditorModel: ObservableObject {
    enum Tool: String, CaseIterable { case pen, blur, watermark }
    enum BlurStyle { case gaussian, mosaic }
    enum BlurApply { case brush, area }
    /// One undoable action, newest last — lets ⌘Z undo pen and blur in the real
    /// order they were drawn, regardless of which tool is currently selected.
    enum EditAction { case pen, blur }

    let baseImage: NSImage
    let imagePixelSize: CGSize
    let displaySize: CGSize
    let fileURL: URL

    @Published var tool: Tool = .pen

    /// Chronological pen/blur history for unified ⌘Z undo.
    @Published private(set) var undoStack: [EditAction] = []

    // Pen
    @Published var strokes: [PenStroke] = []
    @Published var current: PenStroke?
    @Published var colorHex: UInt32 = 0xE5484D
    @Published var lineWidth: CGFloat = 5

    // Watermark — text and logo are independent (both can be active at once).
    @Published var textWM = TextWatermark()
    @Published var logoWM: LogoWatermark?

    // Blur
    @Published var blurStyle: BlurStyle = .gaussian
    @Published var blurApply: BlurApply = .brush
    @Published var blurBrushWidth: CGFloat = 34
    /// 0 = light, 1 = heavy. Invalidates the processed caches when changed.
    @Published var blurIntensity: Double = 0.5 {
        didSet { gaussianCache = nil; mosaicCache = nil }
    }
    @Published var blurRegions: [BlurRegion] = []
    @Published var currentBlurStroke: [CGPoint]?
    @Published var currentBlurRect: CGRect?
    private var gaussianCache: NSImage?
    private var mosaicCache: NSImage?

    static let watermarkBaseFont: CGFloat = 30
    static let watermarkLogoWidthFraction: CGFloat = 0.25
    /// UserDefaults key: chosen watermark font family ("" = system bold).
    /// Set from the Settings window; read here at render time.
    static let fontDefaultsKey = "watermarkFontFamily"
    /// UserDefaults: remember the last watermark text and pre-fill it next time.
    static let rememberTextKey = "rememberWatermarkText"
    static let lastTextKey = "lastWatermarkText"

    /// Resolve the NSFont for the text watermark: the user-chosen installed font
    /// (from Settings) if set & available, otherwise the system bold font.
    static func watermarkNSFont(size: CGFloat) -> NSFont {
        let family = UserDefaults.standard.string(forKey: fontDefaultsKey) ?? ""
        if !family.isEmpty {
            if let f = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) { return f }
            if let f = NSFont(name: family, size: size) { return f }
        }
        return NSFont.boldSystemFont(ofSize: size)
    }
    static let palette: [UInt32] = [0xE5484D, 0xF2A33C, 0xF5D90A, 0x4CAF50, 0x2D7FF9, 0xFFFFFF, 0x111111]
    static let widths: [CGFloat] = [3, 6, 11]

    init?(fileURL: URL) {
        guard let img = NSImage(contentsOf: fileURL) else { return nil }
        self.fileURL = fileURL
        self.baseImage = img
        let px = img.representations.first.map {
            CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
        } ?? img.size
        self.imagePixelSize = px
        let maxW: CGFloat = 1000, maxH: CGFloat = 640
        let scale = min(maxW / px.width, maxH / px.height, 1)
        self.displaySize = CGSize(width: (px.width * scale).rounded(),
                                  height: (px.height * scale).rounded())
        // Text starts at bottom-center.
        self.textWM.center = CGPoint(x: displaySize.width / 2, y: displaySize.height * 0.85)
        // Optionally pre-fill the last-used text (Settings toggle).
        if UserDefaults.standard.bool(forKey: Self.rememberTextKey) {
            self.textWM.text = UserDefaults.standard.string(forKey: Self.lastTextKey) ?? ""
        }
    }

    // MARK: - Pen

    func begin(at p: CGPoint) { current = PenStroke(points: [p], colorHex: colorHex, width: lineWidth) }
    func extend(to p: CGPoint) { current?.points.append(p) }
    func commit() {
        if let c = current, c.points.count > 1 {
            strokes.append(c)
            undoStack.append(.pen)
        }
        current = nil
    }

    // MARK: - Unified undo (⌘Z)

    var canUndo: Bool { !undoStack.isEmpty }
    /// Undo the most recent pen stroke or blur region, in draw order.
    func undoLast() {
        guard let last = undoStack.popLast() else { return }
        switch last {
        case .pen:  if !strokes.isEmpty { strokes.removeLast() }
        case .blur: if !blurRegions.isEmpty { blurRegions.removeLast() }
        }
    }

    // MARK: - Watermark

    /// Replace the logo watermark, placing it just above the text's default spot
    /// so the two don't land exactly on top of each other.
    func setLogo(_ image: NSImage) {
        logoWM = LogoWatermark(
            image: image,
            center: CGPoint(x: displaySize.width / 2, y: displaySize.height * 0.6))
    }
    func removeLogo() { logoWM = nil }

    /// Display size of the logo, honoring its own scale.
    func logoDisplaySize() -> CGSize {
        guard let logo = logoWM, logo.image.size.width > 0 else { return .zero }
        let w = displaySize.width * Self.watermarkLogoWidthFraction * logo.scale
        return CGSize(width: w, height: w * (logo.image.size.height / logo.image.size.width))
    }

    // MARK: - Blur

    func extendBlurBrush(to p: CGPoint) {
        if currentBlurStroke == nil { currentBlurStroke = [p] } else { currentBlurStroke?.append(p) }
    }
    func updateBlurRect(from start: CGPoint, to p: CGPoint) {
        currentBlurRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                                 width: abs(p.x - start.x), height: abs(p.y - start.y))
    }
    func commitBlur() {
        var added = false
        if let pts = currentBlurStroke, pts.count > 1 {
            blurRegions.append(BlurRegion(kind: .stroke(points: pts, width: blurBrushWidth), style: blurStyle))
            added = true
        }
        if let r = currentBlurRect, r.width > 4, r.height > 4 {
            blurRegions.append(BlurRegion(kind: .rect(r), style: blurStyle))
            added = true
        }
        if added { undoStack.append(.blur) }
        currentBlurStroke = nil
        currentBlurRect = nil
    }

    /// A fully blurred / pixellated copy of the base image (lazy + cached).
    /// We reveal it only inside the blur regions.
    func processed(_ style: BlurStyle) -> NSImage? {
        switch style {
        case .gaussian:
            if gaussianCache == nil { gaussianCache = makeProcessed(.gaussian) }
            return gaussianCache
        case .mosaic:
            if mosaicCache == nil { mosaicCache = makeProcessed(.mosaic) }
            return mosaicCache
        }
    }

    private func makeProcessed(_ style: BlurStyle) -> NSImage? {
        guard let tiff = baseImage.tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
        let extent = ci.extent
        let output: CIImage?
        switch style {
        case .gaussian:
            // intensity 0→1 maps radius to ~0.4%→2.4% of image width.
            let radius = max(4, imagePixelSize.width * (0.004 + 0.020 * blurIntensity))
            let f = CIFilter(name: "CIGaussianBlur")
            f?.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
            f?.setValue(radius, forKey: kCIInputRadiusKey)
            output = f?.outputImage?.cropped(to: extent)
        case .mosaic:
            // intensity 0→1 maps block size to ~0.8%→3.8% of image width.
            let blockScale = max(6, imagePixelSize.width * (0.008 + 0.030 * blurIntensity))
            let f = CIFilter(name: "CIPixellate")
            f?.setValue(ci, forKey: kCIInputImageKey)
            f?.setValue(blockScale, forKey: "inputScale")
            output = f?.outputImage?.cropped(to: extent)
        }
        guard let out = output else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: imagePixelSize)
        img.addRepresentation(rep)
        return img
    }

    var hasEdits: Bool { !strokes.isEmpty || textWM.isActive || logoWM != nil || !blurRegions.isEmpty }

    // MARK: - Render & save

    private func renderBitmap() -> NSBitmapImageRep? {
        let w = Int(imagePixelSize.width), h = Int(imagePixelSize.height)
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = imagePixelSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = gctx
        let ctx = gctx.cgContext
        let scale = imagePixelSize.width / displaySize.width

        baseImage.draw(in: NSRect(origin: .zero, size: imagePixelSize))
        drawBlurRegions(ctx, scale: scale)
        drawStrokes(ctx, scale: scale)
        drawLogoWatermark(scale: scale)
        drawTextWatermark(scale: scale)
        return rep
    }

    private func drawBlurRegions(_ ctx: CGContext, scale: CGFloat) {
        for region in blurRegions {
            guard let proc = processed(region.style) else { continue }
            ctx.saveGState()
            switch region.kind {
            case .rect(let r):
                let pr = CGRect(x: r.minX * scale,
                                y: imagePixelSize.height - r.maxY * scale,
                                width: r.width * scale, height: r.height * scale)
                ctx.clip(to: pr)
            case .stroke(let pts, let width):
                guard let first = pts.first else { ctx.restoreGState(); continue }
                ctx.setLineCap(.round); ctx.setLineJoin(.round)
                ctx.setLineWidth(width * scale)
                ctx.beginPath()
                ctx.move(to: flip(first, scale: scale))
                for p in pts.dropFirst() { ctx.addLine(to: flip(p, scale: scale)) }
                ctx.replacePathWithStrokedPath()
                ctx.clip()
            }
            proc.draw(in: NSRect(origin: .zero, size: imagePixelSize))
            ctx.restoreGState()
        }
    }

    private func drawStrokes(_ ctx: CGContext, scale: CGFloat) {
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            ctx.setStrokeColor(nsColor(stroke.colorHex).cgColor)
            ctx.setLineWidth(stroke.width * scale)
            ctx.beginPath()
            ctx.move(to: flip(first, scale: scale))
            for p in stroke.points.dropFirst() { ctx.addLine(to: flip(p, scale: scale)) }
            ctx.strokePath()
        }
    }

    private func drawTextWatermark(scale: CGFloat) {
        guard textWM.isActive else { return }
        let text = textWM.text.trimmingCharacters(in: .whitespaces)
        let cx = textWM.center.x * scale
        let cy = imagePixelSize.height - textWM.center.y * scale
        let fontSize = Self.watermarkBaseFont * textWM.scale * scale
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = fontSize * 0.10
        shadow.shadowOffset = NSSize(width: 0, height: -fontSize * 0.04)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.watermarkNSFont(size: fontSize),
            .foregroundColor: NSColor.white.withAlphaComponent(textWM.opacity),
            .shadow: shadow,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: cx - size.width / 2, y: cy - size.height / 2))
    }

    private func drawLogoWatermark(scale: CGFloat) {
        guard let logo = logoWM else { return }
        let cx = logo.center.x * scale
        let cy = imagePixelSize.height - logo.center.y * scale
        let d = logoDisplaySize()
        let w = d.width * scale, h = d.height * scale
        logo.image.draw(in: NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h),
                        from: .zero, operation: .sourceOver, fraction: logo.opacity)
    }

    @discardableResult
    func save() -> Bool {
        guard let rep = renderBitmap(),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: fileURL)
            // Remember the watermark text for next time, if the user opted in.
            if UserDefaults.standard.bool(forKey: Self.rememberTextKey) {
                UserDefaults.standard.set(textWM.text, forKey: Self.lastTextKey)
            }
            return true
        } catch { NSLog("PicKle editor save failed: \(error)"); return false }
    }

    // MARK: - Helpers

    private func flip(_ p: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: p.x * scale, y: imagePixelSize.height - p.y * scale)
    }
    private func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
