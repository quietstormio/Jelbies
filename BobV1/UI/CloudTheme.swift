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

/// White sky with slow drifting Mist circles. Still when Reduce Motion is on.
struct CloudSky: View {
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, s = max(w, h)
            let still = reduceMotion || CloudTheme.reduceMotion
            ZStack {
                CloudTheme.sky
                bubble(s * 0.46, x: w * 0.05, y: h * 0.14, dx: 10, dy: -16, still)
                bubble(s * 0.30, x: w * 0.95, y: h * 0.36, dx: -12, dy: 12, still)
                bubble(s * 0.58, x: w * 0.55, y: h * 1.0, dx: 8, dy: -18, still)
                bubble(s * 0.14, x: w * 0.18, y: h * 0.58, dx: 6, dy: -10, still)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { drift = true }
    }
    private func bubble(_ d: CGFloat, x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat, _ still: Bool) -> some View {
        Circle().fill(CloudTheme.mist).frame(width: d, height: d)
            .scaleEffect(drift && !still ? 1.06 : 1)
            .position(x: x + (drift && !still ? dx : 0), y: y + (drift && !still ? dy : 0))
            .animation(still ? nil : .easeInOut(duration: 9 + Double(d.truncatingRemainder(dividingBy: 3))).repeatForever(autoreverses: true), value: drift)
    }
}
