//
//  CloudTheme.swift
//  "Cloud Jelly": the blue-on-white look of the start screens (intro, loading, main menu, pause/settings). Colours, the two jelly button
//  styles (primary = blue jelly, secondary = white, both with a thick Jelly rim and a drop lip), the white rimmed card, and drifting Mist bubbles.
//

import SwiftUI

enum CloudTheme {
    static let sky = Color.white
    static let mist = Color(.sRGB, red: 0xEE / 255, green: 0xF5 / 255, blue: 0xFB / 255)
    static let jelly = Color(.sRGB, red: 0x8D / 255, green: 0xB8 / 255, blue: 0xE0 / 255)
    static let deepJelly = Color(.sRGB, red: 0x4F / 255, green: 0x8B / 255, blue: 0xC6 / 255)
    static let jellyLight = Color(.sRGB, red: 0x69 / 255, green: 0xA1 / 255, blue: 0xD6 / 255)
    static let ink = Color(.sRGB, red: 0x22 / 255, green: 0x40 / 255, blue: 0x5E / 255)
    static let blush = Color(.sRGB, red: 0xF6 / 255, green: 0xAF / 255, blue: 0xC0 / 255)
    static let lipPrimary = Color(.sRGB, red: 0x7B / 255, green: 0xA8 / 255, blue: 0xD2 / 255)
    static let lipSecondary = Color(.sRGB, red: 0xCF / 255, green: 0xE1 / 255, blue: 0xF2 / 255)
    static let caption = Color(.sRGB, red: 0x4A / 255, green: 0x6A / 255, blue: 0x89 / 255)          // about 5.5:1 on white (was 3.4:1)

    /// Primary-button gradient ends: white text on them is 4.5:1 or better (the lighter jelly tones were about 2.7:1).
    static let buttonTop = Color(.sRGB, red: 0x3F / 255, green: 0x7A / 255, blue: 0xB8 / 255)
    static let buttonBottom = Color(.sRGB, red: 0x2C / 255, green: 0x66 / 255, blue: 0xA2 / 255)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { JFont.scaled(size, weight) }

    static var reduceMotion: Bool { A11ySettings.shared.reduceMotion }
}

/// Blue jelly pill (primary) or white pill (secondary) with a thick rim and a drop lip; pressing moves it down 3 pt with a small squish.
struct JellyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary
    /// Text size; nil = 24 for primary, 20 for secondary.
    var size: CGFloat?
    var minHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    init(_ kind: Kind = .primary, size: CGFloat? = nil, minHeight: CGFloat? = nil) { self.kind = kind; self.size = size; self.minHeight = minHeight }

    func makeBody(configuration: Configuration) -> some View {
        let p = configuration.isPressed
        let primary = kind == .primary
        let still = reduceMotion || CloudTheme.reduceMotion
        let lip: CGFloat = p ? 3 : 6
        configuration.label
            .font(CloudTheme.font(size ?? (primary ? 24 : 20), .bold))
            .foregroundStyle(primary ? Color.white : CloudTheme.ink)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: minHeight ?? (primary ? 56 : 48))
            .padding(.horizontal, 10)
            .background {
                let shape = Capsule()
                ZStack {
                    shape.fill(primary ? CloudTheme.lipPrimary : CloudTheme.lipSecondary).padding(-4).offset(y: lip)
                    shape.fill(CloudTheme.jelly).padding(-4)
                    if primary { shape.fill(LinearGradient(colors: [CloudTheme.buttonTop, CloudTheme.buttonBottom], startPoint: .top, endPoint: .bottom)) }
                    else { shape.fill(Color.white) }
                    if primary {
                        shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25)), lineWidth: 3)
                    }
                }
            }
            .padding(.horizontal, 4).padding(.bottom, 6)          // room for the rim and the lip inside the layout
            .contentShape(Rectangle())
            .scaleEffect(x: p && !still ? 1.03 : 1, y: p && !still ? 0.96 : 1, anchor: .bottom)
            .offset(y: p ? 3 : 0)
            .opacity(enabled ? 1 : 0.6)
            .animation(still ? .easeOut(duration: 0.1) : .spring(response: 0.25, dampingFraction: 0.55), value: p)
    }
}

