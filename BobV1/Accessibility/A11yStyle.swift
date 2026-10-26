//
//  A11yStyle.swift
//  Contrast / transparency helpers: opaque fallbacks for Materials (Reduce Transparency), stronger inks and strokes (Increase Contrast),
//  a darker pink that carries white text, and a diagonal-stripe pattern so "wanting" never relies on colour alone.
//

import SwiftUI

extension SK {
    /// Pink that carries white text at 4.5:1 or better (#A8405F is about 5.6:1 on white, 4.9:1 on cream).
    static var pinkStrong: Color { DT.accent }
    /// Muted text at 4.5:1 or better on cream (the default `SK.muted` is #6B5749; this is darker).
    /// Sky for icons / text on cream at 3:1 or better (the plain SK.sky is 2.1:1).
    static var skyDeep: Color { DT.accent }
    static let mutedStrong = DT.ink
}

private struct JMaterialModifier<S: SwiftUI.Shape>: ViewModifier {
    let material: Material, fallback: Color, shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduce
    func body(content: Content) -> some View {
        if reduce { content.background(fallback, in: shape) } else { content.background(material, in: shape) }
    }
}

extension View {
    /// `.background(material, in: shape)`, or the opaque `fallback` when Reduce Transparency is on.
    func jMaterial<S: SwiftUI.Shape>(_ material: Material, fallback: Color = SK.cream, in shape: S) -> some View {
        modifier(JMaterialModifier(material: material, fallback: fallback, shape: shape))
    }
}

/// Text colour that follows Increase Contrast: the muted tone normally, full ink when contrast is increased.
struct JMutedText: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    var base: Color = FocusStyle.brown.opacity(0.7)
    func body(content: Content) -> some View { content.foregroundStyle(contrast == .increased ? FocusStyle.brown : base) }
}

extension View {
    func jMuted(_ base: Color = FocusStyle.brown.opacity(0.7)) -> some View { modifier(JMutedText(base: base)) }
}

/// Diagonal stripes over a capsule: the "wanting" pattern for meters.
struct StripePattern: View {
    var color: Color = FocusStyle.brown.opacity(0.55)
    var spacing: CGFloat = 4
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(color), lineWidth: 1.2)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

private struct A11yAvailableHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 800 }
extension EnvironmentValues {
    /// The HUD's available height, so tall menus can scroll instead of running off a landscape screen.
    var a11yAvailableHeight: CGFloat {
        get { self[A11yAvailableHeightKey.self] }
        set { self[A11yAvailableHeightKey.self] = newValue }
    }
}

/// Wraps the paw menu so it scrolls (anchored to the paw at the bottom) when the screen is too short for it, as on a phone on its side.
/// While the menu fits it is laid out exactly as before.
struct CareScroller<Content: View>: View {
    @Binding var natural: CGSize?
    @ViewBuilder var content: () -> Content
    @Environment(\.a11yAvailableHeight) private var avail

    var body: some View {
        // The scroll clips, so a menu taller than the space left really scrolls (it used to draw over the top bar). The shadows get a
        // margin inside the clip, taken back outside it so the layout is the same as before.
        let m: CGFloat = 12
        return ScrollView(.vertical, showsIndicators: false) {
            content()
                .fixedSize(horizontal: true, vertical: false)          // rows take their own width (never wrapped a letter a line by a narrow first proposal)
                .padding(m)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.bottom)
        .frame(width: natural?.width, height: natural.map { min($0.height, max(120, avail) + 2 * m) })
        .padding(-m)
    }
}
