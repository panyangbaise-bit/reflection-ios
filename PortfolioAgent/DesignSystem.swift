import SwiftUI

enum Palette {
    static let blue = Color.blue
    static let green = Color(red: 0, green: 0.66, blue: 0)
    static let red = Color(red: 0.8, green: 0, blue: 0)
    static let secondary = Color.secondary
    static let line = Color(uiColor: .separator)
    static let series: [Color] = [.primary, blue, Color(white: 0.4), Color(red: 0.545, green: 0.361, blue: 0.965), Color(red: 1, green: 0.667, blue: 0)]
    // Icon-derived tokens (light bucket). Mirror docs/brand/icon/palette.json.
    // UI accent stays #0000FF; these are only for the mark and the icon.
    static let ink = Color(red: 20.0 / 255, green: 24.0 / 255, blue: 29.0 / 255)   // #14181D
    static let paper = Color(red: 242.0 / 255, green: 238.0 / 255, blue: 228.0 / 255)   // #F2EEE4
    static let surface = Color(red: 251.0 / 255, green: 250.0 / 255, blue: 244.0 / 255)   // #FBFAF4
    static let frame = Color(red: 201.0 / 255, green: 211.0 / 255, blue: 238.0 / 255)   // #C9D3EE
    static let hardware = Color(red: 20.0 / 255, green: 24.0 / 255, blue: 29.0 / 255)   // #14181D
    static let chalkBlue = Color(red: 61.0 / 255, green: 107.0 / 255, blue: 255.0 / 255)   // #3D6BFF
    static let chalkBlueOnDark = Color(red: 143.0 / 255, green: 166.0 / 255, blue: 255.0 / 255)   // #8FA6FF
    static func mono(_ size: CGFloat = 14, medium: Bool = false) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size, relativeTo: .body)
    }
    /// 中文界面字体：正文用系统 PingFang SC。
    static func han(_ size: CGFloat, semibold: Bool = false) -> Font {
        .system(size: size, weight: semibold ? .semibold : .regular)
    }
    /// 字标使用系统加粗黑体，和导航标题保持一致。
    static func wordmark(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }
}

/// 复盘了 mark: a whiteboard on an easel — light-blue frame, writing surface, crossed
/// easel legs, the day's trend line with an up-arrow, two analysis rules, and the
/// chalk-blue conclusion rule. Mirrors the four icon groups (Conclusion over Ink over
/// Hardware over Board).
/// Geometry mirrors docs/brand/icon/layers/*.svg and scripts/render-brand-assets.swift;
/// change all three together (icon sources, brand assets, in-app mark).
struct BrandMark: View {
    enum Style {
        /// In-app default: one ink silhouette with the chart knocked out in the page colour.
        /// At 14pt the 26-unit frame would be sub-pixel, so the silhouette is intentionally solid.
        case solid
        /// Optional enlarged version (22pt+): the full whiteboard — surface, light-blue frame,
        /// ink chart, ink hardware.
        case whiteboard
    }

    var color: Color = Palette.ink        // silhouette ink (solid style)
    var accent: Color = Palette.chalkBlue // conclusion rule
    var paper: Color = Palette.paper      // knock-out colour of the chart (solid style)
    var style: Style = .solid

    // Unit coordinates = the 1024pt icon canvas (top-left origin, same as the layer SVGs).
    private static let boardHue = Palette.frame
    private static let surfaceHue = Palette.surface
    private static let hardwareHue = Palette.hardware
    private static let frame = CGRect(x: 80, y: 100, width: 864, height: 636)
    private static let frameRadius: CGFloat = 30
    private static let surface = CGRect(x: 106, y: 126, width: 812, height: 584)
    private static let surfaceRadius: CGFloat = 4
    private static let legs = [
        [CGPoint(x: 412, y: 748), CGPoint(x: 846, y: 936)],
[CGPoint(x: 632, y: 748), CGPoint(x: 178, y: 936)]
    ]
    private static let legWidth: CGFloat = 48
    private static let trend = [CGPoint(x: 150, y: 612), CGPoint(x: 270, y: 480), CGPoint(x: 350, y: 548), CGPoint(x: 684, y: 300)]
    private static let trendWidth: CGFloat = 32
    private static let arrow = [CGPoint(x: 653.8, y: 369.7), CGPoint(x: 684, y: 300), CGPoint(x: 608.5, y: 308.7)]
    private static let arrowWidth: CGFloat = 32
    private static let analysisRules = [
        CGRect(x: 636, y: 545, width: 164, height: 28),
        CGRect(x: 636, y: 620, width: 104, height: 28)
    ]
    private static let ruleRadius: CGFloat = 14
    private static let conclusionRule = CGRect(x: 636, y: 470, width: 234, height: 28)
    private static let markBounds = CGRect(x: 80, y: 100, width: 864, height: 860)

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            // The mark box is whiteboard + easel, never the icon canvas: the paper margin
            // is an app-icon thing and never enters the in-app mark.
            let bounds = Self.markBounds
            let scale = side / max(bounds.width, bounds.height)
            let center = CGPoint(x: (size.width - side) / 2 + side / 2,
                                 y: (size.height - side) / 2 + side / 2)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: center.x + (x - bounds.midX) * scale,
                        y: center.y + (y - bounds.midY) * scale)
            }
            func rounded(_ r: CGRect, radius: CGFloat) -> Path {
                let a = point(r.minX, r.minY), b = point(r.maxX, r.maxY)
                return Path(roundedRect: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y),
                            cornerRadius: radius * scale)
            }
            func stroke(_ pts: [CGPoint], _ width: CGFloat, _ color: Color) {
                guard pts.count > 1 else { return }
                var path = Path()
                let mapped = pts.map { point($0.x, $0.y) }
                path.move(to: mapped[0])
                for p in mapped.dropFirst() { path.addLine(to: p) }
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
            }
            func paint(_ r: CGRect, radius: CGFloat, _ color: Color) {
                context.fill(rounded(r, radius: radius), with: .color(color))
            }

            let boardFill: Color
            let surfaceFill: Color?
            let chartInk: Color
            let hardwareFill: Color
            switch style {
            case .solid:
                boardFill = color
                surfaceFill = nil            // frame + surface read as one slab
                chartInk = paper             // chart is knocked out of the slab
                hardwareFill = color
            case .whiteboard:
                boardFill = Self.boardHue
                surfaceFill = Self.surfaceHue
                chartInk = Palette.ink
                hardwareFill = Self.hardwareHue
            }

            // Board group: frame, then the writing surface on top.
            paint(Self.frame, radius: Self.frameRadius, boardFill)
            if let surfaceFill { paint(Self.surface, radius: Self.surfaceRadius, surfaceFill) }
            // Hardware group: the two crossed easel legs.
            for leg in Self.legs { stroke(leg, Self.legWidth, hardwareFill) }
            // Ink group: trend line, arrow head, two analysis rules.
            stroke(Self.trend, Self.trendWidth, chartInk)
            stroke(Self.arrow, Self.arrowWidth, chartInk)
            for rule in Self.analysisRules { paint(rule, radius: Self.ruleRadius, chartInk) }
            // Conclusion group: the chalk-blue rule.
            paint(Self.conclusionRule, radius: Self.ruleRadius, accent)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A compact robot with antenna, rounded head, eyes and smile.
