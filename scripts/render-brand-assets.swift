import AppKit
import CoreText

// Brand asset renderer for 复盘了 / Portfolio Review — V3 “白板 + 画架” system.
// Run from the ios/ directory: `swift scripts/render-brand-assets.swift`
// Writes docs/brand/assets/{brand-board.png, app-icon-light-1024.png, app-icon-dark-1024.png,
//   logo-mark-light.png, logo-mark-dark.png, logo-lockup-light.png, logo-lockup-dark.png, logo-mark.svg}
// and, only while the legacy asset catalog appiconset still exists, its AppIcon.png.
//
// Flat previews only: the shipping app icon is the layered Icon Composer document
// (PortfolioAgent/AppIcon.icon), rendered by the system. This script never fakes glass,
// highlights, shadows or blur; it composes the source colours of the icon layers flat.
//
// The icon artwork itself lives in docs/brand/icon/layers/*.svg + docs/brand/icon/palette.json
// and is owned upstream (see docs/brand/icon/README.md). The GENERATED GEOMETRY / GENERATED
// PALETTE blocks below are a mirror of that source; if you change one, change both.
// In-app BrandMark in PortfolioAgent/DesignSystem.swift mirrors the same geometry.
//
// Internal target/bundle name remains PortfolioAgent; only user-facing branding changes.

