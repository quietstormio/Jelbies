//
//  A11yStyle.swift
//  Contrast / transparency helpers: opaque fallbacks for Materials (Reduce Transparency), stronger inks and strokes (Increase Contrast),
//  a darker pink that carries white text, and a diagonal-stripe pattern so "wanting" never relies on colour alone.
//

import SwiftUI

extension SK {
    /// Pink that carries white text at 4.5:1 or better (#A8405F is about 5.6:1 on white, 4.9:1 on cream).
    static let pinkStrong = Color(hex: 0xA8405F)
    /// Muted text at 4.5:1 or better on cream (the default `SK.muted` is #6B5749; this is darker).
    /// Sky for icons / text on cream at 3:1 or better (the plain SK.sky is 2.1:1).
    static let skyDeep = Color(hex: 0x2F7FA3)
    static let mutedStrong = Color(hex: 0x4F3F33)
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

/// Wraps the paw menu's rows so they scroll (anchored to the paw at the bottom) when the screen is too short for them, as on a phone on its side.
/// While the rows fit it is laid out exactly as before. The paw itself (`footer`) sits below the scroll, not in it: inside, its place in the scroll's
/// coordinates jumped from the top (closed) to the bottom (open), and the animated layout made it start at the top of the menu and slide down on open.
struct CareScroller<Content: View, Footer: View>: View {
    @Binding var natural: CGSize?
    /// What the footer takes out of the available height (the gap above it is the content's own bottom padding).
    var reserved: CGFloat = 0
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @Environment(\.a11yAvailableHeight) private var avail
    /// The rows' size, kept for a moment after they leave. The rows that are folding away no longer count toward the content's size, and a content or frame
    /// that shrank with them clipped them to a sliver at the paw (and let the content slide) for the whole close. While the menu is open this is just its size.
    @State private var kept: CGSize?
    @State private var releaseTicket = 0

    var body: some View {
        // The scroll clips, so a menu taller than the space left really scrolls (it used to draw over the top bar). The shadows get a
        // margin inside the clip, taken back outside it so the layout is the same as before.
        let m: CGFloat = 12
        let size = kept ?? natural
        let under = reserved / 2          // the clip reaches down to the middle of the paw (taken back from the layout below), so the folding rows can end inside it
        return VStack(alignment: .trailing, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .fixedSize(horizontal: true, vertical: false)          // rows take their own width (never wrapped a letter a line by a narrow first proposal)
                    .padding(.bottom, under)
                    .padding(m)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
                    // the leaving rows stay where they were drawn (the content keeps its size, empty, from the top) and at the trailing edge
                    .frame(minWidth: kept?.width, minHeight: kept?.height, alignment: .topTrailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom)
            .frame(width: size?.width, height: size.map { min($0.height, max(120, avail - reserved) + 2 * m + under) })
            .padding(-m)
            .padding(.bottom, -under)
            footer()
        }
        .onChange(of: natural) { _, new in
            guard let new else { return }
            releaseTicket += 1
            if new.height > 2 * m + reserved / 2 + 0.5 { kept = new; return }          // rows showing (or opening, or re-opening in the middle of a fold): follow at once
            let ticket = releaseTicket
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if ticket == releaseTicket { kept = nil } }          // empty: the fold takes ~0.3 s
        }
    }
}
