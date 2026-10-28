//
//  OpeningArt.swift
//  The drawing for the game opening story (OpeningStory.swift): the night sky and stars, the dawn and the sun, parallax cloud layers, Wobble Isle
//  (a larger, more detailed take on the Around-town island art, no place labels), the Jelly Spring, the falling dewdrops and the four coloured
//  orbs. Everything is drawn in "world" units (a 400-wide design space, y down) through one camera (`OpeningCam`) so the 3D Jelbies, which are
//  separate views, can be placed on the same map (`OpeningProjector`). The island's own space starts at world y 690; the Spring is at its middle.
//

import SwiftUI

/// Where the camera is and how the sky looks. All of it eases between beats.
struct OpeningCam: Equatable {
    var cy: Double = 90          // world y under the anchor line
    var zoom: Double = 1
    var warm: Double = 0         // 0 deep night ... 1 pastel dawn
    var part: Double = 0         // the clouds parted, 0...1
    var hand: Double = 0         // the hand-off tint to the species picker's blue, 0...1

    var descend: Double { min(max((cy - 90) / 700, 0), 1) }

    static func mix(_ a: OpeningCam, _ b: OpeningCam, _ t: Double) -> OpeningCam {
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return OpeningCam(cy: l(a.cy, b.cy), zoom: l(a.zoom, b.zoom), warm: l(a.warm, b.warm), part: l(a.part, b.part), hand: l(a.hand, b.hand))
    }
}

/// World <-> screen for one frame.
struct OpeningProjector {
    static let islandY: Double = 690
    let size: CGSize
    let cam: OpeningCam
    let portrait: Bool
    let s: Double                // points per world unit at zoom 1
    let anchor: CGPoint          // the screen point the camera looks at
    var zs: Double { s * cam.zoom }

    init(size: CGSize, cam: OpeningCam) {
        self.size = size; self.cam = cam
        portrait = size.height >= size.width
        s = portrait ? Double(size.width) / 400 : Double(size.height) / 520
        anchor = CGPoint(x: size.width / 2, y: size.height * (portrait ? 0.40 : 0.44))
    }

    /// A point in the island's own space (the Spring is at 200, 100) on screen.
    func island(_ lx: Double, _ ly: Double, bob: Double) -> CGPoint {
        CGPoint(x: anchor.x + (lx - 200) * zs, y: anchor.y + (Self.islandY + ly + bob - cam.cy) * zs)
    }
}

struct OpeningDraw {
    var t: Double = 0                // ambient time (0 when motion is off)
    var motion = true
    var dropT: Double?               // seconds since the dewdrops began
    var giggleT: Double?             // seconds since the tap
    var shiver: Double = 0           // 0...1
    var home: Double = 0             // 0...1, the player's new house is picked out (beat 2)
    var gone: [Bool] = [false, false, false, false]       // the orb has popped
    var swell: [Double] = [0, 0, 0, 0]                    // 0...1, just before the pop
    var bob: Double { motion ? sin(t * 1.25) * 4 : 0 }
}

enum OArt {
    /// The four species colours in picker order (blue, yellow, purple, green), as the orbs.
    static let orbColors: [UInt32] = [0x79B7E6, 0xFFCB45, 0xAF8FE3, 0x7FCB9E]
    static let orbX: [Double] = [162, 187.5, 212.5, 238]
    static let orbY: [Double] = [104, 101, 101, 104]
    static let orbLand: [Double] = [2.8, 3.4, 4.0, 4.6]       // dropT at which each orb lands on the water

    // MARK: helpers