let S: CGFloat = 1024
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brandAssets = root.appendingPathComponent("docs/brand/assets", isDirectory: true)
let legacyAppIcon = root.appendingPathComponent("PortfolioAgent/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: brandAssets, withIntermediateDirectories: true)

let monoMediumURL = root.appendingPathComponent("PortfolioAgent/Resources/IBMPlexMono-Medium.ttf")
let monoRegularURL = root.appendingPathComponent("PortfolioAgent/Resources/IBMPlexMono-Regular.ttf")
CTFontManagerRegisterFontsForURL(monoMediumURL as CFURL, .process, nil)
CTFontManagerRegisterFontsForURL(monoRegularURL as CFURL, .process, nil)

// MARK: - Locked geometry (unit-square = icon canvas, top-left origin, 1024 units)
// Mirror of docs/brand/icon/layers/*.svg (source of truth) and palette.json.
// Keep in sync with BrandMark in PortfolioAgent/DesignSystem.swift.
struct MarkGeometry {
    var canvas: CGFloat
    // Board group, back layer: the whiteboard frame (the light-blue rim that makes it a board).
    var frame: CGRect
    var frameRadius: CGFloat
    // Board group, front layer: the writing surface.
    var surface: CGRect
    var surfaceRadius: CGFloat
    // Hardware group: the two crossed easel legs (no clamp: the artwork's top edge is the board top).
    var legs: [[CGPoint]]
    var legWidth: CGFloat
    // Ink group: the trend line with its arrow head, plus the two analysis rules.
    var trend: [CGPoint]
    var trendWidth: CGFloat
    var arrow: [CGPoint]
    var arrowWidth: CGFloat
    var analysisRules: [CGRect]
    var ruleRadius: CGFloat
    // Conclusion group: the chalk-blue conclusion rule (V1's “blue = conclusion” back as a line).
    var conclusionRule: CGRect

    /// Visual bounds of the mark: frame + easel legs (including round caps).
    /// The logo / in-app mark is cropped to this box, never to the icon canvas.
    var markBounds: CGRect {
        var minX = frame.minX
        var minY = frame.minY
        var maxX = frame.maxX
        var maxY = frame.maxY
        for leg in legs {
            let half = legWidth / 2
            for p in leg {
                minX = min(minX, p.x - half); maxX = max(maxX, p.x + half)
                minY = min(minY, p.y - half); maxY = max(maxY, p.y + half)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK UNIT GEOMETRY — unscaled source coordinates (the stand-alone logo assets and the
// in-app BrandMark use these verbatim; see the golden-ratio icon composition below).
// >>> BEGIN GENERATED GEOMETRY
// MARK UNIT GEOMETRY — unscaled coordinates. The checked-in icon layer SVGs hold the
// golden-ratio scaled composition; this block is the same artwork before that scale,
// which is what the stand-alone marks and the in-app BrandMark use.
let geometry = MarkGeometry(
    canvas: 1024,
    frame: CGRect(x: 80, y: 100, width: 864, height: 636),
    frameRadius: 30,
    surface: CGRect(x: 106, y: 126, width: 812, height: 584),
    surfaceRadius: 4,
    legs: [
        [CGPoint(x: 412, y: 748), CGPoint(x: 846, y: 936)],
        [CGPoint(x: 632, y: 748), CGPoint(x: 178, y: 936)],
    ],
    legWidth: 48,
    trend: [CGPoint(x: 150, y: 612), CGPoint(x: 270, y: 480), CGPoint(x: 350, y: 548), CGPoint(x: 684, y: 300)],
    trendWidth: 32,
    arrow: [CGPoint(x: 653.8, y: 369.7), CGPoint(x: 684, y: 300), CGPoint(x: 608.5, y: 308.7)],
    arrowWidth: 32,
    analysisRules: [
        CGRect(x: 636, y: 545, width: 164, height: 28),
        CGRect(x: 636, y: 620, width: 104, height: 28),
    ],
    ruleRadius: 14,
    conclusionRule: CGRect(x: 636, y: 470, width: 234, height: 28)
)
// <<< END GENERATED GEOMETRY

// MARK: - Golden-ratio icon composition
// The app icon is the same artwork scaled to 1/φ ≈ 61.8% of the canvas height and centred:
//   p' = (512, 512) + (p − (512, 530)) × 0.732485
// Bounds after scale: 632.9 × 629.9 (61.8% × 61.5% of the canvas), margins x ±195.6 / y ±197.0.
// The clamp was removed: the artwork's top edge is the whiteboard's top edge.
// Leave the unit geometry above untouched: a uniform scale does not change the mark's own
// proportions, so the logo assets and the in-app BrandMark keep using it as-is.
// Only the app-icon previews and the brand board's APP ICON panel use `iconGeometry`.
let iconArtworkScale: CGFloat = 0.732485
let iconArtworkOrigin = CGPoint(x: 512, y: 530)   // pre-scale bbox centre
let iconCanvasOrigin = CGPoint(x: 512, y: 512)    // post-scale centre in the 1024 canvas

func iconScaledGeometry(_ g: MarkGeometry) -> MarkGeometry {
    func p(_ point: CGPoint) -> CGPoint {
        CGPoint(x: iconCanvasOrigin.x + (point.x - iconArtworkOrigin.x) * iconArtworkScale,
                y: iconCanvasOrigin.y + (point.y - iconArtworkOrigin.y) * iconArtworkScale)
    }
    func r(_ rect: CGRect) -> CGRect {
        let a = p(CGPoint(x: rect.minX, y: rect.minY))
        return CGRect(x: a.x, y: a.y,
                      width: rect.width * iconArtworkScale, height: rect.height * iconArtworkScale)
    }
    var out = g
    out.frame = r(g.frame); out.frameRadius = g.frameRadius * iconArtworkScale
    out.surface = r(g.surface); out.surfaceRadius = g.surfaceRadius * iconArtworkScale
    out.legs = g.legs.map { $0.map(p) }; out.legWidth = g.legWidth * iconArtworkScale
    out.trend = g.trend.map(p); out.trendWidth = g.trendWidth * iconArtworkScale
    out.arrow = g.arrow.map(p); out.arrowWidth = g.arrowWidth * iconArtworkScale
    out.analysisRules = g.analysisRules.map(r); out.ruleRadius = g.ruleRadius * iconArtworkScale
    out.conclusionRule = r(g.conclusionRule)
    return out
}

let iconGeometry = iconScaledGeometry(geometry)


// MARK: - Palette
// Mirror of docs/brand/icon/palette.json: only three authored fills per layer/background
// (light / dark / tinted). The six renditions are composed by the system on top; Clear*
// renditions have no authored colours at all.
struct PaletteBucket {
    let key: String        // source bucket: light | dark | tinted
    let label: String      // display name on the board
    let note: String       // what the bucket is for
    let paper: NSColor     // document background (app-icon background layer)
    let surface: NSColor   // Board group: writing surface
    let frame: NSColor     // Board group: frame (automatic gradient in the .icon)
    let ink: NSColor       // Ink group: trend line, arrow, analysis rules
    let hardware: NSColor  // Hardware group: easel legs
    let accent: NSColor    // Conclusion group: conclusion rule
}

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

// UI core palette — unchanged from V1.
let ink = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)         // #000000 结构 / 正文
let paperUI = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)     // #FFFFFF 界面底
let brandBlue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)   // #0000FF 链接 / 选中
let grey = NSColor(srgbRed: 0.4, green: 0.4, blue: 0.4, alpha: 1)  // #666666 次级
let lightGrey = NSColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1)
let green = NSColor(srgbRed: 0, green: 0.667, blue: 0, alpha: 1)   // #00AA00 涨，仅功能色
let red = NSColor(srgbRed: 0.8, green: 0, blue: 0, alpha: 1)       // #CC0000 跌，仅功能色

// >>> BEGIN GENERATED PALETTE
// Locked palette (docs/brand/icon/palette.json).
let paletteLight = PaletteBucket(
    key: "light", label: "LIGHT / DEFAULT", note: "浅色桌面 · Default 外观",
    paper: srgb(242, 238, 228),
    surface: srgb(251, 250, 244),
    frame: srgb(201, 211, 238),
    ink: srgb(20, 24, 29),
    hardware: srgb(20, 24, 29),
    accent: srgb(61, 107, 255))
let paletteDark = PaletteBucket(
    key: "dark", label: "DARK", note: "深色外观",
    paper: srgb(23, 26, 31),
    surface: srgb(214, 209, 195),
    frame: srgb(58, 67, 86),
    ink: srgb(23, 26, 31),
    hardware: srgb(184, 178, 164),
    accent: srgb(143, 166, 255))
let paletteTinted = PaletteBucket(
    key: "tinted", label: "TINTED", note: "着色外观的源色",
    paper: srgb(232, 232, 232),
    surface: srgb(255, 255, 255),
    frame: srgb(171, 171, 171),
    ink: srgb(36, 36, 36),
    hardware: srgb(176, 176, 176),
    accent: srgb(110, 110, 110))

let authoredPalettes = [paletteLight, paletteDark, paletteTinted]
// Six renditions: which authored bucket each starts from, and what the system adds.
let renditions: [(name: String, bucket: String, system: String)] = [
    ("Default", "light", "—"),
    ("Dark", "dark", "—"),
    ("TintedLight", "tinted", "系统取色 · 浅"),
    ("TintedDark", "tinted", "系统取色 · 深"),
    ("ClearLight", "—", "系统单色 · 浅"),
    ("ClearDark", "—", "系统单色 · 深"),
]
// <<< END GENERATED PALETTE

// MARK: - Canvas helpers (top-left coordinates)

final class Sheet {
    let ctx: CGContext
    let width: CGFloat
    let height: CGFloat

    init(width: Int, height: Int, opaque: Bool, background: NSColor? = nil) {
        self.width = CGFloat(width)
        self.height = CGFloat(height)
        let space = CGColorSpaceCreateDeviceRGB()
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue)!
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        if let background {
            background.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: self.width, height: self.height)).fill()
        }
    }

    /// Rectangle in top-left coordinates.
    func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(rect: NSRect(x: x, y: height - top - h, width: w, height: h)).fill()
    }

    func roundedRect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     radius: CGFloat, _ color: NSColor) {
        color.setFill()
        let r = min(radius, min(w, h) / 2)
        NSBezierPath(roundedRect: NSRect(x: x, y: height - top - h, width: w, height: h),
                     xRadius: r, yRadius: r).fill()
    }

    func stroke(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, width lw: CGFloat = 1) {
        color.setStroke()
        let path = NSBezierPath(rect: NSRect(x: x, y: height - top - h, width: w, height: h))
        path.lineWidth = lw
        path.stroke()
    }

    func line(_ x1: CGFloat, _ top1: CGFloat, _ x2: CGFloat, _ top2: CGFloat, _ color: NSColor, width lw: CGFloat = 1) {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x1, y: height - top1))
        path.line(to: NSPoint(x: x2, y: height - top2))
        path.lineWidth = lw
        path.stroke()
    }

    func circle(cx: CGFloat, cy: CGFloat, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        let r = NSRect(x: cx - radius, y: height - cy - radius, width: radius * 2, height: radius * 2)
        NSBezierPath(ovalIn: r).fill()
    }

    func circleStroke(cx: CGFloat, cy: CGFloat, radius: CGFloat, lineWidth lw: CGFloat, _ color: NSColor) {
        color.setStroke()
        let r = NSRect(x: cx - radius, y: height - cy - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: r)
        path.lineWidth = lw
        path.stroke()
    }

    func polyline(_ points: [CGPoint], lineWidth lw: CGFloat, _ color: NSColor) {
        guard points.count > 1 else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: points[0].x, y: height - points[0].y))
        for p in points.dropFirst() {
            path.line(to: NSPoint(x: p.x, y: height - p.y))
        }
        path.lineWidth = lw
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    func font(_ name: String, _ size: CGFloat) -> NSFont {
        NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    func measure(_ string: String, _ font: NSFont, tracking: CGFloat = 0) -> CGSize {
        NSAttributedString(string: string, attributes: [.font: font, .kern: tracking]).size()
    }

    @discardableResult
    func text(_ string: String, _ font: NSFont, _ color: NSColor, x: CGFloat, top: CGFloat,
              tracking: CGFloat = 0, lineSpacing: CGFloat = 0, maxWidth: CGFloat? = nil,
              align: NSTextAlignment = .left) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: tracking,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: string, attributes: attrs)
        let measured: CGSize
        if let maxWidth {
            let bounds = attributed.boundingRect(with: NSSize(width: maxWidth, height: 10_000),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading])
            measured = CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        } else {
            measured = attributed.size()
        }
        attributed.draw(with: NSRect(x: x, y: height - top - measured.height, width: maxWidth ?? measured.width + 8,
                                     height: measured.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
        // Layout sanity: catch copy that would run past the sheet or off the bottom.
        if x + measured.width > width + 0.5 || top + measured.height > height + 0.5 {
            print("WARN text overflows sheet: \"\(string.prefix(24))\" x=\(Int(x)) w=\(Int(measured.width)) h=\(Int(measured.height))")
        }
        return measured
    }

    func png() throws -> Data {
        guard let image = ctx.makeImage() else { throw NSError(domain: "render", code: 1) }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    }

    func save(_ url: URL) throws {
        try png().write(to: url)
    }

    func finish() {
        NSGraphicsContext.restoreGraphicsState()
    }
}

