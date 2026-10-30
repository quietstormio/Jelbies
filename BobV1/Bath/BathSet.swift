//
//  BathSet.swift
//  The Bath SET: where Bob stands, the close-up camera, and the per-frame props drawn over him (lint bits stuck to his skin, the held
//  tool, sud bubbles, spray droplets). Static meshes live in BathModels.swift; shading in BathShaders.metal; drawing in RoomRenderer.
//
//  Chosen layout (world: y up, floor = xz, +z toward the camera):
//    basin (Bob's shallow wash tub)  centre (0, 1.0), outer radius 1.12, rim top y 0.37, water y 0.17 (ankle height)
//    standPoint                      (0, 0.17, 1.0)  floor xz + water height. Bob's feet rest on the basin bottom at y ~ 0.02, so the
//                                    flow should put his root at standPoint.xz and y = 0 (the water is a see-through disc over his ankles).
//    bathroom (modern luxury: stone, oak, brass)  back wall z = -2, side walls x = +-3.4, ceiling y 8.0 (above the game camera eye), floor out to z = 14.5 (fills the whole frame,
//                                    also from the living-room camera if the camera blends out)
//    rain shower head                showerNozzle (0, 2.85, -1.0): a good spray origin
//  Close-up camera (`closeUpPose`): target (0, 0.80, 1.0), elevation 0.36 rad, distance so ~2.6 world units are visible across the
//  screen (Bob ~54% of the width): for a 440x956 portrait aspect that is about eye (0, 3.5, 9.9), target (0, 0.8, 1.0).
//

import simd
import Foundation

nonisolated enum BathSet {
    static let standPoint = SIMD3<Float>(BathModels.basinCentre.x, BathModels.waterY, BathModels.basinCentre.y)
    static let showerNozzle = SIMD3<Float>(0, 2.85, BathModels.backZ + 1.0)
    static let closeUpVisibleWidth: Float = 2.6
    static let closeUpElevation: Float = 0.36
    static let closeUpTargetY: Float = 0.80
    /// Rest-frame body centre the foam grid is measured from (the shader and BathLook directions use this).
    static var bodyCentre: SIMD3<Float> { SIMD3(0, 0.5 * BlobShape.H, 0) }

    static func closeUpPose(aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let visH = closeUpVisibleWidth / max(aspect, 0.2)
        let dist = visH / (2 * tanf(GameCamera.fovY / 2))
        let t = SIMD3<Float>(standPoint.x, closeUpTargetY, standPoint.z)
        let e = t + SIMD3<Float>(0, sinf(closeUpElevation), cosf(closeUpElevation)) * dist
        return (e, t)
    }

    static func closeUpCamera(aspect: Float) -> CameraState {
        let p = closeUpPose(aspect: aspect)
        var c = CameraState()
        c.view = M4.lookAt(eye: p.eye, at: p.target, up: SIMD3(0, 1, 0))
        c.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.3, far: 60), c.view)
        c.invViewProj = M4.invert(c.viewProj)
        c.pos = p.eye
        c.fwd = simd_normalize(p.target - p.eye)
        return c
    }
}

// MARK: - per-frame props