extension ButtonStyle where Self == JellyButtonStyle {
    static var jellyPrimary: JellyButtonStyle { JellyButtonStyle(.primary) }
    static var jellySecondary: JellyButtonStyle { JellyButtonStyle(.secondary) }
}

/// The white card with the thick Jelly rim (menus, sheets, confirm).
struct CloudCard: ViewModifier {
    var radius: CGFloat = 26
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white)
                .shadow(color: CloudTheme.ink.opacity(0.18), radius: 14, y: 6))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(CloudTheme.jelly, lineWidth: 4))
    }
}
extension View { func cloudCard(radius: CGFloat = 26) -> some View { modifier(CloudCard(radius: radius)) } }

/// One Jelbie body pose in unit space (body 1 wide, faceless): squash, tilt, arm angles (0 = hanging, positive = outward/up), feet.
private struct JelbiePose {
    var sx = 1.0, sy = 1.0, rot = 0.0, aL = 0.25, aR = 0.25, fx = 0.2, fy = 0.0, fs = 1.0
    static let stand = JelbiePose()
    static let wave = JelbiePose(rot: -0.04, aL: 0.25, aR: 2.6)
    static let hop = JelbiePose(sx: 0.92, sy: 1.1, aL: 1.9, aR: 1.9, fx: 0.15, fy: -0.14)
    static let squish = JelbiePose(sx: 1.2, sy: 0.84, aL: 1.2, aR: 1.2, fx: 0.3, fy: 0.02)
    static let sit = JelbiePose(sx: 1.06, sy: 0.92, aL: 0.5, aR: 0.5, fx: 0.3, fy: -0.04, fs: 1.25)
    static let lean = JelbiePose(rot: 0.38, aL: 0.9, aR: 0.1, fx: 0.22)
    static let sleep = JelbiePose(sx: 1.04, sy: 0.96, rot: 1.45, aL: 0.15, aR: 0.15, fx: 0.18)
    static let cartwheel = JelbiePose(rot: -0.95, aL: 2.9, aR: 2.9, fx: 0.3, fy: -0.06)
    func mixed(_ o: JelbiePose, _ m: Double) -> JelbiePose {
        func l(_ a: Double, _ b: Double) -> Double { a + (b - a) * m }
        return JelbiePose(sx: l(sx, o.sx), sy: l(sy, o.sy), rot: l(rot, o.rot), aL: l(aL, o.aL), aR: l(aR, o.aR), fx: l(fx, o.fx), fy: l(fy, o.fy), fs: l(fs, o.fs))
    }
}