func write(_ sheet: Sheet, _ url: URL, label: String) throws {
    try sheet.save(url)
    sheet.finish()
    print("rendered \(label) -> \(url.path)")
}

// MARK: - Mark placement
// `.icon`  — the full app-icon canvas: paper background + board slab at its locked inset.
// `.mark`  — the logo / in-app unit box: cropped to the board, so the slab is the mark.
enum MarkFrame { case icon, mark }

struct MarkPlacement {
    let scale: CGFloat
    let offset: CGPoint   // canvas units -> sheet points: sheet = (canvas - offset) * scale

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.x) * scale, y: (p.y - offset.y) * scale)
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { point(CGPoint(x: x, y: y)) }
    func rect(_ r: CGRect) -> CGRect {
        let a = point(CGPoint(x: r.minX, y: r.minY))
        let b = point(CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
}

/// Full app-icon canvas placed into `box`.
func iconPlacement(in box: CGRect) -> MarkPlacement {
    let scale = box.width / geometry.canvas
    return MarkPlacement(scale: scale,
                         offset: CGPoint(x: -box.minX / scale,
                                         y: -box.minY / scale))
}

/// Mark placed into `box`: the slab bounds fill the box (longest side), centred.
/// The icon canvas is not the mark box — paper margins never appear in the mark.
func markPlacement(in box: CGRect) -> MarkPlacement {
    let bounds = geometry.markBounds
    let scale = box.width / max(bounds.width, bounds.height)
    let boundsCenter = CGPoint(x: bounds.midX, y: bounds.midY)
    let targetCenter = CGPoint(x: box.midX, y: box.midY)
    return MarkPlacement(scale: scale,
                         offset: CGPoint(x: boundsCenter.x - targetCenter.x / scale,
                                         y: boundsCenter.y - targetCenter.y / scale))
}

/// Full-colour 「白板 + 画架」 mark: frame, surface, easel legs, ink, conclusion.
/// Every asset paints explicit source colours; no faked glass, shadow or blur.
func drawMark(_ sheet: Sheet, placement: MarkPlacement,
              geometry: MarkGeometry = geometry, palette: PaletteBucket) {
    func rounded(_ r: CGRect, _ radius: CGFloat, _ color: NSColor) {
        let p = placement.rect(r)
        sheet.roundedRect(p.minX, p.minY, p.width, p.height, radius: radius * placement.scale, color)
    }
    // Board group, back → front: frame, then the writing surface on top of it.
    rounded(geometry.frame, geometry.frameRadius, palette.frame)
    rounded(geometry.surface, geometry.surfaceRadius, palette.surface)
    // Hardware group: the two crossed easel legs.
    for leg in geometry.legs {
        sheet.polyline(leg.map { placement.point($0) },
                       lineWidth: geometry.legWidth * placement.scale, palette.hardware)
    }
    // Ink group: trend line + arrow head + two analysis rules.
    sheet.polyline(geometry.trend.map { placement.point($0) },
                   lineWidth: geometry.trendWidth * placement.scale, palette.ink)
    sheet.polyline(geometry.arrow.map { placement.point($0) },
                   lineWidth: geometry.arrowWidth * placement.scale, palette.ink)
    for rule in geometry.analysisRules {
        rounded(rule, geometry.ruleRadius, palette.ink)
    }
    // Conclusion group: the chalk-blue rule.
    rounded(geometry.conclusionRule, geometry.ruleRadius, palette.accent)
}

/// Solid-silhouette mark for in-app use: one ink slab (whiteboard + easel legs), the
/// chart/analysis marks knocked out to `paper`, the conclusion rule in `accent`.
/// At 14pt a 26-unit frame would be sub-pixel, so the silhouette is intentionally solid.
func drawSolidMark(_ sheet: Sheet, placement: MarkPlacement,
                   board: NSColor, paper: NSColor, accent: NSColor) {
    func rounded(_ r: CGRect, _ radius: CGFloat, _ color: NSColor) {
        let p = placement.rect(r)
        sheet.roundedRect(p.minX, p.minY, p.width, p.height, radius: radius * placement.scale, color)
    }
    // Silhouette: the whole board (frame + surface read as one slab) plus the easel legs.
    rounded(geometry.frame, geometry.frameRadius, board)
    for leg in geometry.legs {
        sheet.polyline(leg.map { placement.point($0) },
                       lineWidth: geometry.legWidth * placement.scale, board)
    }
    // Knock-out ink: trend, arrow head, analysis rules show the page colour.
    sheet.polyline(geometry.trend.map { placement.point($0) },
                   lineWidth: geometry.trendWidth * placement.scale, paper)
    sheet.polyline(geometry.arrow.map { placement.point($0) },
                   lineWidth: geometry.arrowWidth * placement.scale, paper)
    for rule in geometry.analysisRules {
        rounded(rule, geometry.ruleRadius, paper)
    }
    // Conclusion rule stays coloured.
    rounded(geometry.conclusionRule, geometry.ruleRadius, accent)
}

/// App-icon flat preview: paper background + the icon composition.
func drawIconPreview(_ sheet: Sheet, box: CGRect, palette: PaletteBucket) {
    sheet.rect(box.minX, box.minY, box.width, box.height, palette.paper)
    drawMark(sheet, placement: iconPlacement(in: box), geometry: iconGeometry, palette: palette)
}

func rgbHex(_ color: NSColor) -> String {
    let c = color.usingColorSpace(.sRGB) ?? color
    return String(format: "#%02X%02X%02X",
                  Int((c.redComponent * 255).rounded()),
                  Int((c.greenComponent * 255).rounded()),
                  Int((c.blueComponent * 255).rounded()))
}

// MARK: - App icon flat previews
// These are *source-colour previews*, not the shipping icon. The shipping icon is
// PortfolioAgent/AppIcon.icon, rendered by the system for each appearance.

func renderIconPreview(_ palette: PaletteBucket, to url: URL) throws {
    let sheet = Sheet(width: 1024, height: 1024, opaque: true)
    drawIconPreview(sheet, box: CGRect(x: 0, y: 0, width: 1024, height: 1024), palette: palette)
    try write(sheet, url, label: "app icon preview (\(palette.key))")
}

try renderIconPreview(paletteLight, to: brandAssets.appendingPathComponent("app-icon-light-1024.png"))
try renderIconPreview(paletteDark, to: brandAssets.appendingPathComponent("app-icon-dark-1024.png"))

// Legacy asset catalog: only touch it while it still exists; the .icon migration owns its removal.
if FileManager.default.fileExists(atPath: legacyAppIcon.path) {
    let sheet = Sheet(width: 1024, height: 1024, opaque: true)
    drawIconPreview(sheet, box: CGRect(x: 0, y: 0, width: 1024, height: 1024), palette: paletteLight)
    try write(sheet, legacyAppIcon.appendingPathComponent("AppIcon.png"), label: "legacy AppIcon.png")
} else {
    print("skipped legacy AppIcon.appiconset (icon now ships as AppIcon.icon)")
}

// MARK: - Standalone marks (transparent, board = the unit box)

func renderMark(palette: PaletteBucket, to url: URL) throws {
    let sheet = Sheet(width: 1024, height: 1024, opaque: false)
    let boxSize = S * 0.88
    let box = CGRect(x: (S - boxSize) / 2, y: (S - boxSize) / 2, width: boxSize, height: boxSize)
    drawMark(sheet, placement: markPlacement(in: box), palette: palette)
    try write(sheet, url, label: "mark")
}

// Light material: Default palette. Dark material: Dark palette (surface turns warm beige,
// hardware turns light warm grey — the authored Dark appearance, not an inversion).
try renderMark(palette: paletteLight, to: brandAssets.appendingPathComponent("logo-mark-light.png"))
try renderMark(palette: paletteDark, to: brandAssets.appendingPathComponent("logo-mark-dark.png"))

// MARK: - Lockups

func lockupWidth() -> CGFloat {
    let wordFont = NSFont(name: "STSongti-SC-Regular", size: 168)!
    let descFont = NSFont(name: "IBMPlexMono-Medium", size: 30)!
    let word = NSAttributedString(string: "复盘了", attributes: [.font: wordFont, .kern: 4]).size().width
    let desc = NSAttributedString(string: "PORTFOLIO REVIEW", attributes: [.font: descFont, .kern: 6.5]).size().width
    return 120 + 240 + 120 + max(word, desc) + 120
}

func renderLockup(dark: Bool, to url: URL) throws {
    let w = Int(ceil(lockupWidth()))
    let h = 480
    let sheet = Sheet(width: w, height: h, opaque: false, background: dark ? ink : nil)
    let wordColor = dark ? paperUI : ink
    let descColor = dark ? NSColor(srgbRed: 0.72, green: 0.72, blue: 0.72, alpha: 1) : grey
    let material = dark ? paletteDark : paletteLight
    let markBox = CGRect(x: 120, y: 108, width: 240, height: 240)
    drawMark(sheet, placement: markPlacement(in: markBox), palette: material)
    let wordFont = NSFont(name: "STSongti-SC-Regular", size: 168)!
    sheet.text("复盘了", wordFont, wordColor, x: 480, top: 118, tracking: 4)
    let descFont = NSFont(name: "IBMPlexMono-Medium", size: 30)!
    sheet.text("PORTFOLIO REVIEW", descFont, descColor, x: 486, top: 330, tracking: 6.5)
    try write(sheet, url, label: "lockup \(dark ? "dark" : "light")")
}

try renderLockup(dark: false, to: brandAssets.appendingPathComponent("logo-lockup-light.png"))
try renderLockup(dark: true, to: brandAssets.appendingPathComponent("logo-lockup-dark.png"))

// MARK: - SVG mark (vector, coloured, transparent)

func svgMark() -> String {
    let box = 1024.0 * 0.88
    let boxRect = CGRect(x: (1024 - box) / 2, y: (1024 - box) / 2, width: box, height: box)
    let p = markPlacement(in: boxRect)
    let palette = paletteLight
    func fmt(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    func fill(_ color: NSColor) -> String { rgbHex(color) }
    func rectLine(_ r: CGRect, _ radius: CGFloat, _ color: NSColor) -> String {
        let a = p.rect(r)
        return "  <rect x=\"\(fmt(a.minX))\" y=\"\(fmt(a.minY))\" width=\"\(fmt(a.width))\" height=\"\(fmt(a.height))\" rx=\"\(fmt(radius * p.scale))\" fill=\"\(fill(color))\"/>\n"
    }
    func pathLine(_ pts: [CGPoint], _ width: CGFloat, _ color: NSColor) -> String {
        let q = pts.map { p.point($0) }
        let d = "M " + q.map { "\(fmt($0.x)) \(fmt($0.y))" }.joined(separator: " L ")
        return "  <path d=\"\(d)\" fill=\"none\" stroke=\"\(fill(color))\" stroke-width=\"\(fmt(width * p.scale))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
    }
    var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    out += "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\">\n"
    out += "  <title>复盘了 · mark</title>\n"
    out += rectLine(geometry.frame, geometry.frameRadius, palette.frame)
    out += rectLine(geometry.surface, geometry.surfaceRadius, palette.surface)
    for leg in geometry.legs { out += pathLine(leg, geometry.legWidth, palette.hardware) }
    out += pathLine(geometry.trend, geometry.trendWidth, palette.ink)
    out += pathLine(geometry.arrow, geometry.arrowWidth, palette.ink)
    for rule in geometry.analysisRules { out += rectLine(rule, geometry.ruleRadius, palette.ink) }
    out += rectLine(geometry.conclusionRule, geometry.ruleRadius, palette.accent)
    out += "</svg>\n"
    return out
}
try svgMark().write(to: brandAssets.appendingPathComponent("logo-mark.svg"), atomically: true, encoding: .utf8)
print("rendered svg mark")

// MARK: - Brand board
// Board layout (2400 x 2140): header, hero, 01 mark, 02 lockup, 03 UI colour,
// 04 type, 05 icon appearance, footer.

let boardW = 2400, boardH = 2140
let board = Sheet(width: boardW, height: boardH, opaque: true, background: paperUI)
let margin: CGFloat = 120
let boardWidth = CGFloat(boardW)

let semibold = { (size: CGFloat) in NSFont(name: "PingFangSC-Semibold", size: size)! }
let songti = { (size: CGFloat) in NSFont(name: "STSongti-SC-Regular", size: size)! }
let regular = { (size: CGFloat) in NSFont(name: "PingFangSC-Regular", size: size)! }
let medium = { (size: CGFloat) in NSFont(name: "PingFangSC-Medium", size: size)! }
let mono = { (size: CGFloat) in NSFont(name: "IBMPlexMono-Medium", size: size)! }
let monoRegular = { (size: CGFloat) in NSFont(name: "IBMPlexMono-Regular", size: size)! }

func eyebrow(_ label: String, x: CGFloat, top: CGFloat) {
    board.text(label, mono(17), grey, x: x, top: top, tracking: 3)
}

// Header
let headerMarkBox = CGRect(x: margin, y: 86, width: 56, height: 56)
drawSolidMark(board, placement: markPlacement(in: headerMarkBox),
              board: paletteLight.ink, paper: paletteLight.paper, accent: paletteLight.accent)
board.text("复盘了", semibold(46), ink, x: margin + 74, top: 84, tracking: 1)
board.text("PORTFOLIO REVIEW", mono(15), grey, x: margin + 76, top: 142, tracking: 3.4)
let versionWidth = board.measure("BRAND SYSTEM / V2", mono(16), tracking: 2.4).width
board.text("BRAND SYSTEM / V3", mono(16), grey, x: boardWidth - margin - versionWidth, top: 96, tracking: 2.4)
let dateWidth = board.measure("2026.10.26", mono(16), tracking: 2.4).width
board.text("2026.10.26", mono(16), grey, x: boardWidth - margin - dateWidth, top: 126, tracking: 2.4)
board.rect(margin, 206, boardWidth - margin * 2, 2, ink)

// Hero
let taglineWidth = board.text("每天，把持仓读清楚", medium(70), ink, x: margin, top: 262).width
board.rect(margin + taglineWidth + 18, 330, 18, 18, brandBlue)
board.text("复盘优先的 AI 持仓复盘。收盘总结、每周复盘，以及带依据的追问。",
           regular(28), ink, x: margin, top: 382)
board.text("V3：把「复盘」架起来 —— 一块白板，一条趋势，一句画成蓝线的结论。",
           regular(20), grey, x: margin, top: 436)

// Icon preview column
let iconPanel: CGFloat = 300
let iconX = boardWidth - margin - iconPanel
board.rect(iconX, 262, iconPanel, iconPanel, paletteLight.paper)
drawIconPreview(board, box: CGRect(x: iconX, y: 262, width: iconPanel, height: iconPanel),
                palette: paletteLight)
board.stroke(iconX, 262, iconPanel, iconPanel, lightGrey, width: 1)
board.text("APP ICON · FLAT PREVIEW", mono(14), grey, x: iconX, top: 580, tracking: 3)
board.text("图标以分层 Icon Composer 文档交付；\n此图为源色平面预览，非玻璃效果；\n实际渲染见 icon-renders/。",
           regular(14), grey, x: iconX, top: 604, lineSpacing: 5, maxWidth: iconPanel)
// size ladder
let ladder = [96.0, 56.0, 29.0]
var ladderX = iconX
let ladderBaseline: CGFloat = 802
for size in ladder {
    let y = ladderBaseline - size
    board.rect(ladderX, y, size, size, paletteLight.paper)
    drawIconPreview(board, box: CGRect(x: ladderX, y: y, width: size, height: size), palette: paletteLight)
    board.stroke(ladderX, y, size, size, lightGrey, width: 1)
    ladderX += size + 26
}
board.text("96 / 56 / 29 px", mono(14), grey, x: iconX, top: 812, tracking: 2)

// Naming block
board.text("命名 NAMING", mono(17), grey, x: margin, top: 540, tracking: 3)
board.text("从一次报告，到一份记录。", semibold(30), ink, x: margin, top: 576)
board.text("复盘，是用户已经会说的词；志，让每天的报告留下来、能回看。",
           regular(20), grey, x: margin, top: 626)
board.text("三个字，好念、好记，也不承诺收益。",
           regular(20), grey, x: margin, top: 660)

// BEFORE / AFTER
board.text("BEFORE", mono(13), grey, x: 1180, top: 540, tracking: 2.6)
board.rect(1180, 570, 90, 90, paperUI)
board.stroke(1180, 570, 90, 90, lightGrey)
let oldFont = mono(30)
let oldPieces: [(String, NSColor)] = [("P", ink), ("/", brandBlue), ("A", ink)]
let oldWidths = oldPieces.map { board.measure($0.0, oldFont).width }
var oldX = 1180 + (90 - oldWidths.reduce(0, +)) / 2
for (i, piece) in oldPieces.enumerated() {
    board.text(piece.0, oldFont, piece.1, x: oldX, top: 594)
    oldX += oldWidths[i]
}
board.text("→", regular(18), grey, x: 1284, top: 600)
board.text("AFTER", mono(13), grey, x: 1330, top: 540, tracking: 2.6)
board.rect(1330, 570, 90, 90, paletteLight.paper)
drawIconPreview(board, box: CGRect(x: 1330, y: 570, width: 90, height: 90), palette: paletteLight)
board.stroke(1330, 570, 90, 90, lightGrey)
board.text("从占位字母，到一块架起来给你看结论的白板。", regular(16), grey, x: 1180, top: 688)

// Divider
board.rect(margin, 840, boardWidth - margin * 2, 2, ink)

// Section 01: mark
eyebrow("01 / 标志 MARK", x: margin, top: 880)
let markBoxSize: CGFloat = 300
let sectionMarkBox = CGRect(x: margin, y: 940, width: markBoxSize, height: markBoxSize)
drawMark(board, placement: markPlacement(in: sectionMarkBox), palette: paletteLight)

// Element glyphs: each row shows one group only, drawn from the same geometry so the
// whiteboard vocabulary reads without leader lines.  Each glyph is a 26-unit-wide map of
// the mark box (frame + easel bounds), so all four align.
let glyphW: CGFloat = 26
let glyphScale = glyphW / geometry.markBounds.width
let glyphH = geometry.markBounds.height * glyphScale
func glyphPoint(_ x: CGFloat, _ top: CGFloat, _ p: CGPoint) -> CGPoint {
    CGPoint(x: x + (p.x - geometry.markBounds.minX) * glyphScale,
            y: top + (p.y - geometry.markBounds.minY) * glyphScale)
}
func glyphRect(_ x: CGFloat, _ top: CGFloat, _ r: CGRect) -> CGRect {
    let a = glyphPoint(x, top, CGPoint(x: r.minX, y: r.minY))
    return CGRect(x: a.x, y: a.y, width: r.width * glyphScale, height: r.height * glyphScale)
}
func glyphTile(_ x: CGFloat, _ top: CGFloat) {
    let boardRect = glyphRect(x, top, geometry.frame)
    board.roundedRect(boardRect.minX, boardRect.minY, boardRect.width, boardRect.height,
                      radius: geometry.frameRadius * glyphScale, paperUI)
    board.stroke(boardRect.minX, boardRect.minY, boardRect.width, boardRect.height, lightGrey, width: 1)
}
let glyphBoard: (CGFloat, CGFloat) -> Void = { x, top in
    glyphTile(x, top)
    let f = glyphRect(x, top, geometry.frame)
    board.roundedRect(f.minX, f.minY, f.width, f.height, radius: geometry.frameRadius * glyphScale, paletteLight.frame)
    let s = glyphRect(x, top, geometry.surface)
    board.roundedRect(s.minX, s.minY, s.width, s.height, radius: geometry.surfaceRadius * glyphScale, paletteLight.surface)
}
let glyphHardware: (CGFloat, CGFloat) -> Void = { x, top in
    glyphTile(x, top)
    for leg in geometry.legs {
        board.polyline(leg.map { glyphPoint(x, top, $0) },
                       lineWidth: geometry.legWidth * glyphScale, paletteLight.hardware)
    }
}
let glyphInk: (CGFloat, CGFloat) -> Void = { x, top in
    glyphTile(x, top)
    board.polyline(geometry.trend.map { glyphPoint(x, top, $0) },
                   lineWidth: geometry.trendWidth * glyphScale, paletteLight.ink)
    board.polyline(geometry.arrow.map { glyphPoint(x, top, $0) },
                   lineWidth: geometry.arrowWidth * glyphScale, paletteLight.ink)
    for rule in geometry.analysisRules {
        let r = glyphRect(x, top, rule)
        board.roundedRect(r.minX, r.minY, r.width, r.height, radius: geometry.ruleRadius * glyphScale, paletteLight.ink)
    }
}
let glyphConclusion: (CGFloat, CGFloat) -> Void = { x, top in
    glyphTile(x, top)
    let r = glyphRect(x, top, geometry.conclusionRule)
    board.roundedRect(r.minX, r.minY, r.width, r.height, radius: geometry.ruleRadius * glyphScale, paletteLight.accent)
}

let textX: CGFloat = 548
let glyphX: CGFloat = 500
let rows: [(CGFloat, (CGFloat, CGFloat) -> Void, String, String)] = [
    (954, glyphBoard, "白板 BOARD", "书写面 + 浅蓝边框；边框把它从「卡片」变成「板」。"),
    (1040, glyphHardware, "硬件 HARDWARE", "交叉画架腿：板是被架起来给人看的；顶部就是板沿。"),
    (1126, glyphInk, "墨线 INK", "趋势线带一个向上的箭头，旁边两条分析横线。"),
    (1212, glyphConclusion, "结论 CONCLUSION", "一条粉笔蓝的结论横线 —— V1 的「蓝 = 结论」回到一条线。"),
]
for (rowY, glyph, title, note) in rows {
    glyph(glyphX, rowY - 2)
    board.text(title, mono(15), ink, x: textX, top: rowY, tracking: 2)
    board.text(note, regular(18), grey, x: textX, top: rowY + 28)
}

// concept statement under the mark
board.text("白板是读的地方，画架是讲的方式。", semibold(30), ink, x: margin, top: 1290)
board.text("V1 三行账目 + 一条蓝合计线；V2 黑板 + 圈注；V3 白板 + 画架 + 一条蓝结论线 —— 同一句「蓝 = 结论」。",
           regular(20), grey, x: margin, top: 1338)
board.text("趋势与分析是过程，蓝线是结果。四组五层（Board / Hardware / Ink / Conclusion）分开交付，效果交给系统。",
           regular(20), grey, x: margin, top: 1372)

// Section 02: lockups
let lockX: CGFloat = 1240
let lockW: CGFloat = 1040
eyebrow("02 / 组合 LOCKUP", x: lockX, top: 880)

func boardLockup(x: CGFloat, top: CGFloat, dark: Bool) {
    board.rect(x, top, lockW, 160, dark ? ink : paletteLight.paper)
    board.stroke(x, top, lockW, 160, dark ? ink : lightGrey, width: 1)
    let mb = CGRect(x: x + 36, y: top + 40, width: 80, height: 80)
    let material = dark ? paletteDark : paletteLight
    drawMark(board, placement: markPlacement(in: mb), palette: material)
    board.text("复盘了", semibold(48), dark ? paperUI : ink, x: x + 150, top: top + 28, tracking: -1)
    board.text("PORTFOLIO REVIEW", mono(13), dark ? NSColor(srgbRed: 0.72, green: 0.72, blue: 0.72, alpha: 1) : grey,
               x: x + 153, top: top + 96, tracking: 2.6)
}
boardLockup(x: lockX, top: 940, dark: false)
boardLockup(x: lockX, top: 1120, dark: true)
board.text("浅色物料用 Default 色板；深色物料用 Dark 色板（书写面转暗米、硬件转浅暖灰），字标转白。",
           regular(18), grey, x: lockX, top: 1302)

// Divider
board.rect(margin, 1420, boardWidth - margin * 2, 2, ink)

// Section 03: UI core palette
eyebrow("03 / 界面色 UI COLOUR", x: margin, top: 1460)
let swatches: [(NSColor, String, String)] = [
    (ink, "#000000", "结构"),
    (paperUI, "#FFFFFF", "底色"),
    (brandBlue, "#0000FF", "强调 / 链接"),
    (grey, "#666666", "次级"),
    (green, "#00AA00", "涨"),
    (red, "#CC0000", "跌"),
]
for (i, item) in swatches.enumerated() {
    let x = margin + CGFloat(i) * 160
    board.rect(x, 1504, 132, 132, item.0)
    board.stroke(x, 1504, 132, 132, lightGrey, width: 1)
    board.text(item.1, mono(13), ink, x: x, top: 1648, tracking: 1)
    board.text(item.2, regular(16), grey, x: x, top: 1674)
}

// Section 04: type
let typeX: CGFloat = 1240
eyebrow("04 / 字体 TYPE", x: typeX, top: 1460)
board.text("SONGTI SC REGULAR · 字标", mono(13), grey, x: typeX, top: 1504, tracking: 2.2)
board.text("复盘了", songti(56), ink, x: typeX, top: 1528, tracking: 3)
board.text("IBM PLEX MONO MEDIUM", mono(13), grey, x: typeX, top: 1602, tracking: 2.2)
board.text("PORTFOLIO REVIEW 08:00", mono(24), ink, x: typeX, top: 1628, tracking: 1.6)
board.text("字标用 Songti SC（宋体），界面中文用 PingFang SC，英文与数字用 IBM Plex Mono；标签全大写、宽字距。",
           regular(17), grey, x: typeX, top: 1678)

// Divider
board.rect(margin, 1730, boardWidth - margin * 2, 2, ink)

// Section 05: icon appearance palette
eyebrow("05 / 图标外观 ICON APPEARANCE", x: margin, top: 1770)
board.text("三种源色（light / dark / tinted），六种外观由系统合成；画框用系统渐变，其余纯色，不烘焙效果。",
           regular(18), grey, x: 760, top: 1772)

// three authored palette cards (the only hex values the design owns)
let cardW: CGFloat = 340
let cardH: CGFloat = 188
let cardGap: CGFloat = 24
for (i, palette) in authoredPalettes.enumerated() {
    let x = margin + CGFloat(i) * (cardW + cardGap)
    let top: CGFloat = 1816
    board.rect(x, top, cardW, cardH, paperUI)
    board.stroke(x, top, cardW, cardH, lightGrey, width: 1)
    let mini = CGRect(x: x + 14, y: top + 14, width: 148, height: 148)
    drawIconPreview(board, box: mini, palette: palette)
    board.stroke(mini.minX, mini.minY, mini.width, mini.height, lightGrey, width: 1)
    board.text(palette.label, mono(11), ink, x: x + 176, top: top + 14, tracking: 1.2)
    board.text(palette.note, regular(12), grey, x: x + 176, top: top + 32)
    let hexRows: [(String, NSColor)] = [("纸", palette.paper), ("面", palette.surface), ("框", palette.frame),
                                        ("墨", palette.ink), ("硬", palette.hardware), ("蓝", palette.accent)]
    for (j, row) in hexRows.enumerated() {
        board.text("\(row.0) \(rgbHex(row.1))", mono(10), grey, x: x + 176, top: top + 52 + CGFloat(j) * 20, tracking: 0)
    }
}

// six renditions: source bucket + what the system adds. No Clear-specific hex exists.
let tableX: CGFloat = 1240
board.text("六种外观 RENDITIONS", mono(12), ink, x: tableX, top: 1800, tracking: 2)
board.text("外观", mono(11), grey, x: tableX, top: 1832, tracking: 1.6)
board.text("源色", mono(11), grey, x: tableX + 220, top: 1832, tracking: 1.6)
board.text("系统叠加", mono(11), grey, x: tableX + 360, top: 1832, tracking: 1.6)
for (i, rendition) in renditions.enumerated() {
    let y = 1858 + CGFloat(i) * 26
    board.text(rendition.name, mono(13), ink, x: tableX, top: y, tracking: 0.4)
    board.text(rendition.bucket, mono(12), grey, x: tableX + 220, top: y + 1)
    board.text(rendition.system, regular(14), grey, x: tableX + 360, top: y)
}
board.text("实际渲染：docs/brand/assets/icon-renders/icon-renditions-1024.png",
           regular(15), grey, x: tableX, top: 2022)
board.text("ClearLight / ClearDark 由系统单色生成，Tinted 叠加系统取色；图标本身无烘焙高光、阴影或模糊。",
           regular(15), grey, x: margin, top: 2046)

// Footer
board.rect(margin, 2092, boardWidth - margin * 2, 1, lightGrey)
board.text("复盘了 · BRAND SYSTEM V3", mono(15), grey, x: margin, top: 2108, tracking: 2.4)
let footer = "每天，把持仓读清楚。"
let footerWidth = NSAttributedString(string: footer, attributes: [.font: regular(15)]).size().width
board.text(footer, regular(15), grey, x: boardWidth - margin - footerWidth, top: 2108)

try write(board, brandAssets.appendingPathComponent("brand-board.png"), label: "brand board")

print("done")
