//
//  MelonTheme.swift
//  Colours, fonts and the hairline control styles of the editorial UI.
//

import SwiftUI

extension Color {
    /// Linear-RGB -> sRGB-encoded colour.
    init(linear c: SIMD3<Float>) {
        func enc(_ v: Float) -> Double {
            let x = Double(min(max(v, 0), 1))
            return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        self.init(.sRGB, red: enc(c.x), green: enc(c.y), blue: enc(c.z), opacity: 1)
    }
}

enum MelonTheme {
    static let bg = Color(red: 0xE2 / 255, green: 0xDF / 255, blue: 0xDA / 255)
    static let ink = Color(red: 0x1c / 255, green: 0x1b / 255, blue: 0x19 / 255)
    static let muted = Color(red: 0x6d / 255, green: 0x69 / 255, blue: 0x62 / 255)
    static let faint = Color(red: 0x9a / 255, green: 0x95 / 255, blue: 0x8c / 255)
    static let line = ink.opacity(0.16)
    static let lineStrong = ink.opacity(0.42)
    static let accent = Color(red: 0x9e / 255, green: 0x1b / 255, blue: 0x2b / 255)
    static let live = Color(red: 0x2f / 255, green: 0x6f / 255, blue: 0x47 / 255)
    static let noteText = Color(red: 0x3d / 255, green: 0x3b / 255, blue: 0x37 / 255)

    static func serif(_ size: CGFloat) -> Font { .custom("IowanOldStyle-Roman", size: size) }
    static func serifItalic(_ size: CGFloat) -> Font { .custom("IowanOldStyle-Italic", size: size) }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// 10.5pt uppercase, tracked .2em, medium sans.
struct MelonLabel: ViewModifier {
    var size: CGFloat = 10.5
    var tracking: CGFloat = 0.2
    var color: Color = MelonTheme.muted
    func body(content: Content) -> some View {
        content
            .font(MelonTheme.sans(size, .medium))
            .tracking(size * tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
extension View {
    func melonLabel(size: CGFloat = 10.5, tracking: CGFloat = 0.2, color: Color = MelonTheme.muted) -> some View {
        modifier(MelonLabel(size: size, tracking: tracking, color: color))
    }
}

// MARK: - Button

/// 1pt strong border, transparent; inverts to ink on press. Dimmed when disabled.
struct HairlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let p = configuration.isPressed
        configuration.label
            .font(MelonTheme.sans(12.5))
            .tracking(0.12)
            .foregroundStyle(p ? MelonTheme.bg : MelonTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44 - 2)
            .frame(maxWidth: .infinity)
            .background(p ? MelonTheme.ink : Color.clear)
            .overlay(Rectangle().stroke(p ? MelonTheme.ink : MelonTheme.lineStrong, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - Checkbox

/// Square 12pt box with an inset filled square when on.
struct SquareCheckStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle().stroke(MelonTheme.ink, lineWidth: 1).frame(width: 12, height: 12)
                    if configuration.isOn {
                        Rectangle().fill(MelonTheme.ink).frame(width: 8, height: 8)
                    }
                }
                configuration.label
                    .font(MelonTheme.sans(12.5))
                    .foregroundStyle(MelonTheme.ink)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: - Slider

/// 1pt track, 13pt circular thumb with ink border. Value 0...1 with 0.01 steps.
struct HairlineSlider: View {
    @Binding var value: Double
    var label: String
    @Environment(\.isEnabled) private var enabled
    @State private var dragging = false

    private let thumb: CGFloat = 13

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - thumb)
            let x = CGFloat(value) * usable
            ZStack(alignment: .leading) {
                Rectangle().fill(MelonTheme.lineStrong).frame(height: 1)
                Circle()
                    .fill(dragging ? MelonTheme.ink : MelonTheme.bg)
                    .overlay(Circle().stroke(MelonTheme.ink, lineWidth: 1))
                    .frame(width: thumb, height: thumb)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        let v = Double((g.location.x - thumb / 2) / usable)
                        value = (min(max(v, 0), 1) * 100).rounded() / 100
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(1, (value * 100).rounded() / 100 + 0.05)
            case .decrement: value = max(0, (value * 100).rounded() / 100 - 0.05)
            @unknown default: break
            }
        }
    }
}
