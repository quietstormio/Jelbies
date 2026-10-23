//
//  TouchHearts.swift
//  Bare pink hearts (no cloud, no bubble, no trail) that pop out BESIDE Bob's head while he enjoys being petted or held.
//  Reads `TouchPlay.hearts` (birth time, side, drift, start offset) every frame. Each heart starts just outside his silhouette, alternately at
//  the upper left and upper right of the crown, found with the SAME world->screen projection as the need bubble (`ThoughtBubbleView.project`),
//  so it follows him when he is lifted. Flat pink (#E98AA4) with a very soft shadow and a slightly deeper pink edge so it reads over the cream
//  rug and the light-blue Blob. Sizes vary 28-44 pt (from the heart's start offset); it floats up ~75 pt with a gentle side sway, pops in with
//  a slight scale overshoot and fades out over 1.2 s, and is clamped inside the safe area, under the status bar and clear of the "Let Bob go"
//  pill. While the need bubble shows the hearts move out a little further. Idle cost: a 0.15 s tick reading `hearts.isEmpty`; drawing (30 fps)
//  only while a heart is alive. Not hit-testable.
//

import SwiftUI
import UIKit
import simd

struct TouchHeartsView: View {
    let play: TouchPlay
    let care: GameCare

    static let pink = Color(red: 0.914, green: 0.541, blue: 0.643)         // #E98AA4
    static let edge = Color(red: 0.80, green: 0.38, blue: 0.51)            // slightly deeper pink outline
    static let minSize: CGFloat = 28, maxSize: CGFloat = 44                // heart width range, points
    static let halfExtent: CGFloat = 24                                    // placement clamp radius (largest heart, a little room for the sway)
    static let sway: CGFloat = 7
    /// Heart width for a heart (its start offset -1...1 picks the size).
    static func size(of h: TouchPlay.Heart) -> CGFloat { minSize + (maxSize - minSize) * CGFloat((min(max(h.start, -1), 1) + 1) / 2) }
    static let rise: CGFloat = 75

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { _ in
            if play.hearts.isEmpty { Color.clear } else { live }          // (read outside any GeometryReader: its content is not re-run every tick)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The window's top safe-area inset (status bar / Dynamic Island), points.
    static var safeTop: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.top ?? 59
    }

    /// Where a heart sits (centre, points) for a head point and a heart age 0...1: beside the crown, rising with a sway, clamped into the visible area.
    static func place(_ h: TouchPlay.Heart, age a: Double, anchor: CGPoint, size: CGSize, safeTop: CGFloat, calm: Bool = false) -> CGPoint {
        let a = calm ? 0.25 : a          // Reduce Motion: the heart stays put beside the crown and only fades
        let r = halfExtent
        let e = CGFloat(1 - (1 - a) * (1 - a))
        var x = anchor.x + CGFloat(h.drift) * 14 * CGFloat(a) + CGFloat(h.start) * 6 + sway * CGFloat(sin(a * 2 * .pi * 1.3 + Double(h.drift) * 2)) * CGFloat(min(1, a * 4))
        var y = anchor.y - rise * e
        x = min(max(x, r + 8), size.width - r - 8)
        var top = safeTop + r + 6                                       // under the status bar / island
        if x - r < 126 { top = max(top, 116 + r) }                          // and under the "Let Bob go" pill when beside it
        y = min(max(y, top), size.height - r - 8)
        return CGPoint(x: x, y: y)
    }

    private var live: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                _ = tl.date
                let head = care.headWorld               // centroid + H/2: the middle of his body is head.y - H/2
                let H = Float(BlobShape.H)
                let mid = head - SIMD3(0, H * 0.5, 0)
                let need: Float = care.bubbleNeed != nil ? 0.2 : 0
                guard let sym = ctx.resolveSymbol(id: 0), let edge = ctx.resolveSymbol(id: 1) else { return }
                let now = CACurrentMediaTime()
                let top = Self.safeTop
                for h in play.hearts {
                    let a = (now - h.born) / TouchPlay.heartLife
                    guard a >= 0, a < 1 else { continue }
                    // 80 % of his height above his feet, a hair outside the silhouette on the heart's side
                    let w = SIMD3<Float>(mid.x + h.side * (0.80 + need), mid.y - 0.64 + 0.8 * H, mid.z)
                    guard let p0 = ThoughtBubbleView.project(w, size: size, focus: care.focus.blend) else { continue }
                    let p = Self.place(h, age: a, anchor: p0, size: size, safeTop: top, calm: A11ySettings.shared.reduceMotion)
                    var c = ctx
                    c.opacity = Self.opacity(age: a)
                    let s = Self.scale(age: a) * Self.size(of: h) / Self.symbolSize
                    c.translateBy(x: p.x, y: p.y); c.scaleBy(x: s, y: s)
                    Self.drawHeart(&c, edge: edge, fill: sym)
                }
            } symbols: {
                Image(systemName: "heart.fill").font(.system(size: Self.symbolSize, weight: .semibold)).foregroundStyle(Self.pink).tag(0)
                Image(systemName: "heart.fill").font(.system(size: Self.symbolSize, weight: .semibold)).foregroundStyle(Self.edge).tag(1)
            }
        }
    }

    static let symbolSize: CGFloat = 36

    /// Fade: quick in, fading over the last 40 %.
    static func opacity(age a: Double) -> Double { a < 0.1 ? a / 0.1 : min(1, (1 - a) / 0.4) }
    /// Pop-in: 0.6 -> a slight overshoot (1.1) at age 0.15 -> 1 at age 0.3.
    static func scale(age a: Double) -> CGFloat {
        if a >= 0.3 { return 1 }
        if a < 0.15 { return CGFloat(0.6 + 0.5 * (a / 0.15)) }
        return CGFloat(1.1 - 0.1 * ((a - 0.15) / 0.15))
    }

    /// Just the heart at the origin: a slightly deeper pink edge (the same glyph a touch bigger, behind) and a very soft shadow.
    static func drawHeart(_ c: inout GraphicsContext, edge: GraphicsContext.ResolvedSymbol, fill: GraphicsContext.ResolvedSymbol) {
        var layer = c
        layer.addFilter(.shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.16), radius: 3, x: 0, y: 1.5))
        layer.drawLayer { l in
            var e = l; e.scaleBy(x: 1.12, y: 1.12)
            e.draw(edge, at: .zero)
            l.draw(fill, at: .zero)
        }
    }
}
