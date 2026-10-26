//
//  ThoughtBubbleView.swift
//  The thought bubble above Bob's head when he wants something: a pastel cloud with two small circles trailing toward his head and the icon of
//  what he wants (berries, a drop, a heart). Anchored with the game camera's world->screen projection (the same one the hearts and the outline
//  use), a gentle bob, a puff when it pops in and when it goes. Tap it to open the matching care action. When the need is fixed it poofs with a
//  happy sparkle. GameCare's BubbleSchedule decides when it shows (about 6 s every 20 s); this view only draws.
//

import SwiftUI
import simd

struct ThoughtBubbleView: View {
    let care: GameCare
    let onTap: (BubbleAction) -> Void

    @State private var shown: BubbleIcon?
    @State private var appeared = Date.distantPast
    @State private var leaving: Leave?
    @State private var lastSpokenAt = Date.distantPast
    @State private var lastSpoken = ""          // VoiceOver hears a need once, not on every 20 s cycle

    private struct Leave { var need: BubbleIcon; var start: Date; var fixed: Bool; var shownBefore: Bool }

    static let radius: CGFloat = 40
    static let popTime = 0.55

    /// World -> screen with the game camera (points, y down); nil behind the camera.
    static func project(_ w: SIMD3<Float>, size: CGSize, focus: Float) -> CGPoint? {
        let vp = GameCamera.camera(aspect: Float(size.width / max(size.height, 1)), focus: focus).viewProj
        let q = vp * SIMD4<Float>(w, 1)
        guard q.w > 1e-4 else { return nil }
        return CGPoint(x: CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (q.y / q.w * 0.5 + 0.5)) * size.height)
    }

    /// Where the cloud sits for a head point: above it, with room for the two trailing circles.
    static func cloudCenter(head: CGPoint) -> CGPoint { CGPoint(x: head.x + 8, y: head.y - radius - 34) }

    var body: some View {
        GeometryReader { geo in
            let live = shown != nil || leaving != nil
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { tl in
                ZStack {
                    Canvas { ctx, size in paint(&ctx, size: size, now: tl.date) } symbols: {
                        Image(systemName: "drop.fill").font(.system(size: 36, weight: .semibold)).foregroundStyle(NeedStyle.drop).tag(1)
                        Image(systemName: "heart.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(NeedStyle.heart).tag(2)
                        Image(systemName: "bubbles.and.sparkles.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(NeedStyle.soap).tag(3)
                    }
                    .allowsHitTesting(false)
                    if let n = shown, let h = headPoint(geo.size) {
                        let c = Self.cloudCenter(head: h)
                        Button { if let a = care.tapBubble() { onTap(a) } } label: { Color.clear }
                            .buttonStyle(.plain)
                            .frame(width: 92, height: 92)
                            .contentShape(Circle())
                            .position(x: c.x, y: c.y + bob(tl.date))
                            .accessibilityIdentifier("thought-bubble")
                            .accessibilityLabel(label(n))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: care.bubbleIcon) { _, n in
            if let n { shown = n; appeared = Date(); leaving = nil; let t = spoken(n); if t != lastSpoken || Date().timeIntervalSince(lastSpokenAt) > 180 { lastSpokenAt = Date(); lastSpoken = t; A11yAnnounce.say(t, priority: .low) } }          // the cloud is transient: say it once
        }
        .onChange(of: care.bubbleEnd) { _, e in
            if e.silent { leaving = nil; shown = nil; return }       // the clean-up run-out: the cloud just goes, no puff over the room
            leaving = Leave(need: e.clean ? .clean : .need(e.need), start: Date(), fixed: e.fixed, shownBefore: shown != nil)
            shown = nil
        }
        .task(id: leaving?.start) {
            guard leaving != nil else { return }
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            leaving = nil
        }
    }

    private func spoken(_ i: BubbleIcon) -> String {
        let who = care.bubbleJellyName
        guard case .need(let n) = i else { return "\(who) is dirty" }
        switch n { case .hunger: return "\(who) is hungry"; case .thirst: return "\(who) is thirsty"; case .attention: return "\(who) wants attention" }
    }

    private func label(_ i: BubbleIcon) -> String {
        let who = care.bubbleJellyName
        guard case .need(let n) = i else { return "\(who) is dirty. Tap to clean \(who)" }
        switch n { case .hunger: return "\(who) is hungry. Tap to feed \(who)"; case .thirst: return "\(who) is thirsty. Tap to give a drink"; case .attention: return "\(who) wants attention. Tap to call \(who)" }
    }

    private func headPoint(_ size: CGSize) -> CGPoint? {
        Self.project(care.bubbleHead(care.bubbleJelly) + SIMD3(0, 0.1, 0), size: size, focus: care.focus.blend)
    }
    private func bob(_ date: Date) -> CGFloat { CGFloat(sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 2.2)) * 4 }

    // MARK: drawing

    private func paint(_ ctx: inout GraphicsContext, size: CGSize, now: Date) {
        guard let head = headPoint(size) else { return }
        let c = Self.cloudCenter(head: head)
        if let n = shown {
            let u = now.timeIntervalSince(appeared)
            let s = CGFloat(max(0, 1 - exp(-7 * u) * cos(14 * u)))                       // springy pop, overshoots and settles
            var g = ctx
            drawCloud(&g, need: n, center: CGPoint(x: c.x, y: c.y + bob(now)), head: head, scale: s, ctx: ctx)
            if u < Self.popTime { Self.puff(&ctx, at: c, u: u / Self.popTime) }
        }
        if let l = leaving {
            let u = now.timeIntervalSince(l.start)
            if l.shownBefore || l.fixed {
                // the cloud shrinks away fast inside the puff
                if u < 0.2 {
                    let s = CGFloat(max(0, 1 - (u / 0.2) * (u / 0.2)))
                    var g = ctx
                    drawCloud(&g, need: l.need, center: CGPoint(x: c.x, y: c.y + bob(now)), head: head, scale: s, ctx: ctx)
                }
                if u < Self.popTime { Self.puff(&ctx, at: c, u: u / Self.popTime) }
            }
            if l.fixed, u < 1.0 { Self.sparkle(&ctx, around: CGPoint(x: head.x, y: head.y - 50), u: u / 1.0) }
        }
    }

    private func drawCloud(_ g: inout GraphicsContext, need: BubbleIcon, center c: CGPoint, head: CGPoint, scale s: CGFloat, ctx base: GraphicsContext) {
        guard s > 0.01 else { return }
        let R = Self.radius
        // the cloud scales about its bottom-centre (it pops out of the trailing circles), the circles toward the head grow with it
        let pivot = CGPoint(x: c.x, y: c.y + R * 0.8)
        g.translateBy(x: pivot.x, y: pivot.y); g.scaleBy(x: s, y: s); g.translateBy(x: -pivot.x, y: -pivot.y)
        let fill: Color
        if case .need(let k) = need { fill = NeedStyle.bubble(k) } else { fill = NeedStyle.cleanFill }
        var layer = g
        layer.addFilter(.shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.25), radius: 6, x: 0, y: 3))
        let blobs: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 0.78), (-0.62, 0.14, 0.58), (0.62, 0.14, 0.58), (-0.32, -0.42, 0.56), (0.30, -0.46, 0.62), (0, 0.32, 0.62)]
        // trailing circles toward his head
        let tx = head.x - c.x, ty = (head.y - 8) - (c.y + R * 0.8)
        let trail: [(CGFloat, CGFloat)] = [(0.30, 10), (0.66, 6)]
        layer.drawLayer { l in
            for (dx, dy, r) in blobs { l.fill(Path(ellipseIn: CGRect(x: c.x + dx * R - r * R, y: c.y + dy * R - r * R, width: 2 * r * R, height: 2 * r * R)), with: .color(fill)) }
            for (k, r) in trail { l.fill(Path(ellipseIn: CGRect(x: c.x + tx * k - r, y: c.y + R * 0.8 + ty * k - r, width: 2 * r, height: 2 * r)), with: .color(fill)) }
        }
        g.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.6, y: c.y - R * 0.62, width: R * 0.5, height: R * 0.28)), with: .color(.white.opacity(0.45)))   // glossy highlight
        // the icon
        switch need {
        case .need(.hunger): NeedStyle.drawBerries(&g, at: CGPoint(x: c.x, y: c.y + 2), size: 50)
        case .need(.thirst): if let sym = base.resolveSymbol(id: 1) { g.draw(sym, at: CGPoint(x: c.x, y: c.y + 2)) }
        case .need(.attention): if let sym = base.resolveSymbol(id: 2) { g.draw(sym, at: CGPoint(x: c.x, y: c.y + 3)) }
        case .clean: if let sym = base.resolveSymbol(id: 3) { g.draw(sym, at: CGPoint(x: c.x, y: c.y + 2)) }
        }
    }

    /// The same idea as the room's Puff: a handful of soft cream spheres that swell, drift apart and fade.
    static func puff(_ ctx: inout GraphicsContext, at c: CGPoint, u: Double) {
        let u = min(max(u, 0), 1)
        let ease = CGFloat(1 - (1 - u) * (1 - u))
        let a = 0.95 * pow(max(1 - u, 0), 1.1)
        for k in 0..<6 {
            let az = Double(k) * 2.39996
            let d = CGFloat(30 + 18 * Double(k % 3)) * ease
            let r = CGFloat(10 + 5 * Double(k % 2)) * CGFloat(0.4 + 0.9 * min(u / 0.45, 1))
            let p = CGPoint(x: c.x + CGFloat(cos(az)) * d, y: c.y + CGFloat(sin(az)) * d * 0.8)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 1.0, green: 0.97, blue: 0.94).opacity(a)))
        }
    }

    /// A little happy sparkle: four-point stars burst out and rise.
    static func sparkle(_ ctx: inout GraphicsContext, around c: CGPoint, u: Double) {
        let u = min(max(u, 0), 1)
        let a = 1 - u * u
        let colors: [Color] = [Color(red: 1.0, green: 0.84, blue: 0.35), NeedStyle.heart, .white, Color(red: 1.0, green: 0.84, blue: 0.35), NeedStyle.heart, .white, Color(red: 1.0, green: 0.84, blue: 0.35)]
        for k in 0..<7 {
            let ang = Double(k) / 7 * 2 * .pi + 0.4
            let d = CGFloat(18 + 52 * (1 - (1 - u) * (1 - u)))
            let p = CGPoint(x: c.x + CGFloat(cos(ang)) * d, y: c.y + CGFloat(sin(ang)) * d * 0.8 - 18 * CGFloat(u))
            let r = CGFloat(7 + 5 * Double(k % 3)) * CGFloat(sin(.pi * min(u * 1.3, 1)))
            var path = Path()
            path.move(to: CGPoint(x: p.x, y: p.y - r)); path.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: p)
            path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: p); path.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: p)
            path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: p)
            ctx.fill(path, with: .color(colors[k].opacity(a)))
        }
    }
}
