//
//  MusicBubbleView.swift
//  The music thought bubble: while a Jelbie dances to the music he hears (Music Ears, hold-to-listen), the same pastel thought cloud as the needs
//  bubble (ThoughtBubbleView: same projection, same cloud, same trailing circles and pop) floats over his head with a music note in it. One cloud per
//  dancer, shown for as long as `Ears.dancingIDs` has him, a puff when it goes. Drawing only; it never takes a touch.
//

import SwiftUI
import simd

struct MusicBubbleView: View {
    let care: GameCare
    var ears: Ears = .shared

    @State private var appeared: [Int: Date] = [:]
    @State private var leaving: [Int: Date] = [:]

    static let fill = Color(red: 0.93, green: 0.90, blue: 1.0)
    static let note = Color(red: 0.52, green: 0.36, blue: 0.86)
    static let radius: CGFloat = 34
    static let popTime = 0.5

    var body: some View {
        GeometryReader { geo in
            let ids = ears.dancingIDs
            let live = !ids.isEmpty || !leaving.isEmpty
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { tl in
                Canvas { ctx, size in
                    for id in ids { draw(&ctx, id: id, size: size, now: tl.date, born: appeared[id] ?? tl.date, going: nil) }
                    for (id, t) in leaving where !ids.contains(id) { draw(&ctx, id: id, size: size, now: tl.date, born: nil, going: t) }
                } symbols: {
                    Image(systemName: "music.note").font(.system(size: 30, weight: .bold)).foregroundStyle(Self.note).tag(1)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: ears.dancingIDs) { old, new in
            let now = Date()
            for id in new where appeared[id] == nil { appeared[id] = now; leaving[id] = nil }
            for id in old where !new.contains(id) { appeared[id] = nil; leaving[id] = now }
        }
        .task(id: leaving.count) {
            guard !leaving.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            let cut = Date().addingTimeInterval(-0.6)
            leaving = leaving.filter { $0.value > cut }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, id: Int, size: CGSize, now: Date, born: Date?, going: Date?) {
        guard let head = ThoughtBubbleView.project(care.bubbleHead(id) + SIMD3(0, 0.1, 0), size: size, focus: care.focus.blend) else { return }
        let R = Self.radius
        let bob = CGFloat(sin(now.timeIntervalSinceReferenceDate * 2 * .pi / 0.9 + Double(id))) * 4          // a bobbing quicker than the needs cloud: it is dancing too
        let c = CGPoint(x: head.x + 8, y: head.y - R - 30 + bob)
        if let b = born {
            let u = now.timeIntervalSince(b)
            let s = CGFloat(max(0, 1 - exp(-7 * u) * cos(14 * u)))
            cloud(&ctx, c: c, head: head, R: R, scale: s)
            if u < Self.popTime { ThoughtBubbleView.puff(&ctx, at: c, u: u / Self.popTime) }
        } else if let g = going {
            let u = now.timeIntervalSince(g)
            if u < 0.2 { cloud(&ctx, c: c, head: head, R: R, scale: CGFloat(max(0, 1 - (u / 0.2) * (u / 0.2)))) }
            if u < Self.popTime { ThoughtBubbleView.puff(&ctx, at: c, u: u / Self.popTime) }
        }
    }

    private func cloud(_ ctx: inout GraphicsContext, c: CGPoint, head: CGPoint, R: CGFloat, scale s: CGFloat) {
        guard s > 0.01 else { return }
        var g = ctx
        let pivot = CGPoint(x: c.x, y: c.y + R * 0.8)
        g.translateBy(x: pivot.x, y: pivot.y); g.scaleBy(x: s, y: s); g.translateBy(x: -pivot.x, y: -pivot.y)
        var layer = g
        layer.addFilter(.shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.25), radius: 6, x: 0, y: 3))
        let blobs: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 0.78), (-0.62, 0.14, 0.58), (0.62, 0.14, 0.58), (-0.32, -0.42, 0.56), (0.30, -0.46, 0.62), (0, 0.32, 0.62)]
        let tx = head.x - c.x, ty = (head.y - 8) - (c.y + R * 0.8)
        let trail: [(CGFloat, CGFloat)] = [(0.30, 9), (0.66, 5.5)]
        layer.drawLayer { l in
            for (dx, dy, r) in blobs { l.fill(Path(ellipseIn: CGRect(x: c.x + dx * R - r * R, y: c.y + dy * R - r * R, width: 2 * r * R, height: 2 * r * R)), with: .color(Self.fill)) }
            for (k, r) in trail { l.fill(Path(ellipseIn: CGRect(x: c.x + tx * k - r, y: c.y + R * 0.8 + ty * k - r, width: 2 * r, height: 2 * r)), with: .color(Self.fill)) }
        }
        g.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.6, y: c.y - R * 0.62, width: R * 0.5, height: R * 0.28)), with: .color(.white.opacity(0.45)))
        if let sym = ctx.resolveSymbol(id: 1) { g.draw(sym, at: CGPoint(x: c.x, y: c.y + 2)) }
    }
}
