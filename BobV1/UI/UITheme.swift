import SwiftUI

// MARK: - Palette

extension Color {
    /// "#RRGGBB" hex.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt32(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255, opacity: 1)
    }
}

/// Cosy peach/cream palette matching RoomTheme's default tint (0.96, 0.78, 0.66).
enum UITheme {
    static let peach = Color(.sRGB, red: 0.96, green: 0.78, blue: 0.66)
    static let cream = Color(.sRGB, red: 1.0, green: 0.95, blue: 0.89)
    static let panel = Color(.sRGB, red: 1.0, green: 0.93, blue: 0.85)
    static let panelDeep = Color(.sRGB, red: 0.96, green: 0.84, blue: 0.72)
    static let ink = Color(.sRGB, red: 0.40, green: 0.24, blue: 0.20)
    static let inkSoft = Color(.sRGB, red: 0.40, green: 0.24, blue: 0.20).opacity(0.65)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.68)

    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func caption(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .medium, design: .rounded) }
}

extension BreedID {
    var core: Color { Color(hex: spec.colorHexCore) }
    var light: Color { Color(hex: spec.colorHexLight) }
    var deep: Color { Color(hex: spec.colorHexDeep) }
    var featureDescription: String {
        switch spec.feature {
        case .none: return "Smooth and squishy all over"
        case .dorsalSpikes: return "Soft spikes down its back"
        case .curlyAntenna: return "A bouncy curly antenna"
        }
    }
}

extension Marking {
    var displayName: String {
        switch self {
        case .none: return "Plain"
        case .spotOnHead: return "Head spot"
        case .starOnHead: return "Star"
        case .heartOnCheek: return "Heart cheek"
        case .freckles: return "Freckles"
        case .spotOnBack: return "Back spot"
        case .whiteBelly: return "Pale belly"
        }
    }
}

// MARK: - Panels

struct SoftPanel: ViewModifier {
    var radius: CGFloat = 26
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [UITheme.cream, UITheme.panel], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                    .shadow(color: UITheme.ink.opacity(0.18), radius: 14, y: 6)
            )
    }
}

extension View {
    func softPanel(radius: CGFloat = 26) -> some View { modifier(SoftPanel(radius: radius)) }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = UITheme.ink
    var filled = true
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(UITheme.body(compact ? 14 : 17))
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(filled ? Color.white : tint)
            .padding(.horizontal, compact ? 12 : 22).padding(.vertical, compact ? 9 : 13)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.14)))
            .shadow(color: tint.opacity(filled ? 0.35 : 0), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(UITheme.spring, value: configuration.isPressed)
    }
}

// MARK: - Placeholder blob (SwiftUI-drawn; used by the kennel and previews)

struct BlobPlaceholder: View {
    var breed: BreedID
    var look: BlobLook = BlobLook()
    var mood: Mood? = nil

