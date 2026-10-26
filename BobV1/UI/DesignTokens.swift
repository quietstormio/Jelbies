//
//  DesignTokens.swift
//  "Calm & Clean": the one shared look of the app chrome. Neutrals do most of the work, ONE accent (the player's theme colour) marks the
//  primary button, the selected chip/tab, the active toggle and progress fills. Calm weights (semibold at most), 8 pt grid, hairline borders.
//  The older palettes (SK, FocusStyle, CareMenu, UITheme, CloudTheme) read their values from here so every screen stays uniform.
//

import SwiftUI

enum DT {
    // MARK: Neutrals
    static let paper = Color(hex: 0xF8F6F2)
    static let card = Color.white
    static let line = Color(hex: 0xE9E4DC)
    static let ink = Color(hex: 0x2A2622)
    static let ink2 = Color(hex: 0x6B635B)          // 5.3:1 on Paper, 5.7:1 on Card
    static let fill = Color(hex: 0xF0ECE6)

    // MARK: Accent (the theme colour; deep enough for white text)
    static var accent: Color { ThemeStore.shared.palette.newGame }
    static var accentSoft: Color { accent.opacity(0.14) }
    static var accentLine: Color { accent.opacity(0.55) }

    // MARK: Semantic (sparing)
    static let success = Color(hex: 0x3E9A6E)
    static let warning = Color(hex: 0xD69A2D)
    static let danger = Color(hex: 0xCF4B45)

    // MARK: Spacing (8 pt grid)
    static let gutter: CGFloat = 16
    static let related: CGFloat = 12
    static let section: CGFloat = 24
    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 14
    static let buttonHeight: CGFloat = 50
    static let well: CGFloat = 44

    // MARK: Type (all through jFont's scaler so Dynamic Type keeps working)
    static func title(_ size: CGFloat = 28) -> Font { JFont.scaled(size, .semibold, style: .title2) }
    static func heading(_ size: CGFloat = 20) -> Font { JFont.scaled(size, .semibold, style: .title3) }
    static func body(_ size: CGFloat = 17) -> Font { JFont.scaled(size, .regular) }
    static func callout(_ size: CGFloat = 15) -> Font { JFont.scaled(size, .medium, style: .callout) }
    static func caption(_ size: CGFloat = 13) -> Font { JFont.scaled(size, .medium, style: .footnote) }

    // MARK: Motion
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
}

// MARK: - Buttons

/// Primary = accent fill + white text. Secondary = Card + hairline + Ink. Tertiary = text only, in the accent.
enum DTButtonKind { case primary, secondary, tertiary }

struct DTButtonStyle: ButtonStyle {
    typealias Kind = DTButtonKind
    var kind: Kind = .primary
    var size: CGFloat?
    var minHeight: CGFloat?
    init(_ kind: Kind = .primary, size: CGFloat? = nil, minHeight: CGFloat? = nil) { self.kind = kind; self.size = size; self.minHeight = minHeight }
    func makeBody(configuration: Configuration) -> some View {
        DTButtonBody(kind: kind, size: size, minHeight: minHeight, label: configuration.label, pressed: configuration.isPressed)
    }
}

struct DTButtonBody<Label: View>: View {
    typealias Kind = DTButtonKind
    let kind: Kind, size: CGFloat?, minHeight: CGFloat?, label: Label, pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DT.buttonRadius, style: .continuous)
        label
            .font(DT.heading(size ?? 17))
            .foregroundStyle(kind == .primary ? Color.white : kind == .secondary ? DT.ink : DT.accent)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: kind == .tertiary ? 44 : (minHeight ?? DT.buttonHeight))
            .padding(.horizontal, 12)
            .background {
                switch kind {
                case .primary: shape.fill(DT.accent)
                case .secondary: shape.fill(DT.card).overlay(shape.strokeBorder(DT.line, lineWidth: 1))
                case .tertiary: Color.clear
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? (pressed ? 0.9 : 1) : 0.5)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : DT.spring, value: pressed)
    }
}

extension ButtonStyle where Self == DTButtonStyle {
    static var dtPrimary: DTButtonStyle { DTButtonStyle(.primary) }
    static var dtSecondary: DTButtonStyle { DTButtonStyle(.secondary) }
    static var dtTertiary: DTButtonStyle { DTButtonStyle(.tertiary) }
}

// MARK: - Card, chip, icon well

struct DTCard: ViewModifier {
    var radius: CGFloat = DT.cardRadius
    func body(content: Content) -> some View {
        let s = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background(s.fill(DT.card).shadow(color: .black.opacity(0.06), radius: 10, y: 2)).overlay(s.strokeBorder(DT.line, lineWidth: 1))
    }
}
extension View {
    func dtCard(radius: CGFloat = DT.cardRadius) -> some View { modifier(DTCard(radius: radius)) }
    /// A capsule chip: Fill when idle, Accent-Soft with an accent hairline when selected.
    func dtChip(selected: Bool = false) -> some View {
        background(Capsule().fill(selected ? DT.accentSoft : DT.fill)).overlay(Capsule().strokeBorder(selected ? DT.accentLine : .clear, lineWidth: 1))
    }
    /// A 44 pt round icon well on a Card with a hairline (HUD buttons).
    func dtWell(_ size: CGFloat = DT.well, active: Bool = false) -> some View {
        frame(width: size, height: size)
            .background(Circle().fill(active ? DT.accentSoft : DT.card))
            .overlay(Circle().strokeBorder(active ? DT.accentLine : DT.line, lineWidth: 1))
    }
}

/// An SF Symbol (medium weight, Ink or accent) in a 44 pt Fill well.
struct DTIcon: View {
    let name: String
    var size: CGFloat = DT.well
    var active = false
    var body: some View {
        Image(systemName: name).font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(active ? DT.accent : DT.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(active ? DT.accentSoft : DT.fill))
    }
}
