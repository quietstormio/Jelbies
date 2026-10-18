//
//  NeedGlyph.swift
//  The three need icons shared by the thought bubble and the roster: a pair of berries (food), a water drop (drink), a heart (attention).
//

import SwiftUI

enum NeedStyle {
    static let berry = Color(red: 0.93, green: 0.30, blue: 0.45)
    static let leaf = Color(red: 0.45, green: 0.74, blue: 0.40)
    static let drop = Color(red: 0.33, green: 0.63, blue: 0.95)
    static let heart = Color(red: 0.95, green: 0.42, blue: 0.56)
    static func tint(_ k: NeedKind) -> Color {
        switch k { case .hunger: return berry; case .thirst: return drop; case .attention: return heart }
    }
    static let soap = Color(red: 0.36, green: 0.72, blue: 0.82)
    /// The pastel the bath bubble is filled with.
    static let cleanFill = Color(red: 0.88, green: 0.97, blue: 0.96)
    /// The pastel the bubble is filled with.
    static func bubble(_ k: NeedKind) -> Color {
        switch k {
        case .hunger: return Color(red: 1.0, green: 0.91, blue: 0.87)
        case .thirst: return Color(red: 0.88, green: 0.94, blue: 1.0)
        case .attention: return Color(red: 1.0, green: 0.89, blue: 0.93)
        }
    }

    /// Two berries with a leaf, centred at `c`, about `s` points across.
    static func drawBerries(_ ctx: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        let r = s * 0.29
        for (dx, dy) in [(-0.2, 0.08), (0.2, 0.0)] {
            let b = CGPoint(x: c.x + CGFloat(dx) * s, y: c.y + CGFloat(dy) * s)
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: 2 * r, height: 2 * r)), with: .color(berry))
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - r * 0.55, y: b.y - r * 0.6, width: r * 0.45, height: r * 0.45)), with: .color(.white.opacity(0.65)))
            var leafPath = Path()
            leafPath.addEllipse(in: CGRect(x: -r * 0.55, y: -r * 0.2, width: r * 1.1, height: r * 0.5))
            var l = ctx
            l.translateBy(x: b.x, y: b.y - r * 0.95)
            l.rotate(by: .degrees(dx < 0 ? -25 : 25))
            l.fill(leafPath, with: .color(leaf))
        }
    }
}

/// A need icon at `size` points.
struct NeedGlyph: View {
    let kind: NeedKind
    var size: CGFloat = 22
    var body: some View {
        switch kind {
        case .hunger:
            Canvas { ctx, sz in NeedStyle.drawBerries(&ctx, at: CGPoint(x: sz.width / 2, y: sz.height / 2), size: size) }
                .frame(width: size, height: size)
        case .thirst:
            Image(systemName: "drop.fill").font(.system(size: size * 0.9, weight: .semibold)).foregroundStyle(NeedStyle.drop)
                .frame(width: size, height: size)
        case .attention:
            Image(systemName: "heart.fill").font(.system(size: size * 0.85, weight: .semibold)).foregroundStyle(NeedStyle.heart)
                .frame(width: size, height: size)
        }
    }
}