    var body: some View {
        let colors = look.colors(for: breed)
        let core = Color(hex: colors.core), light = Color(hex: colors.light), deep = Color(hex: colors.deep)
        let p = breed.spec.proportions
        let scale = CGFloat(look.sizeScale)
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let w = s * 0.78 * CGFloat(p.widthScale) * scale
            let h = s * 0.74 * CGFloat(p.heightScale) * scale
            ZStack {
                // ground shadow
                Ellipse().fill(.black.opacity(0.14)).frame(width: w * 0.9, height: h * 0.14)
                    .offset(y: s * 0.40)
                // feature behind/over body
                featureBack(w: w, h: h, core: core, deep: deep)
                // body
                RoundedRectangle(cornerRadius: w * 0.46, style: .continuous)
                    .fill(RadialGradient(colors: [light, core, deep], center: .init(x: 0.35, y: 0.25),
                                         startRadius: 2, endRadius: max(w, h) * 0.9))
                    .frame(width: w, height: h)
                    .overlay(marking(w: w, h: h))
                    .overlay(alignment: .topLeading) {
                        Capsule().fill(.white.opacity(0.45)).frame(width: w * 0.2, height: h * 0.09)
                            .rotationEffect(.degrees(-30)).offset(x: w * 0.16, y: h * 0.12)
                    }
                    .overlay(face(w: w, h: h))
                featureFront(w: w, h: h, light: light, deep: deep)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func face(w: CGFloat, h: CGFloat) -> some View {
        let eye = w * 0.075
        return ZStack {
            HStack(spacing: w * 0.24) {
                Circle().fill(UITheme.ink).frame(width: eye, height: eye * 1.25)
                Circle().fill(UITheme.ink).frame(width: eye, height: eye * 1.25)
            }
            .offset(y: -h * 0.02)
            SmileShape(happy: mood != .glum).stroke(UITheme.ink, style: .init(lineWidth: max(2, w * 0.018), lineCap: .round))
                .frame(width: w * 0.16, height: h * 0.06).offset(y: h * 0.1)
        }
    }

    @ViewBuilder private func marking(w: CGFloat, h: CGFloat) -> some View {
        let m = Color.white.opacity(0.7)
        switch look.marking {
        case .none: EmptyView()
        case .spotOnHead:
            Circle().fill(m).frame(width: w * 0.2).offset(x: w * 0.12, y: -h * 0.3)
        case .starOnHead:
            Image(systemName: "star.fill").font(.system(size: w * 0.18)).foregroundStyle(m).offset(y: -h * 0.3)
        case .heartOnCheek:
            Image(systemName: "heart.fill").font(.system(size: w * 0.12)).foregroundStyle(.pink.opacity(0.7))
                .offset(x: w * 0.27, y: h * 0.1)
        case .freckles:
            ForEach(0..<5, id: \.self) { i in
                Circle().fill(UITheme.ink.opacity(0.4)).frame(width: w * 0.03)
                    .offset(x: w * (0.16 + 0.05 * CGFloat(i % 3)) * (i % 2 == 0 ? 1 : -1) , y: h * (0.05 + 0.03 * CGFloat(i % 2)))
            }
        case .spotOnBack:
            Ellipse().fill(m).frame(width: w * 0.22, height: h * 0.16).offset(x: -w * 0.22, y: h * 0.18)
        case .whiteBelly:
            Ellipse().fill(m.opacity(0.55)).frame(width: w * 0.5, height: h * 0.34).offset(y: h * 0.28)
        }
    }

    @ViewBuilder private func featureBack(w: CGFloat, h: CGFloat, core: Color, deep: Color) -> some View {
        if breed.spec.feature == .dorsalSpikes {
            let n = max(look.featureCount, 5)
            let sz = w * 0.11 * CGFloat(look.featureScale)
            HStack(spacing: -sz * 0.1) {
                ForEach(0..<n, id: \.self) { _ in
                    Triangle().fill(deep).frame(width: sz, height: sz * 1.3)
                }
            }
            .frame(width: w * 0.8).offset(y: -h * 0.5 - sz * 0.35 + h * 0.04)
        }
    }

    @ViewBuilder private func featureFront(w: CGFloat, h: CGFloat, light: Color, deep: Color) -> some View {
        if breed.spec.feature == .curlyAntenna {
            let n = min(2, max(1, look.featureCount))
            let k = CGFloat(look.featureScale)
            HStack(spacing: w * 0.18) {
                ForEach(0..<n, id: \.self) { _ in
                    VStack(spacing: -2) {
                        Circle().fill(light).overlay(Circle().strokeBorder(deep, lineWidth: 1.5))
                            .frame(width: w * 0.12 * k, height: w * 0.12 * k)
                        CurlShape().stroke(deep, style: .init(lineWidth: max(2.5, w * 0.025), lineCap: .round))
                            .frame(width: w * 0.16 * k, height: h * 0.26 * k)
                    }
                }
            }
            .offset(y: -h * 0.5 - h * 0.1 * k)
        }
    }
}

private struct CurlShape: SwiftUI.Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.midX, y: r.maxY))
        p.addCurve(to: .init(x: r.midX, y: r.midY), control1: .init(x: r.minX - r.width * 0.3, y: r.maxY * 0.8),
                   control2: .init(x: r.maxX + r.width * 0.5, y: r.midY + r.height * 0.1))
        p.addCurve(to: .init(x: r.midX, y: r.minY + r.height * 0.1), control1: .init(x: r.minX - r.width * 0.4, y: r.midY * 0.9),
                   control2: .init(x: r.maxX + r.width * 0.3, y: r.minY))
        return p
    }
}

private struct Triangle: SwiftUI.Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.midX, y: r.minY))
        p.addQuadCurve(to: .init(x: r.maxX, y: r.maxY), control: .init(x: r.midX + r.width * 0.2, y: r.midY))
        p.addLine(to: .init(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: .init(x: r.midX, y: r.minY), control: .init(x: r.midX - r.width * 0.2, y: r.midY))
        return p
    }
}

private struct SmileShape: SwiftUI.Shape {
    var happy: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.minX, y: happy ? r.minY : r.maxY))
        p.addQuadCurve(to: .init(x: r.maxX, y: happy ? r.minY : r.maxY),
                       control: .init(x: r.midX, y: happy ? r.maxY * 1.8 : r.minY - r.height * 0.8))
        return p
    }
}

/// Plain peach backdrop used as the stage in previews/snapshots.
struct HUDPlaceholderStage: View {
    var store: GameStore? = nil
    var body: some View {
        ZStack {
            LinearGradient(colors: [UITheme.peach.opacity(0.9), UITheme.peach], startPoint: .top, endPoint: .bottom)
            VStack {
                Spacer()
                Rectangle().fill(UITheme.panelDeep).frame(height: 260)
            }
            if let b = store?.blobs.first {
                BlobPlaceholder(breed: b.breed, look: b.look, mood: b.mood).frame(width: 220).offset(y: 80)
            }
        }
        .ignoresSafeArea()
    }
}