    static func hash(_ i: Int, _ k: Int = 0) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 7919 &+ k &* 104729 &+ 12345)
        x = x &* 6364136223846793005 &+ 1442695040888963407
        x ^= x >> 29; x = x &* 0x9E3779B97F4A7C15; x ^= x >> 32
        return Double(x >> 11) / Double(1 << 53)
    }
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double, _ o: Double = 1) -> Color {
        let t = min(max(t, 0), 1)
        func c(_ h: UInt32, _ sh: UInt32) -> Double { Double((h >> sh) & 0xFF) }
        return Color(red: (c(a, 16) * (1 - t) + c(b, 16) * t) / 255, green: (c(a, 8) * (1 - t) + c(b, 8) * t) / 255, blue: (c(a, 0) * (1 - t) + c(b, 0) * t) / 255).opacity(o)
    }
    static func C(_ h: UInt32, _ o: Double = 1) -> Color { Color(hex: h).opacity(o) }
    static func ell(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
    }
    static func smooth(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }
    static func star4(_ c: CGPoint, _ r: Double, squash: Double = 0.34) -> Path {
        var p = Path()
        let k = r * squash
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
        return p
    }
    static func drop(_ r: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -2.3 * r))
        p.addCurve(to: CGPoint(x: r, y: 0.3 * r), control1: CGPoint(x: 0.2 * r, y: -1.3 * r), control2: CGPoint(x: r, y: -0.4 * r))
        p.addCurve(to: CGPoint(x: -r, y: 0.3 * r), control1: CGPoint(x: r, y: 1.65 * r), control2: CGPoint(x: -r, y: 1.65 * r))
        p.addCurve(to: CGPoint(x: 0, y: -2.3 * r), control1: CGPoint(x: -r, y: -0.4 * r), control2: CGPoint(x: -0.2 * r, y: -1.3 * r))
        return p
    }

    // MARK: the whole scene

    static func scene(_ ctx: GraphicsContext, _ pr: OpeningProjector, _ f: OpeningDraw) {
        sky(ctx, pr)
        stars(ctx, pr, f)
        moon(ctx, pr)
        sun(ctx, pr, f)
        clouds(ctx, pr, f, layer: 0)
        clouds(ctx, pr, f, layer: 1)
        let reveal = smooth((pr.cam.part - 0.08) / 0.32)
        if reveal > 0.001 {
            var c = ctx
            c.opacity = reveal
            c.translateBy(x: pr.anchor.x, y: pr.anchor.y)
            c.scaleBy(x: pr.zs, y: pr.zs)
            c.translateBy(x: -200, y: -pr.cam.cy + OpeningProjector.islandY + f.bob)
            island(c, pr, f)
        }
        clouds(ctx, pr, f, layer: 2)
    }

    // MARK: sky

    static func sky(_ ctx: GraphicsContext, _ pr: OpeningProjector) {
        let w = pr.cam.warm
        let glow = max(w, pr.cam.descend * 0.4)
        let top = mix(0x070A2B, 0x7DB0EC, w)
        let mid = mix(0x1B2062, 0xF2C4DC, w)
        let low = mix(0x3E3B8C, 0xFFDDB2, glow)
        ctx.fill(Path(CGRect(origin: .zero, size: pr.size)), with: .linearGradient(
            Gradient(stops: [.init(color: top, location: 0), .init(color: mid, location: 0.58), .init(color: low, location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: pr.size.height)))
    }

    static func stars(_ ctx: GraphicsContext, _ pr: OpeningProjector, _ f: OpeningDraw) {
        let vis = pow(max(0, 1 - pr.cam.warm * 1.1), 1.4)
        guard vis > 0.01 else { return }
        let w = Double(pr.size.width), h = Double(pr.size.height)
        let shift = (pr.cam.cy - 90) * 0.07 * pr.s
        for i in 0..<120 {
            let x = hash(i, 1) * w
            let y = hash(i, 2) * h * 1.4 - h * 0.1 - shift
            guard y > -10, y < h + 10 else { continue }
            let tw = f.motion ? 0.55 + 0.45 * sin(f.t * (0.8 + hash(i, 3) * 2.4) + hash(i, 5) * 6.28) : 0.85
            let big = hash(i, 6) > 0.9
            let r = (0.7 + hash(i, 4) * 1.2) * (big ? 2.6 : 1) * max(0.8, pr.s)
            let col = hash(i, 7) > 0.5 ? C(0xFFF3D0, vis * tw) : C(0xD3E2FF, vis * tw)
            if big { ctx.fill(star4(CGPoint(x: x, y: y), r * 1.9), with: .color(col)) }
            else { ctx.fill(ell(x, y, r, r), with: .color(col)) }
        }
        // one shooting star early on
        if f.motion {
            let u = (f.t - 2.1) / 0.9
            if u > 0, u < 1 {
                let x0 = w * 0.85, y0 = h * 0.12 - shift
                let x = x0 - u * w * 0.5, y = y0 + u * h * 0.2
                var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + w * 0.12, y: y - h * 0.04))
                ctx.stroke(p, with: .linearGradient(Gradient(colors: [C(0xFFFFFF, (1 - u) * vis), C(0xFFFFFF, 0)]), startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + w * 0.12, y: y - h * 0.04)),
                           style: StrokeStyle(lineWidth: 2.2 * pr.s, lineCap: .round))
            }
        }
    }

    static func moon(_ ctx: GraphicsContext, _ pr: OpeningProjector) {
        let a = max(0, 1 - pr.cam.warm * 1.4)
        guard a > 0.01 else { return }
        let p = CGPoint(x: pr.anchor.x + (300 - 200) * pr.s, y: pr.anchor.y + (190 - pr.cam.cy * 0.3) * pr.s)
        guard p.y > -80, p.y < pr.size.height + 80 else { return }
        let r = 26 * pr.s
        var c = ctx
        c.opacity = a
        c.fill(ell(p.x, p.y, r * 3.2, r * 3.2), with: .radialGradient(Gradient(colors: [C(0xE8EBFF, 0.30), C(0xE8EBFF, 0)]), center: p, startRadius: 0, endRadius: r * 3.2))
        c.drawLayer { l in
            l.fill(ell(p.x, p.y, r, r), with: .color(C(0xFFF4D6)))
            l.blendMode = .destinationOut
            l.fill(ell(p.x + r * 0.5, p.y - r * 0.18, r * 0.88, r * 0.88), with: .color(.black))
        }
    }

    static func sun(_ ctx: GraphicsContext, _ pr: OpeningProjector, _ f: OpeningDraw) {
        let w = pr.cam.warm
        guard w > 0.01 else { return }
        let rise = smooth(w)
        let wy = 985 - (985 - 706) * rise
        let p = CGPoint(x: pr.anchor.x, y: pr.anchor.y + (wy - pr.cam.cy * 0.97) * pr.zs)
        let r = 46 * pr.zs
        var c = ctx
        c.opacity = min(1, w * 1.2)
        // wide warm glow
        c.fill(ell(p.x, p.y, r * 8, r * 6), with: .radialGradient(Gradient(colors: [C(0xFFE9B8, 0.85), C(0xFFC9B8, 0.35), C(0xFFC9B8, 0)]), center: p, startRadius: 0, endRadius: r * 7))
        // slow rays
        let spin = f.motion ? f.t * 0.03 : 0
        for i in 0..<14 where i % 2 == 0 {
            let a0 = Double.pi * 2 * Double(i) / 14 + spin, a1 = a0 + Double.pi * 2 / 28
            var ray = Path()
            ray.move(to: p)
            ray.addLine(to: CGPoint(x: p.x + cos(a0) * r * 14, y: p.y + sin(a0) * r * 14))
            ray.addLine(to: CGPoint(x: p.x + cos(a1) * r * 14, y: p.y + sin(a1) * r * 14))
            ray.closeSubpath()
            c.fill(ray, with: .radialGradient(Gradient(colors: [C(0xFFF6D8, 0.22), C(0xFFF6D8, 0)]), center: p, startRadius: r, endRadius: r * 12))
        }
        c.fill(ell(p.x, p.y, r * 1.5, r * 1.5), with: .radialGradient(Gradient(colors: [C(0xFFF6C8, 0.9), C(0xFFE08A, 0)]), center: p, startRadius: r * 0.7, endRadius: r * 1.5))
        c.fill(ell(p.x, p.y, r, r), with: .linearGradient(Gradient(colors: [C(0xFFFBE0), C(0xFFD58C)]), startPoint: CGPoint(x: p.x, y: p.y - r), endPoint: CGPoint(x: p.x, y: p.y + r)))
    }

    // MARK: clouds

    private static func cloud(_ ctx: GraphicsContext, _ p: CGPoint, w: Double, h: Double, top: Color, bottom: Color, alpha: Double) {
        guard alpha > 0.01 else { return }
        let puffs: [(Double, Double, Double, Double)] = [(-0.30, 0.08, 0.24, 0.30), (-0.10, -0.12, 0.26, 0.44), (0.16, -0.04, 0.28, 0.40), (0.36, 0.10, 0.20, 0.28), (0.02, 0.16, 0.52, 0.26)]
        var path = Path()
        for (dx, dy, rx, ry) in puffs { path.addEllipse(in: CGRect(x: p.x + dx * w - rx * w, y: p.y + dy * h - ry * h, width: 2 * rx * w, height: 2 * ry * h)) }
        var c = ctx
        c.opacity = alpha
        c.fill(path, with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: p.x, y: p.y - h * 0.5), endPoint: CGPoint(x: p.x, y: p.y + h * 0.42)))
    }

    /// layer 0 far (behind the island), 1 middle (behind), 2 near (in front: the bank that hides the island, then parts).
    static func clouds(_ ctx: GraphicsContext, _ pr: OpeningProjector, _ f: OpeningDraw, layer: Int) {
        let cam = pr.cam
        let par = [0.5, 0.8, 1.25][layer]
        let n = [9, 9, 7][layer]
        let wBase = [150.0, 210.0, 280.0][layer]
        let alpha0 = [0.72, 0.9, 0.96][layer]
        let night = [(0x676CB8 as UInt32, 0x2F3379 as UInt32), (0x7A7FC8, 0x373B86), (0x8F94D6, 0x424791)][layer]
        let dawn = [(0xFFF0F6 as UInt32, 0xE9C6E0 as UInt32), (0xFFFFFF, 0xF3D2E6), (0xFFFFFF, 0xF8DDEA)][layer]
        let top = mix(night.0, dawn.0, cam.warm), bottom = mix(night.1, dawn.1, cam.warm)
        let lo = par * 40 - 300, hi = par * 900 + 560
        let partK = [0.35, 0.8, 1.0][layer]
        let fade = layer == 2 ? (1 - smooth((cam.part - 0.1) / 0.7)) : (1 - 0.3 * cam.part)
        let count = layer == 2 ? n + 7 : n
        for i in 0..<count {
            var x: Double, y: Double, w: Double
            if layer == 2 && i >= n {
                // the bank: a blanket of big clouds that hides the island until the camera is through
                let j = i - n
                x = -40 + Double(j) * 75 + hash(i, 20) * 20
                y = 760 + (j % 2 == 0 ? 0 : 52) + hash(i, 21) * 14
                w = 330
            } else {
                x = hash(i, 10 + layer) * 520 - 60
                y = lo + (hi - lo) * (Double(i) + hash(i, 12 + layer)) / Double(n)
                w = wBase * (0.7 + hash(i, 14 + layer) * 0.6)
            }
            let sway = f.motion ? sin(f.t * (0.10 + 0.06 * hash(i, 16)) + hash(i, 17) * 6.28) * 16 : 0
            let dir: Double = x < 200 ? -1 : 1
            let shift = cam.part * dir * (330 + 90 * abs(x - 200) / 200) * partK
            let sp = CGPoint(x: pr.anchor.x + (x + sway + shift - 200) * pr.zs, y: pr.anchor.y + (y - cam.cy * par) * pr.zs)
            let h = w * 0.46
            guard sp.y > -h * pr.zs, sp.y < pr.size.height + h * pr.zs, sp.x > -w * pr.zs, sp.x < pr.size.width + w * pr.zs else { continue }
            cloud(ctx, sp, w: w * pr.zs, h: h * pr.zs, top: top, bottom: bottom, alpha: alpha0 * fade)
        }
    }

    // MARK: Wobble Isle (drawn in the island's own space, origin at world (0, 690))

    static func island(_ ctx: GraphicsContext, _ pr: OpeningProjector, _ f: OpeningDraw) {
        let t = f.t, warm = pr.cam.warm
        // glow under the island
        ctx.fill(ell(200, 150, 230, 90), with: .radialGradient(Gradient(colors: [C(0xFFD9C2, 0.28 * warm), C(0xFFD9C2, 0)]), center: CGPoint(x: 200, y: 150), startRadius: 0, endRadius: 230))
        // small floating rocks
        for (i, r) in [(0, (24.0, 222.0, 11.0)), (1, (372.0, 236.0, 8.0)), (2, (336.0, 306.0, 5.5)), (3, (60.0, 300.0, 6.0))] {
            let b = f.motion ? sin(t * 1.1 + Double(i) * 1.9) * 3 : 0
            let rk = ell(r.0, r.1 + b, r.2, r.2 * 0.72)
            ctx.fill(rk, with: .linearGradient(Gradient(colors: [C(0xC9A47A), C(0x8A6849)]), startPoint: CGPoint(x: r.0, y: r.1 - r.2), endPoint: CGPoint(x: r.0, y: r.1 + r.2)))
            ctx.fill(ell(r.0 - r.2 * 0.1, r.1 + b - r.2 * 0.46, r.2 * 0.7, r.2 * 0.26), with: .color(C(0x9FD7AE)))
        }
        underside(ctx, t, f.motion)
        // rim and grass, as in the Around-town art
        let rim = ell(200, 116, 184, 62)
        ctx.fill(rim, with: .color(C(0xD9B98F)))
        ctx.stroke(rim, with: .color(C(0xC7A276)), lineWidth: 2)
        ctx.fill(ell(200, 104, 184, 62), with: .linearGradient(Gradient(colors: [C(0xB9E5C2), C(0x9FD7AE)]), startPoint: CGPoint(x: 0, y: 42), endPoint: CGPoint(x: 0, y: 166)))
        ctx.fill(ell(200, 100, 158, 46), with: .color(C(0xC6EBCD, 0.6)))
        ctx.stroke(ell(200, 104, 183, 61), with: .linearGradient(Gradient(colors: [C(0xFFFFFF, 0.6), C(0xFFFFFF, 0)]), startPoint: CGPoint(x: 0, y: 42), endPoint: CGPoint(x: 0, y: 100)), lineWidth: 1.6)
        // dawn light on the grass
        ctx.fill(ell(200, 80, 150, 36), with: .radialGradient(Gradient(colors: [C(0xFFF3CF, 0.30 * warm), C(0xFFF3CF, 0)]), center: CGPoint(x: 200, y: 80), startRadius: 0, endRadius: 150))
        // back trees, houses, front trees (sorted by depth by hand)
        tree(ctx, 152, 62, 0.8, 0); tree(ctx, 258, 60, 0.82, 1); tree(ctx, 98, 76, 1.0, 2); tree(ctx, 306, 74, 1.05, 3)
        cottage(ctx, 66, 110, 1.0, roof: 0xF7B3C5)
        movingBoxes(ctx, f)
        cottage(ctx, 334, 108, 0.95, roof: 0x8CC4E6)
        tree(ctx, 40, 118, 1.15, 4); tree(ctx, 362, 124, 1.1, 5)
        // stepping stones to the Spring
        for (i, y) in [150.0, 141, 132].enumerated() {
            let x = 200 + [-6.0, 5, -3][i]
            ctx.fill(ell(x, y, 8 - Double(i) * 1.2, 3.2 - Double(i) * 0.4), with: .color(C(0xFFF8EC)))
            ctx.stroke(ell(x, y, 8 - Double(i) * 1.2, 3.2 - Double(i) * 0.4), with: .color(C(0xE6D6BC)), lineWidth: 0.8)
        }
        // flowers and tufts
        let flowers: [(Double, Double, UInt32)] = [(140, 128, 0xF7B3C5), (148, 134, 0xFFE07A), (252, 128, 0xFFF8EC), (260, 134, 0xF7B3C5), (110, 138, 0xFFE07A), (292, 140, 0xF7B3C5),
                                                    (176, 152, 0xFFF8EC), (226, 154, 0xFFE07A), (84, 128, 0xFFF8EC), (318, 130, 0xFFE07A), (128, 98, 0xF7B3C5), (278, 96, 0xFFF8EC), (200, 160, 0xF7B3C5)]
        for (x, y, c) in flowers {
            ctx.fill(ell(x, y + 1.4, 1.2, 0.5), with: .color(C(0x6FBF86)))
            for a in 0..<5 {
                let an = Double(a) * 1.2566
                ctx.fill(ell(x + cos(an) * 1.5, y + sin(an) * 1.1, 1.1, 0.9), with: .color(C(c)))
            }
            ctx.fill(ell(x, y, 0.8, 0.7), with: .color(C(0xFFC94D)))
        }
        spring(ctx, pr, f)
    }

    /// The player's new house (the pink one on the left): a couple of moving boxes by the door and, in beat 2, a soft pulsing glow and a bobbing star.
    private static func movingBoxes(_ ctx: GraphicsContext, _ f: OpeningDraw) {
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ rot: Double) {
            var c = ctx
            c.translateBy(x: x, y: y); c.rotate(by: .degrees(rot))
            c.fill(ell(0, 0.8, w * 0.7, 1.6), with: .color(Color(hex: 0x2E4A2E).opacity(0.18)))
            c.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h, width: w, height: h), cornerRadius: 1.2), with: .linearGradient(Gradient(colors: [C(0xDDB47E), C(0xC49A63)]), startPoint: CGPoint(x: 0, y: -h), endPoint: CGPoint(x: 0, y: 0)))
            c.fill(Path(CGRect(x: -1.1, y: -h, width: 2.2, height: h)), with: .color(C(0xF3E2BC, 0.9)))
        }
        box(90, 116, 11, 8, -3); box(100, 117, 8, 6, 5); box(92, 108, 7, 5, 2)
        guard f.home > 0.01 else { return }
        let pulse = f.motion ? 0.75 + 0.25 * sin(f.t * 3.2) : 1
        let a = f.home * pulse
        ctx.fill(ell(70, 100, 46, 34), with: .radialGradient(Gradient(colors: [C(0xFFF0B0, 0.55 * a), C(0xFFF0B0, 0)]), center: CGPoint(x: 70, y: 100), startRadius: 0, endRadius: 46))
        let bob = f.motion ? sin(f.t * 3.2) * 2 : 0
        ctx.fill(star4(CGPoint(x: 66, y: 70 + bob), 5.5 * f.home, squash: 0.25), with: .color(C(0xFFFFFF, f.home)))
        ctx.fill(star4(CGPoint(x: 78, y: 78 - bob), 3 * f.home, squash: 0.25), with: .color(C(0xFFE07A, f.home)))
    }

    private static func underside(_ ctx: GraphicsContext, _ t: Double, _ motion: Bool) {
        var rock = Path()
        rock.move(to: CGPoint(x: 16, y: 118))
        rock.addCurve(to: CGPoint(x: 72, y: 196), control1: CGPoint(x: 18, y: 152), control2: CGPoint(x: 42, y: 178))
        rock.addCurve(to: CGPoint(x: 128, y: 244), control1: CGPoint(x: 94, y: 212), control2: CGPoint(x: 110, y: 230))
        rock.addLine(to: CGPoint(x: 140, y: 238))
        rock.addCurve(to: CGPoint(x: 176, y: 290), control1: CGPoint(x: 150, y: 256), control2: CGPoint(x: 166, y: 274))
        rock.addCurve(to: CGPoint(x: 203, y: 336), control1: CGPoint(x: 184, y: 304), control2: CGPoint(x: 196, y: 322))
        rock.addCurve(to: CGPoint(x: 232, y: 284), control1: CGPoint(x: 211, y: 318), control2: CGPoint(x: 224, y: 300))
        rock.addCurve(to: CGPoint(x: 262, y: 252), control1: CGPoint(x: 240, y: 270), control2: CGPoint(x: 252, y: 260))
        rock.addLine(to: CGPoint(x: 276, y: 258))
        rock.addCurve(to: CGPoint(x: 332, y: 200), control1: CGPoint(x: 296, y: 240), control2: CGPoint(x: 316, y: 224))
        rock.addCurve(to: CGPoint(x: 384, y: 118), control1: CGPoint(x: 362, y: 182), control2: CGPoint(x: 382, y: 152))
        rock.closeSubpath()
        ctx.fill(rock, with: .linearGradient(Gradient(colors: [C(0xCBA67C), C(0xA37F5C), C(0x7A5A44)]), startPoint: CGPoint(x: 0, y: 118), endPoint: CGPoint(x: 0, y: 336)))
        ctx.drawLayer { l in
            l.clip(to: rock)
            l.fill(Path(CGRect(x: 200, y: 100, width: 200, height: 260)), with: .linearGradient(Gradient(colors: [C(0x4B3426, 0), C(0x4B3426, 0.38)]), startPoint: CGPoint(x: 200, y: 0), endPoint: CGPoint(x: 384, y: 0)))
            for (i, y) in [150.0, 182, 214, 246, 276].enumerated() {
                var arc = Path()
                arc.addEllipse(in: CGRect(x: 200 - (190 - Double(i) * 30), y: y - 26, width: 2 * (190 - Double(i) * 30), height: 52))
                l.stroke(arc, with: .color(C(0xE2C79F, 0.28)), lineWidth: 1.6)
            }
            for (x, y, r) in [(80.0, 170.0, 5.0), (150.0, 205.0, 4.0), (262.0, 200.0, 6.0), (210.0, 262.0, 4.0), (310.0, 160.0, 4.0)] {
                l.fill(ell(x, y, r, r * 0.7), with: .color(C(0x6B4D38, 0.22)))
            }
        }
        // hanging vines
        for (i, x) in [58.0, 112, 292, 340].enumerated() {
            let len = 34.0 + Double(i % 2) * 18
            let sway = motion ? sin(t * 1.3 + Double(i)) * 2.2 : 0
            var v = Path()
            v.move(to: CGPoint(x: x, y: 160 + (i % 2 == 0 ? 0 : 10)))
            v.addQuadCurve(to: CGPoint(x: x + sway, y: 160 + len), control: CGPoint(x: x + 6 + sway * 0.5, y: 160 + len * 0.5))
            ctx.stroke(v, with: .color(C(0x5FB37A)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            for k in 1...3 {
                let u = Double(k) / 3.4
                ctx.fill(ell(x + sway * u + (k % 2 == 0 ? 3 : -3), 160 + len * u, 3.2, 1.9), with: .color(C(0x7FCB94)))
            }
        }
        // a thin waterfall off the front-left edge, with a little mist
        let fx = 96.0
        var fall = Path()
        fall.move(to: CGPoint(x: fx - 3, y: 160)); fall.addLine(to: CGPoint(x: fx + 3, y: 160))
        fall.addLine(to: CGPoint(x: fx + 1.5, y: 262)); fall.addLine(to: CGPoint(x: fx - 1.5, y: 262)); fall.closeSubpath()
        ctx.fill(fall, with: .linearGradient(Gradient(colors: [C(0xB8EBF7, 0.9), C(0xB8EBF7, 0)]), startPoint: CGPoint(x: fx, y: 160), endPoint: CGPoint(x: fx, y: 262)))
        if motion {
            for k in 0..<5 {
                let u = (t * 0.7 + Double(k) * 0.2).truncatingRemainder(dividingBy: 1)
                ctx.fill(ell(fx + sin(Double(k) * 3) * 1.2, 160 + u * 100, 1.4, 2.6), with: .color(C(0xFFFFFF, 0.8 * (1 - u))))
            }
        }
        ctx.fill(ell(fx, 266, 12, 5), with: .radialGradient(Gradient(colors: [C(0xFFFFFF, 0.45), C(0xFFFFFF, 0)]), center: CGPoint(x: fx, y: 266), startRadius: 0, endRadius: 12))
    }

    private static func tree(_ ctx: GraphicsContext, _ x: Double, _ y: Double, _ s: Double, _ seed: Int) {
        ctx.fill(ell(x, y + 1, 12 * s, 3.4 * s), with: .color(Color(hex: 0x2E4A2E).opacity(0.16)))
        ctx.fill(Path(roundedRect: CGRect(x: x - 2 * s, y: y - 11 * s, width: 4 * s, height: 12 * s), cornerRadius: 1.6 * s), with: .color(C(0x9B7653)))
        let greens: [(UInt32, UInt32)] = [(0x6FC08A, 0x92D8A6), (0x7BCB93, 0xA0E0B0), (0x68B884, 0x8CD3A0)]
        let g = greens[seed % 3]
        ctx.fill(ell(x - 6 * s, y - 15 * s, 8 * s, 7.5 * s), with: .color(C(g.0)))
        ctx.fill(ell(x + 6 * s, y - 15 * s, 8 * s, 7.5 * s), with: .color(C(g.0)))
        ctx.fill(ell(x, y - 21 * s, 10.5 * s, 9.5 * s), with: .color(C(g.0)))
        ctx.fill(ell(x - 2.5 * s, y - 23 * s, 6 * s, 4.8 * s), with: .color(C(g.1, 0.9)))
        if seed % 2 == 0 { ctx.fill(ell(x + 5 * s, y - 19 * s, 1.5 * s, 1.5 * s), with: .color(C(0xF7B3C5))) }
    }

    private static func cottage(_ ctx: GraphicsContext, _ x: Double, _ y: Double, _ s: Double, roof: UInt32) {
        ctx.fill(ell(x, y + 1, 18 * s, 4 * s), with: .color(Color(hex: 0x2E4A2E).opacity(0.16)))
        ctx.fill(Path(roundedRect: CGRect(x: x - 12 * s, y: y - 15 * s, width: 24 * s, height: 16 * s), cornerRadius: 2.4 * s), with: .color(C(0xFFF8EC)))
        var r = Path()
        r.move(to: CGPoint(x: x - 16 * s, y: y - 13 * s)); r.addLine(to: CGPoint(x: x, y: y - 27 * s)); r.addLine(to: CGPoint(x: x + 16 * s, y: y - 13 * s)); r.closeSubpath()
        ctx.fill(r, with: .color(C(roof)))
        ctx.stroke(r, with: .color(C(0xFFFFFF, 0.7)), style: StrokeStyle(lineWidth: 1.2 * s, lineJoin: .round))
        ctx.fill(Path(roundedRect: CGRect(x: x - 2.4 * s, y: y - 9 * s, width: 5 * s, height: 10 * s), cornerRadius: 2 * s), with: .color(C(0xB58D67)))
        ctx.fill(ell(x - 7.5 * s, y - 8 * s, 2.2 * s, 2.2 * s), with: .color(C(0xFFE07A)))
        ctx.fill(ell(x + 7.5 * s, y - 8 * s, 2.2 * s, 2.2 * s), with: .color(C(0xFFE07A)))
    }

    // MARK: the Jelly Spring and its dewdrops

    private static func spring(_ ctx: GraphicsContext, _ pr: OpeningProjector, _ f: OpeningDraw) {
        let t = f.t
        let beam = f.dropT.map { smooth($0 / 2.5) } ?? 0
        // the glow the pool throws up, and a faint column of light the drops fall through
        let pulse = f.motion ? 0.85 + 0.15 * sin(t * 1.7) : 1
        ctx.fill(ell(200, 98, 130, 46), with: .radialGradient(Gradient(colors: [C(0xBFF2FF, 0.55 * pulse), C(0xBFF2FF, 0)]), center: CGPoint(x: 200, y: 98), startRadius: 0, endRadius: 130))
        if beam > 0 {
            var col = Path()
            col.move(to: CGPoint(x: 160, y: -260)); col.addLine(to: CGPoint(x: 240, y: -260)); col.addLine(to: CGPoint(x: 262, y: 98)); col.addLine(to: CGPoint(x: 138, y: 98)); col.closeSubpath()
            ctx.fill(col, with: .linearGradient(Gradient(colors: [C(0xFFFFFF, 0), C(0xE6FBFF, 0.16 * beam)]), startPoint: CGPoint(x: 0, y: -260), endPoint: CGPoint(x: 0, y: 98)))
        }
        // stone ring
        ctx.fill(ell(200, 103, 72, 23), with: .color(Color(hex: 0x3C5A3C).opacity(0.15)))
        ctx.fill(ell(200, 101, 70, 22), with: .linearGradient(Gradient(colors: [C(0xFFFBF2), C(0xEADCC4)]), startPoint: CGPoint(x: 0, y: 79), endPoint: CGPoint(x: 0, y: 123)))
        for i in 0..<16 {
            let a = Double(i) / 16 * .pi * 2
            ctx.fill(ell(200 + cos(a) * 66, 101 + sin(a) * 20.5, 5.2, 2.7), with: .color(i % 2 == 0 ? C(0xFFF8EC) : C(0xF2E6D2)))
        }
        // water
        ctx.fill(ell(200, 100, 61, 17.5), with: .linearGradient(Gradient(colors: [C(0xA6E8F2), C(0x66BBE6), C(0x4FA6DB)]), startPoint: CGPoint(x: 0, y: 82), endPoint: CGPoint(x: 0, y: 118)))
        ctx.fill(ell(200, 96, 46, 10), with: .radialGradient(Gradient(colors: [C(0xFFFFFF, 0.55), C(0xFFFFFF, 0)]), center: CGPoint(x: 200, y: 96), startRadius: 0, endRadius: 46))
        for i in 0..<3 {
            let u = f.motion ? (t * 0.25 + Double(i) / 3).truncatingRemainder(dividingBy: 1) : Double(i) / 3
            ctx.stroke(ell(200, 100, 14 + u * 44, 4 + u * 12), with: .color(C(0xFFFFFF, 0.35 * (1 - u))), lineWidth: 1.1)
        }
        // glitter
        for i in 0..<12 {
            let a = hash(i, 40) * .pi * 2, rr = sqrt(hash(i, 41)) * 0.86
            let tw = f.motion ? max(0, sin(t * (1.2 + hash(i, 42) * 1.8) + hash(i, 43) * 6.28)) : 0.6
            guard tw > 0.05 else { continue }
            ctx.fill(star4(CGPoint(x: 200 + cos(a) * 58 * rr, y: 100 + sin(a) * 16 * rr), 2.0 + 2.6 * tw, squash: 0.2), with: .color(C(0xFFFFFF, 0.9 * tw)))
        }
        // ripples from the giggle
        if let g = f.giggleT {
            for k in 0..<4 {
                for j in 0..<2 {
                    let age = g - Double(k) * 0.09 - Double(j) * 0.38
                    guard age > 0, age < 1.8 else { continue }
                    let u = age / 1.8
                    ctx.stroke(ell(orbX[k], orbY[k] + 4, 6 + u * 46, 2 + u * 14), with: .color(C(0xFFFFFF, 0.7 * (1 - u))), lineWidth: 1.5 * (1 - u) + 0.4)
                }
            }
        }
        guard let dt = f.dropT else { return }
        // the snow of dewdrops
        let nSnow = 30
        for i in 0..<nSnow {
            let period = 8.5 + hash(i, 50) * 3
            let ph = (dt + 1.8 + hash(i, 51) * period).truncatingRemainder(dividingBy: period)
            let fall = 6.2
            let ang = hash(i, 52) * .pi * 2, rr = sqrt(hash(i, 53)) * 0.8
            let tx = 200 + cos(ang) * 58 * rr, ty = 100 + sin(ang) * 15.5 * rr
            let x0 = 200 + (hash(i, 54) * 2 - 1) * 105
            let r = 1.8 + hash(i, 55) * 2.2
            if ph < fall {
                let u = ph / fall
                let x = x0 + (tx - x0) * u * u + sin(ph * 1.6 + hash(i, 56) * 6) * 7 * (1 - u)
                let y = -250 + (ty + 250) * (0.25 * u + 0.75 * u * u)
                let a = min(1, ph / 0.8)
                dew(ctx, CGPoint(x: x, y: y), r, a, tear: 1 - u * 0.85)
            } else {
                let u = (ph - fall) / (period - fall)         // sits and fades on the water
                let a = u < 0.55 ? 1 : max(0, 1 - (u - 0.55) / 0.45)
                dew(ctx, CGPoint(x: tx, y: ty - 1.2 + (f.motion ? sin(t * 2 + Double(i)) * 0.5 : 0)), r * 0.9, a * 0.85, tear: 0)
                if u < 0.35 {
                    let g = u / 0.35
                    ctx.stroke(ell(tx, ty + 1, 2 + g * 12, 0.8 + g * 3.4), with: .color(C(0xFFFFFF, 0.6 * (1 - g))), lineWidth: 0.9)
                }
            }
        }
        // the four coloured orbs
        for k in 0..<4 where !f.gone[k] {
            let start = Double(k) * 0.6 + 0.2, land = orbLand[k]
            guard dt > start else { continue }
            let col = orbColors[k]
            var x = orbX[k], y: Double
            let tearOn: Double
            if dt < land {
                let u = (dt - start) / (land - start)
                y = -230 + (orbY[k] - 8 + 230) * (0.2 * u + 0.8 * u * u)
                x += sin(u * 5 + Double(k)) * 9 * (1 - u)
                tearOn = 1 - u * 0.9
            } else {
                y = orbY[k] - 9 + (f.motion ? sin(t * 2.1 + Double(k) * 1.3) * 1.6 : 0)
                tearOn = 0
                let sinceLand = dt - land
                if sinceLand < 0.9 {                  // a landing ring
                    let g = sinceLand / 0.9
                    ctx.stroke(ell(orbX[k], orbY[k] + 3, 4 + g * 28, 1.6 + g * 8), with: .color(C(col, 0.8 * (1 - g))), lineWidth: 1.4)
                }
            }
            var sq = 1.0
            if dt >= land, f.motion {
                if f.shiver > 0 { x += sin(t * 52 + Double(k) * 2) * 1.4 * f.shiver; y += cos(t * 61 + Double(k)) * 0.6 * f.shiver }
                if let g0 = f.giggleT {
                    let g = g0 - Double(k) * 0.06
                    if g > 0 { y -= abs(sin(g * 8.5)) * 16 * exp(-g * 1.7); sq = 1 + 0.16 * sin(g * 17) * exp(-g * 2.2) }
                }
            }
            let swell = 1 + 0.45 * f.swell[k]
            orb(ctx, CGPoint(x: x, y: y), col: col, tear: tearOn, squash: sq, swell: swell, glow: 1 + f.swell[k] * 1.4, t: t)
        }
    }

    private static func dew(_ ctx: GraphicsContext, _ p: CGPoint, _ r: Double, _ a: Double, tear: Double) {
        guard a > 0.01 else { return }
        var c = ctx
        c.opacity = a
        c.fill(ell(p.x, p.y, r * 4.2, r * 4.2), with: .radialGradient(Gradient(colors: [C(0xDFF7FF, 0.55), C(0xDFF7FF, 0)]), center: p, startRadius: 0, endRadius: r * 4.2))
        if tear > 0.05 {
            c.translateBy(x: p.x, y: p.y)
            c.scaleBy(x: 1, y: 0.4 + 0.6 * tear)
            c.fill(drop(r), with: .color(C(0xF2FDFF)))
        } else {
            c.fill(ell(p.x, p.y, r, r), with: .color(C(0xF2FDFF)))
        }
    }

    static func orb(_ ctx: GraphicsContext, _ p: CGPoint, col: UInt32, tear: Double, squash: Double, swell: Double, glow: Double, t: Double) {
        let r = 8.2 * swell
        var c = ctx
        c.fill(ell(p.x, p.y, r * 3.6 * glow, r * 3.6 * glow), with: .radialGradient(Gradient(colors: [C(col, 0.55), C(col, 0)]), center: p, startRadius: 0, endRadius: r * 3.6 * glow))
        c.translateBy(x: p.x, y: p.y)
        c.scaleBy(x: 1 / squash, y: squash)
        if tear > 0.05 {
            c.scaleBy(x: 1, y: 0.45 + 0.55 * tear)
            c.fill(drop(r), with: .linearGradient(Gradient(colors: [C(0xFFFFFF), C(col)]), startPoint: CGPoint(x: 0, y: -2 * r), endPoint: CGPoint(x: 0, y: r)))
        } else {
            c.fill(ell(0, 0, r, r), with: .radialGradient(Gradient(colors: [C(0xFFFFFF, 0.95), C(col), mix(col, 0x4A3A7A, 0.25)]), center: CGPoint(x: -r * 0.3, y: -r * 0.35), startRadius: 0, endRadius: r * 1.25))
            c.stroke(ell(0, 0, r, r), with: .color(C(0xFFFFFF, 0.7)), lineWidth: 1)
            c.fill(ell(-r * 0.36, -r * 0.42, r * 0.28, r * 0.2), with: .color(C(0xFFFFFF, 0.95)))
        }
    }
}


/// Beat 6's tiny badges (centred on the origin, `d` points across): 0 a checkered flag (races), 1 a star on a ribbon (shows), 2 a volleyball.
enum OpeningIcons {
    static func badge(_ ctx: GraphicsContext, _ i: Int, d: Double) {
        let r = d / 2
        func C(_ h: UInt32, _ o: Double = 1) -> Color { OArt.C(h, o) }
        ctx.fill(OArt.ell(0, r * 0.12, r, r), with: .color(Color(hex: 0x2A2060).opacity(0.22)))
        ctx.fill(OArt.ell(0, 0, r, r), with: .linearGradient(Gradient(colors: [C(0xFFFFFF), C([0xFFE9F0, 0xFFF3CF, 0xE3F3FF][i])]), startPoint: CGPoint(x: 0, y: -r), endPoint: CGPoint(x: 0, y: r)))
        ctx.stroke(OArt.ell(0, 0, r, r), with: .color(C(0xFFFFFF, 0.9)), lineWidth: 2)
        let k = r / 24                      // the drawings below are in a 48-unit space
        switch i {
        case 0:
            // pole and a waving checkered pennant
            var pole = Path(); pole.move(to: CGPoint(x: -9 * k, y: 15 * k)); pole.addLine(to: CGPoint(x: -9 * k, y: -15 * k))
            ctx.stroke(pole, with: .color(C(0x4D331F)), style: StrokeStyle(lineWidth: 2.6 * k, lineCap: .round))
            let cols = 4, rows = 3, cw = 6.4 * k, ch = 5.4 * k
            for rr in 0..<rows { for cc in 0..<cols {
                let x = -7.5 * k + Double(cc) * cw, y = -14 * k + Double(rr) * ch + sin(Double(cc) * 0.9) * 1.2 * k
                ctx.fill(Path(CGRect(x: x, y: y, width: cw, height: ch)), with: .color((rr + cc) % 2 == 0 ? C(0x4D331F) : C(0xFFFFFF)))
            } }
            ctx.stroke(Path(CGRect(x: -7.5 * k, y: -14 * k, width: Double(cols) * cw, height: Double(rows) * ch + 2.4 * k)), with: .color(C(0x4D331F, 0.25)), lineWidth: 0.8)
        case 1:
            // ribbon tails and a gold star
            for s in [-1.0, 1.0] {
                var t = Path()
                t.move(to: CGPoint(x: s * 3 * k, y: 4 * k)); t.addLine(to: CGPoint(x: s * 13 * k, y: 4 * k)); t.addLine(to: CGPoint(x: s * 9 * k, y: 17 * k))
                t.addLine(to: CGPoint(x: s * 5 * k, y: 12 * k)); t.addLine(to: CGPoint(x: s * 1 * k, y: 17 * k)); t.closeSubpath()
                ctx.fill(t, with: .color(C(0xEE96AC)))
            }
            var star = Path()
            for n in 0..<10 {
                let a = -Double.pi / 2 + Double(n) * .pi / 5, rad = n % 2 == 0 ? 12.5 * k : 5.4 * k
                let p = CGPoint(x: cos(a) * rad, y: -4 * k + sin(a) * rad)
                if n == 0 { star.move(to: p) } else { star.addLine(to: p) }
            }
            star.closeSubpath()
            ctx.fill(star, with: .linearGradient(Gradient(colors: [C(0xFFE07A), C(0xF9CC59)]), startPoint: CGPoint(x: 0, y: -16 * k), endPoint: CGPoint(x: 0, y: 8 * k)))
            ctx.stroke(star, with: .color(C(0xE0A92E)), style: StrokeStyle(lineWidth: 1.2 * k, lineJoin: .round))
        default:
            // a volleyball: white with three curved panels
            ctx.fill(OArt.ell(0, 0, 15 * k, 15 * k), with: .radialGradient(Gradient(colors: [C(0xFFFFFF), C(0xF2F2F2)]), center: CGPoint(x: -4 * k, y: -5 * k), startRadius: 0, endRadius: 20 * k))
            ctx.stroke(OArt.ell(0, 0, 15 * k, 15 * k), with: .color(C(0x4D331F, 0.55)), lineWidth: 1.4 * k)
            // three seams, like a volleyball's panels
            var seam = Path()
            seam.move(to: CGPoint(x: -13 * k, y: -6 * k)); seam.addQuadCurve(to: CGPoint(x: 13 * k, y: -6 * k), control: CGPoint(x: 0, y: 6 * k))
            ctx.stroke(seam, with: .color(C(0x79B7E6, 0.9)), style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round))
            var seam2 = Path()
            seam2.move(to: CGPoint(x: -12 * k, y: 8 * k)); seam2.addQuadCurve(to: CGPoint(x: 12 * k, y: 8 * k), control: CGPoint(x: 0, y: -4 * k))
            ctx.stroke(seam2, with: .color(C(0xFFCB45, 0.95)), style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round))
            var seam3 = Path()
            seam3.move(to: CGPoint(x: 1 * k, y: -15 * k)); seam3.addQuadCurve(to: CGPoint(x: 1 * k, y: 15 * k), control: CGPoint(x: 9 * k, y: 0))
            ctx.stroke(seam3, with: .color(C(0x79B7E6, 0.9)), style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round))
        }
    }
}