/// Builds the small meshes drawn over Bob each frame into one reusable soup (no allocation once warm).
nonisolated final class BathOverlay {
    private(set) var soup = BathSoup()
    var isEmpty: Bool { soup.i.isEmpty }
    static let sparkleSpots = 32
    static let maxLint = 10, maxBubbles = 48, sprayDrops = 30

    private struct Frame {
        var o: SIMD3<Float>, t: SIMD3<Float>, b: SIMD3<Float>, n: SIMD3<Float>, s: Float
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { o + (t * x + b * y + n * z) * s }
        func a(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { (t * x + b * y + n * z) * s }
    }

    /// Fills the soup. `attach(i, bit)` returns the deformed surface point and normal for lint bit `i` (nil = not placeable).
    func compose(look: BathLook, time: Float, camRight: SIMD3<Float> = SIMD3(1, 0, 0), camUp: SIMD3<Float> = SIMD3(0, 1, 0),
                 sparkleAt: ((Int) -> (p: SIMD3<Float>, n: SIMD3<Float>)?)? = nil,
                 attach: (Int, LintBit) -> (p: SIMD3<Float>, n: SIMD3<Float>)?) {
        soup.clear()
        for (k, bit) in look.lint.prefix(Self.maxLint).enumerated() where bit.peel < 0.999 {
            guard let at = attach(k, bit) else { continue }
            addLint(bit, at: at.p, normal: at.n, tool: look.toolAt, time: time)
        }
        if look.tool != .none, look.tool != .rinse, let at = look.toolAt { addTool(look.tool, at: at, time: time) }
        if let nz = look.spray { addSpray(from: nz, time: time) }
        for b in look.bubbles.prefix(Self.maxBubbles) where b.w > 0.003 {
            soup.sphere(SIMD3(b.x, b.y, b.z), b.w, color: .zero, mat: .bubble, alpha: 1, rings: 4, segs: 8)
        }
        if look.sparkle > 0.02, let sparkleAt { addStars(count: Int((look.sparkle * 16).rounded(.up)), time: time, right: camRight, up: camUp, at: sparkleAt) }
        if soup.v.isEmpty { bounds = nil; return }
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for x in soup.v { let p = SIMD3(x.pos.x, x.pos.y, x.pos.z); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        bounds = (lo, hi)
    }

    /// World AABB of this frame's props (the room cache re-shades it), nil when there are none.
    private(set) var bounds: (lo: SIMD3<Float>, hi: SIMD3<Float>)?

    // MARK: lint

    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }

    private func addLint(_ bit: LintBit, at p: SIMD3<Float>, normal n0: SIMD3<Float>, tool: SIMD3<Float>?, time: Float) {
        var n = simd_normalize(n0)
        let q = min(max(bit.peel, 0), 1)
        // the bit lifts toward the roller (or up), curls, then shrinks out
        var o = p + n * (0.012 * bit.size / 0.1)
        if q > 0 {
            let dir = tool.map { simd_normalize($0 - p) } ?? SIMD3<Float>(0, 1, 0)
            o += (n * 0.30 + dir * 0.55) * q * (bit.size / 0.1) * 0.6
            n = simd_normalize(n + (dir - n * simd_dot(dir, n)) * q * 1.3)
        }
        let ref: SIMD3<Float> = abs(n.y) < 0.92 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        var t = simd_normalize(simd_cross(ref, n))
        var b = simd_cross(n, t)
        let cs = cosf(bit.spin + q * 2.0), sn = sinf(bit.spin + q * 2.0)
        let t2 = t * cs + b * sn
        b = b * cs - t * sn
        t = t2
        let sc = bit.size * 1.3 * (1 - Self.smooth(0.7, 1.0, q))
        let f = Frame(o: o, t: t, b: b, n: n, s: sc)
        switch bit.kind {
        case .dust: dust(f)
        case .crumb: crumb(f)
        case .leaf: leaf(f, curl: 0.25 + q * 1.4)
        case .glitter: glitter(f)
        case .fuzz: fuzz(f)
        case .drop: drop(f)
        }
    }

    private func dust(_ f: Frame) {
        let g = bathLin(0.66, 0.65, 0.68), g2 = bathLin(0.80, 0.79, 0.82), g3 = bathLin(0.54, 0.53, 0.57)
        soup.ellipsoid(f.p(0, 0, 0.25), ax: f.a(0.55, 0, 0), ay: f.a(0, 0.5, 0), az: f.a(0, 0, 0.3), color: g, mat: .fabric, rings: 3, segs: 7)
        let spots: [(Float, Float, Float, Float)] = [(0.42, 0.18, 0.3, 0.26), (-0.4, 0.22, 0.32, 0.25), (0.1, -0.45, 0.28, 0.27), (-0.15, 0.42, 0.34, 0.22), (0.36, -0.3, 0.38, 0.2), (-0.38, -0.25, 0.3, 0.23)]
        for (k, s) in spots.enumerated() {
            soup.ellipsoid(f.p(s.0, s.1, s.2), ax: f.a(s.3, 0, 0), ay: f.a(0, s.3, 0), az: f.a(0, 0, s.3 * 0.9), color: k % 3 == 0 ? g2 : (k % 3 == 1 ? g : g3), mat: .fabric, rings: 3, segs: 6)
        }
        // a few stray hairs
        soup.ellipsoid(f.p(0.55, -0.1, 0.4), ax: f.a(0.45, 0.05, 0), ay: f.a(0, 0.04, 0), az: f.a(0, 0, 0.04), color: g3, mat: .fabric, rings: 2, segs: 4)
        soup.ellipsoid(f.p(-0.5, 0.3, 0.42), ax: f.a(0.4, -0.08, 0), ay: f.a(0, 0.04, 0), az: f.a(0, 0, 0.04), color: g3, mat: .fabric, rings: 2, segs: 4)
    }

    private func crumb(_ f: Frame) {
        let c = bathLin(0.80, 0.58, 0.32), d = bathLin(0.62, 0.40, 0.2), l = bathLin(0.92, 0.72, 0.45)
        soup.ellipsoid(f.p(0, 0, 0.14), ax: f.a(0.5, 0.1, 0), ay: f.a(-0.1, 0.4, 0), az: f.a(0, 0, 0.22), color: c, mat: .matte, rings: 3, segs: 7)
        soup.ellipsoid(f.p(0.32, 0.2, 0.12), ax: f.a(0.24, 0, 0), ay: f.a(0, 0.2, 0), az: f.a(0, 0, 0.16), color: l, mat: .matte, rings: 3, segs: 6)
        soup.ellipsoid(f.p(-0.3, -0.18, 0.1), ax: f.a(0.2, 0, 0), ay: f.a(0, 0.17, 0), az: f.a(0, 0, 0.13), color: d, mat: .matte, rings: 3, segs: 6)
        soup.ellipsoid(f.p(0.05, -0.02, 0.3), ax: f.a(0.1, 0, 0), ay: f.a(0, 0.08, 0), az: f.a(0, 0, 0.05), color: d, mat: .matte, rings: 2, segs: 5)
    }

    private func leaf(_ f: Frame, curl: Float) {
        // a pointed oval, green at the stem and orange at the tip, double sided, lifting at the edges and curling with `curl`
        let cu = 7, cv = 4
        let len: Float = 2.5
        func pos(_ u: Float, _ v: Float) -> SIMD3<Float> {
            let w = 0.5 * powf(sinf(.pi * min(max(u, 0.001), 0.999)), 0.75) * (1 - 0.25 * u)
            let x = (u - 0.5) * len, y = v * w
            let z = 0.07 + 0.12 * abs(v) * w * 2 + curl * 0.9 * u * u * 0.5
            return f.p(x, y, z)
        }
        let green = bathLin(0.40, 0.72, 0.34), orange = bathLin(0.95, 0.52, 0.16), mid = bathLin(0.74, 0.70, 0.22)
        for side in 0..<2 {
            var grid: [[UInt32]] = []
            for i in 0...cu {
                let u = Float(i) / Float(cu)
                let col = u < 0.5 ? simd_mix(green, mid, SIMD3(repeating: u * 2)) : simd_mix(mid, orange, SIMD3(repeating: (u - 0.5) * 2))
                var row: [UInt32] = []
                for j in 0...cv {
                    let v = Float(j) / Float(cv) * 2 - 1
                    let e: Float = 0.01
                    let du = pos(min(u + e, 1), v) - pos(max(u - e, 0), v), dv = pos(u, min(v + 0.05, 1)) - pos(u, max(v - 0.05, -1))
                    var nn = simd_cross(du, dv)
                    nn = simd_length_squared(nn) > 1e-12 ? simd_normalize(nn) : f.n
                    if simd_dot(nn, f.n) < 0 { nn = -nn }
                    let vein = abs(v) < 0.12 ? SIMD3<Float>(0.85, 0.85, 0.85) : SIMD3<Float>(repeating: 1)
                    row.append(soup.vert(pos(u, v), side == 0 ? nn : -nn, col * vein, mat: .matte))
                }
                grid.append(row)
            }
            for i in 0..<cu { for j in 0..<cv { soup.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]) } }
        }
        soup.tube(f.p(-len * 0.5, 0, 0.07), f.p(-len * 0.5 - 0.5, 0, 0.1 + curl * 0.1), r0: 0.05 * f.s, r1: 0.04 * f.s, color: green, mat: .matte, segs: 5)
    }

    private func glitter(_ f: Frame) {
        let cols = [bathLin(1.0, 0.7, 0.9), bathLin(0.6, 0.9, 1.0), bathLin(1.0, 0.9, 0.5)]
        let pts: [(Float, Float, Float)] = [(-0.4, 0.2, 0.7), (0.35, -0.1, 1.2), (0.05, 0.42, 2.0)]
        for (k, pp) in pts.enumerated() {
            let c = cs(pp.2), s = sn(pp.2)
            soup.ellipsoid(f.p(pp.0, pp.1, 0.06), ax: f.a(0.36 * c, 0.36 * s, 0), ay: f.a(-0.18 * s, 0.18 * c, 0), az: f.a(0, 0, 0.05), color: cols[k], mat: .glitter, rings: 2, segs: 4)
        }
    }
    private func cs(_ a: Float) -> Float { cosf(a) }
    private func sn(_ a: Float) -> Float { sinf(a) }

    private func fuzz(_ f: Frame) {
        let cols = [bathLin(1.0, 0.72, 0.84), bathLin(0.84, 0.74, 1.0), bathLin(1.0, 0.86, 0.9)]
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi + 0.3
            let d = SIMD2<Float>(cosf(a), sinf(a))
            soup.ellipsoid(f.p(d.x * 0.35, d.y * 0.35, 0.18 + 0.08 * Float(k % 3)), ax: f.a(d.x * 0.5, d.y * 0.5, 0.12), ay: f.a(-d.y * 0.11, d.x * 0.11, 0), az: f.a(0, 0, 0.11), color: cols[k % 3], mat: .fabric, rings: 3, segs: 5)
        }
        soup.ellipsoid(f.p(0, 0, 0.2), ax: f.a(0.3, 0, 0), ay: f.a(0, 0.3, 0), az: f.a(0, 0, 0.24), color: cols[0], mat: .fabric, rings: 3, segs: 6)
    }

    private func drop(_ f: Frame) {
        // the Jelly Drops currency: a glossy golden-amber jelly teardrop on its base, a white highlight and a faint warm glow
        let amber = bathLin(1.0, 0.70, 0.12)
        let prof: [(r: Float, y: Float)] = [(0, 0), (0.5, 0.04), (0.74, 0.35), (0.66, 0.75), (0.42, 1.15), (0.2, 1.5), (0.06, 1.75), (0, 1.8)].map { (r: $0.0 * f.s, y: $0.1 * f.s) }
        soup.revolve(f.o, up: f.n, side: f.t, profile: prof, color: amber, mat: .jelly, alpha: 0.97, segs: 10)
        soup.revolve(f.o - f.n * 0.1 * f.s, up: f.n, side: f.t, profile: prof.map { (r: $0.r * 1.28, y: $0.y * 1.12) }, color: bathLin(1.0, 0.8, 0.3), mat: .jelly, alpha: 0.22, segs: 10)
        soup.ellipsoid(f.p(-0.28, -0.12, 0.62), ax: f.a(0.16, 0.05, 0), ay: f.a(-0.04, 0.1, 0), az: f.a(0, 0, 0.2), color: SIMD3(1.5, 1.5, 1.4), mat: .glitter, rings: 3, segs: 6)
        soup.ellipsoid(f.p(-0.12, 0.28, 0.92), ax: f.a(0.07, 0, 0), ay: f.a(0, 0.07, 0), az: f.a(0, 0, 0.1), color: SIMD3(1.5, 1.5, 1.4), mat: .glitter, rings: 3, segs: 6)
    }

    // MARK: tools

    private func addTool(_ tool: BathTool, at t: SIMD3<Float>, time: Float) {
        switch tool {
        case .roller:
            // sticky white roll lying along x, pastel frame and handle rising up-right toward the camera
            let roll = bathLin(0.97, 0.97, 0.98), stripe = bathLin(0.86, 0.86, 0.84), pink = BathModels.brass, lav = BathModels.matteBlack
            let r: Float = 0.16, hl: Float = 0.22
            soup.tube(t + SIMD3(-hl, 0, 0), t + SIMD3(hl, 0, 0), r0: r, r1: r, color: roll, mat: .matte, segs: 14)
            for k in 0..<5 { let x = -hl + (Float(k) + 0.5) / 5 * 2 * hl
                soup.tube(t + SIMD3(x - 0.008, 0, 0), t + SIMD3(x + 0.008, 0, 0), r0: r + 0.004, r1: r + 0.004, color: stripe, mat: .matte, segs: 14) }
            soup.tube(t + SIMD3(hl, 0, 0), t + SIMD3(hl + 0.04, 0, 0), r0: r * 0.55, r1: r * 0.55, color: lav, mat: .matte, segs: 12)
            let a = t + SIMD3(hl + 0.04, 0, 0), b = t + SIMD3(hl + 0.04, 0.34, 0.12), h = t + SIMD3(hl + 0.04, 0.5, 0.2)
            soup.tube(a, b, r0: 0.022, r1: 0.022, color: lav, mat: .matte, segs: 8)
            soup.tube(b, h + SIMD3(0, 0.34, 0.2), r0: 0.035, r1: 0.04, color: pink, mat: .metal, segs: 10)
            soup.sphere(h + SIMD3(0, 0.34, 0.2), 0.042, color: pink, mat: .metal, rings: 4, segs: 10)
        case .soap:
            // translucent pastel jelly bar with a tiny bubble riding on it
            let c = bathLin(0.84, 0.83, 0.82)
            let ct = cosf(0.4), st = sinf(0.4)
            soup.ellipsoid(t + SIMD3(0, 0.02, 0.02), ax: SIMD3(0.24 * ct, 0, 0.24 * st), ay: SIMD3(0, 0.12, 0), az: SIMD3(-0.15 * st, 0, 0.15 * ct), color: c, mat: .jelly, alpha: 0.86, rings: 7, segs: 14)
            soup.sphere(t + SIMD3(0.08, 0.17, 0.05), 0.035, color: .zero, mat: .bubble, rings: 4, segs: 8)
            soup.sphere(t + SIMD3(0.14, 0.12, 0.09), 0.02, color: .zero, mat: .bubble, rings: 3, segs: 6)
        case .shine:
            // soft polishing cloth / wax pad: a plump cream pad with a folded edge and a pink fold
            let cl = bathLin(0.96, 0.96, 0.95), fold = bathLin(0.86, 0.86, 0.85)
            soup.ellipsoid(t + SIMD3(0, 0, 0.02), ax: SIMD3(0.27, 0, 0), ay: SIMD3(0, 0.07, 0), az: SIMD3(0, 0, 0.22), color: cl, mat: .fabric, rings: 5, segs: 12)
            soup.ellipsoid(t + SIMD3(0.04, 0.07, 0), ax: SIMD3(0.2, 0, 0), ay: SIMD3(0, 0.05, 0), az: SIMD3(0, 0, 0.15), color: fold, mat: .fabric, rings: 4, segs: 10)
            soup.ellipsoid(t + SIMD3(-0.1, 0.1, 0.05), ax: SIMD3(0.07, 0, 0), ay: SIMD3(0, 0.04, 0), az: SIMD3(0, 0, 0.07), color: cl, mat: .fabric, rings: 3, segs: 6)
        case .none, .rinse: break
        }
    }

    // MARK: floating sparkles

    private func hash1(_ a: Int, _ b: Int) -> Float { BathModels.hash(a &* 7919 &+ 13, b &* 104729 &+ 7) }

    /// Camera-facing four-point stars that pop up just off his skin, drift up and fade (each at its own rate and spot).
    private func addStars(count: Int, time: Float, right: SIMD3<Float>, up: SIMD3<Float>, at: (Int) -> (p: SIMD3<Float>, n: SIMD3<Float>)?) {
        for i in 0..<min(count, 20) {
            let rate = 0.22 + 0.3 * hash1(i, 1)
            let t = time * rate + hash1(i, 2) * 9
            let cycle = Int(floorf(t)), u = t - floorf(t)
            let spot = Int(hash1(i, cycle + 100) * Float(Self.sparkleSpots)) % Self.sparkleSpots
            guard let s = at(spot) else { continue }
            let fade = powf(max(sinf(u * .pi), 0), 1.3)
            if fade < 0.02 { continue }
            let size = (0.13 + 0.13 * hash1(i, cycle + 5)) * (0.55 + 0.45 * fade)
            let c = s.p + s.n * (0.07 + 0.30 * u) + SIMD3<Float>(0, 0.22 * u, 0)
            let rot = hash1(i, cycle + 9) * 0.8
            let r = right * cosf(rot) + up * sinf(rot), v = up * cosf(rot) - right * sinf(rot)
            let col = hash1(i, cycle + 3) < 0.5 ? SIMD3<Float>(1.0, 0.97, 0.85) : SIMD3<Float>(0.85, 0.95, 1.0)
            var ids: [UInt32] = []
            for (x, y) in [(Float(-1), Float(-1)), (1, -1), (1, 1), (-1, 1)] {
                ids.append(soup.vert(c + (r * x + v * y) * size, SIMD3(x, y, 0), col, mat: .star, alpha: fade))
            }
            soup.i.append(contentsOf: [ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]])
        }
    }

    // MARK: spray

    private func addSpray(from s: SIMD3<Float>, time: Float) {
        let target = BathSet.standPoint + SIMD3(0, 0.9, 0)
        for k in 0..<Self.sprayDrops {
            let seed = Float(k) * 0.61803
            let ph = (time * 1.7 + seed).truncatingRemainder(dividingBy: 1)
            let p = ph < 0 ? ph + 1 : ph
            let spread = SIMD3<Float>(sinf(seed * 91.7) * 0.10, 0, cosf(seed * 57.3) * 0.10) * (0.3 + p)
            let base = s + (target - s) * SIMD3<Float>(p, 0.5 * p + 0.5 * p * p, p)
            let pos = base + spread
            let r: Float = 0.022 + 0.01 * Float(k % 3)
            soup.ellipsoid(pos, ax: SIMD3(r, 0, 0), ay: SIMD3(0, r * 2.2, 0), az: SIMD3(0, 0, r), color: bathLin(0.6, 0.85, 1.0), mat: .droplet, rings: 3, segs: 6)
        }
    }
}
