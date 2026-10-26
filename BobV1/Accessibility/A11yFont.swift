//
//  A11yFont.swift
//  Dynamic Type for the chrome. The game's fonts are fixed point sizes (`.system(size:)`); these helpers make them follow the reader's text size.
//  `JFont.scaled` is what `SK.font` and `UITheme.title/body/caption` call, so the hundreds of call sites grow without being touched. It reads the
//  app's content size category on every call, so a size change made mid-session applies on the next re-render (the HUD and the sheets re-render often).
//  The room HUD overlay is additionally capped at `.accessibility2` (see `jHUDCap`) so the room stays visible.
//

import SwiftUI
import UIKit

enum JFont {
    /// How far a central helper may grow a size: 2x keeps fixed-size pills and cards workable; `jFont` (new text) may go to 3x.
    static let helperCap: CGFloat = 2.0

    /// `size` scaled by the current Dynamic Type setting relative to `style`, never above `size * cap`.
    static func scaledSize(_ size: CGFloat, style: UIFont.TextStyle = .body, cap: CGFloat = helperCap, category: UIContentSizeCategory? = nil) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: style)
        let v: CGFloat
        if let category { v = metrics.scaledValue(for: size, compatibleWith: UITraitCollection(preferredContentSizeCategory: category)) }
        else { v = metrics.scaledValue(for: size) }
        return min(max(v, size), size * cap)
    }

    /// Calm & Clean: nothing heavier than semibold (the title-screen logo draws its own font).
    static func calm(_ w: Font.Weight) -> Font.Weight { w == .black || w == .heavy || w == .bold ? .semibold : w }

    static func scaled(_ size: CGFloat, _ weight: Font.Weight = .semibold, design: Font.Design = .rounded, style: UIFont.TextStyle = .body, cap: CGFloat = helperCap) -> Font {
        .system(size: scaledSize(size, style: style, cap: cap), weight: calm(weight), design: design)
    }
}

private struct JFontModifier: ViewModifier {
    let size: CGFloat, weight: Font.Weight, design: Font.Design, maxScale: CGFloat
    @ScaledMetric private var scaled: CGFloat
    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle, maxScale: CGFloat) {
        self.size = size; self.weight = weight; self.design = design; self.maxScale = maxScale
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
    }
    func body(content: Content) -> some View {
        content.font(.system(size: min(max(scaled, size), size * maxScale), weight: JFont.calm(weight), design: design))
    }
}

extension View {
    /// A rounded system font that follows Dynamic Type (including the accessibility sizes), clamped to `size * maxScale`.
    func jFont(_ size: CGFloat, _ weight: Font.Weight = .semibold, design: Font.Design = .rounded, relativeTo: Font.TextStyle = .body, maxScale: CGFloat = 3.0) -> some View {
        modifier(JFontModifier(size: size, weight: weight, design: design, relativeTo: relativeTo, maxScale: maxScale))
    }

    /// The room HUD overlay stops growing at accessibility2 so the room itself stays visible.
    func jHUDCap() -> some View { dynamicTypeSize(...DynamicTypeSize.accessibility2) }
}

private struct JLineModifier: ViewModifier {
    let lines: Int, scale: CGFloat
    @Environment(\.dynamicTypeSize) private var dts
    func body(content: Content) -> some View {
        // At accessibility sizes text wraps instead of truncating or shrinking.
        content.lineLimit(dts.isAccessibilitySize ? nil : lines).minimumScaleFactor(dts.isAccessibilitySize ? 1 : scale)
    }
}
extension View {
    /// `.lineLimit(lines).minimumScaleFactor(scale)`, except at accessibility text sizes where the text wraps in full.
    func jLine(_ lines: Int = 1, scale: CGFloat = 0.8) -> some View { modifier(JLineModifier(lines: lines, scale: scale)) }
}