/// White sky with slow faceless Jelbie silhouettes in Mist tints: each drifts (20-40 s loops), breathes jelly-like
/// (wider while shorter), sways, and morphs between two poses. One Canvas; still (pose A) when Reduce Motion is on.
struct CloudSky: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true
    private struct Shape { let x, y, size, ax, ay, per, ph: Double; let a, b: JelbiePose }
    private static let shapes: [Shape] = [
        Shape(x: 0.06, y: 0.16, size: 0.34, ax: 0.07, ay: 0.05, per: 31, ph: 0.0, a: .stand, b: .wave),
        Shape(x: 0.97, y: 0.34, size: 0.22, ax: 0.06, ay: 0.06, per: 23, ph: 1.7, a: .hop, b: .squish),
        Shape(x: 0.52, y: 1.02, size: 0.42, ax: 0.09, ay: 0.04, per: 37, ph: 3.1, a: .sit, b: .lean),
        Shape(x: 0.14, y: 0.64, size: 0.17, ax: 0.10, ay: 0.07, per: 27, ph: 4.4, a: .sleep, b: .stand),
        Shape(x: 0.88, y: 0.76, size: 0.26, ax: 0.07, ay: 0.06, per: 33, ph: 2.3, a: .cartwheel, b: .lean),
        Shape(x: 0.60, y: 0.02, size: 0.20, ax: 0.08, ay: 0.04, per: 29, ph: 5.2, a: .squish, b: .wave),
    ]
    private static let mist = (r: 0xEE / 255.0, g: 0xF5 / 255.0, b: 0xFB / 255.0)
    private static let deep = (r: 0xD6 / 255.0, g: 0xE8 / 255.0, b: 0xF7 / 255.0)
    private static let body: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -0.575))
        p.addCurve(to: CGPoint(x: 0.5, y: 0.12), control1: CGPoint(x: 0.32, y: -0.575), control2: CGPoint(x: 0.5, y: -0.26))
        p.addCurve(to: CGPoint(x: 0, y: 0.575), control1: CGPoint(x: 0.5, y: 0.4), control2: CGPoint(x: 0.28, y: 0.575))
        p.addCurve(to: CGPoint(x: -0.5, y: 0.12), control1: CGPoint(x: -0.28, y: 0.575), control2: CGPoint(x: -0.5, y: 0.4))
        p.addCurve(to: CGPoint(x: 0, y: -0.575), control1: CGPoint(x: -0.5, y: -0.26), control2: CGPoint(x: -0.32, y: -0.575))
        return p
    }()
    private static let arm = Path(roundedRect: CGRect(x: -0.09, y: -0.04, width: 0.18, height: 0.34), cornerRadius: 0.09)
    private static let foot = Path(ellipseIn: CGRect(x: -0.17, y: -0.09, width: 0.34, height: 0.18))

    var body: some View {
        let still = reduceMotion || CloudTheme.reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: still || !visible)) { tl in
            let t = still ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let s = max(size.width, size.height)
                let k = still ? 0.0 : (sin(t / 40 * 2 * .pi) + 1) / 2
                let tint = Color(red: Self.mist.r + (Self.deep.r - Self.mist.r) * k * 0.8,
                                 green: Self.mist.g + (Self.deep.g - Self.mist.g) * k * 0.8,
                                 blue: Self.mist.b + (Self.deep.b - Self.mist.b) * k * 0.8)
                func draw(_ l: inout GraphicsContext) {
                    for sh in Self.shapes {
                        let a = t / sh.per * 2 * .pi + sh.ph
                        let m = still ? 0 : (1 - cos(t / (sh.per * 0.7) * 2 * .pi + sh.ph)) / 2
                        var p = sh.a.mixed(sh.b, m)
                        let br = still ? 0 : 0.045 * sin(t / 5.5 * 2 * .pi + sh.ph)
                        p.sx *= 1 + br; p.sy *= 1 - br
                        p.rot += still ? 0 : 0.05 * sin(t / (sh.per * 0.5) * 2 * .pi + sh.ph)
                        let cx = (sh.x + sh.ax * sin(a)) * size.width, cy = (sh.y + sh.ay * sin(a * 0.8 + 1)) * size.height
                        var c = l
                        c.translateBy(x: cx, y: cy); c.rotate(by: .radians(p.rot)); c.scaleBy(x: sh.size * s * p.sx, y: sh.size * s * p.sy)
                        c.fill(Self.body, with: .color(tint))
                        for side in [-1.0, 1.0] {
                            let ang = side < 0 ? p.aL : p.aR
                            let at = CGAffineTransform(rotationAngle: -side * ang).concatenating(CGAffineTransform(translationX: side * 0.44, y: -0.04))
                            c.fill(Self.arm.applying(at), with: .color(tint))
                            c.fill(Self.foot.applying(CGAffineTransform(scaleX: p.fs, y: p.fs).concatenating(CGAffineTransform(translationX: side * p.fx, y: 0.56 + p.fy))), with: .color(tint))
                        }
                    }
                }
                ctx.drawLayer { l in l.addFilter(.blur(radius: s * 0.035)); l.opacity = 0.6; draw(&l) }
                ctx.drawLayer { l in l.addFilter(.blur(radius: s * 0.004)); l.opacity = 0.9; draw(&l) }
            }
        }
        .background(CloudTheme.sky)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}