struct AgentMark: View {
    var color: Color = .primary

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 28
            context.scaleBy(x: scale, y: scale)
            let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            context.stroke(Path(roundedRect: CGRect(x: 5, y: 8, width: 18, height: 16), cornerRadius: 5), with: .color(color), style: stroke)
            var antenna = Path(); antenna.move(to: CGPoint(x: 14, y: 8)); antenna.addLine(to: CGPoint(x: 14, y: 4))
            context.stroke(antenna, with: .color(color), style: stroke)
            context.fill(Path(ellipseIn: CGRect(x: 12, y: 1, width: 4, height: 4)), with: .color(color))
            for x in [9.0, 16.0] {
                context.fill(Path(roundedRect: CGRect(x: x, y: 13, width: 3, height: 4), cornerRadius: 1.5), with: .color(color))
            }
            var smile = Path(); smile.move(to: CGPoint(x: 11, y: 20)); smile.addQuadCurve(to: CGPoint(x: 17, y: 20), control: CGPoint(x: 14, y: 22))
            context.stroke(smile, with: .color(color), style: stroke)
            for x in [2.0, 26.0] {
                var ear = Path(); ear.move(to: CGPoint(x: x, y: 13)); ear.addLine(to: CGPoint(x: x, y: 18))
                context.stroke(ear, with: .color(color), style: stroke)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct SquareButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(primary ? Color(uiColor: .systemBackground) : Color.primary)
            .background(primary ? Color.primary : Color(uiColor: .systemBackground))
            .overlay(Rectangle().stroke(Color.primary, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
struct Panel<Content: View>: View {
    var heavy = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color(uiColor: .systemBackground)).overlay(Rectangle().stroke(Color.primary, lineWidth: heavy ? 2 : 1))
    }
}
struct Screen<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24, content: content).padding(20).frame(maxWidth: 640) }
            .background(Color(uiColor: .systemBackground)).scrollDismissesKeyboard(.interactively)
    }
}
struct PageTitle: View {
    let title: String
    var eyebrow = "PORTFOLIO REVIEW"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(Palette.mono(11)).foregroundStyle(Palette.secondary)
            Text(title).font(.system(size: 27, weight: .bold)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
struct Note: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true) }
}
struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: { Label("返回", systemImage: "chevron.left").frame(minHeight: 44) }
            .font(.system(size: 14)).foregroundStyle(Palette.blue)
    }
}
struct DetailScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { Screen { BackButton(); content() }.toolbar(.hidden, for: .navigationBar) }
}
struct ValueRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            Spacer(minLength: 10)
            Text(value).font(Palette.mono(14)).multilineTextAlignment(.trailing)
        }
    }
}
struct FormField: View {
    let title: String
    @Binding var value: String
    var numeric = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            TextField(title, text: $value).font(.system(size: 16))
                .keyboardType(numeric ? .decimalPad : .default).padding(13)
                .overlay(Rectangle().stroke(Color.primary, lineWidth: 1))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
}
struct SettingLink: View {
    let title: String
    var subtitle: String = ""
    let route: Route
    var body: some View {
        NavigationLink(value: route) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 15))
                    if !subtitle.isEmpty { Note(text: subtitle) }
                }
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 12))
            }.foregroundStyle(.primary).frame(minHeight: 48)
        }.buttonStyle(.plain)
    }
}

/// Native Liquid Glass on iOS 26+, with an adaptive material fallback.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 26
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

struct GlassActionButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .modifier(GlassCard(cornerRadius: 27))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
