//
//  GardenPlants.swift
//  What changes in the Garden: the plants of the four plots in their three mesh stages (sprout, bud, bloom / ripe fruit; rebuilt only when a plot's stage or
//  wetness changes, then drawn in the room's cached pass) and the live things (butterflies and bees by day, fireflies by night, the watering can's pour, the
//  sparkle over a ripe plot), a few hundred vertices rebuilt every frame while the Garden is the home (`MelonRenderer.setGardenLive`).
//

import simd
import Foundation

enum GardenPlants {
    typealias S = GardenShapes
    typealias V3 = SIMD3<Float>
    private static func c(_ r: Float, _ g: Float, _ b: Float) -> V3 { S.srgb(r, g, b) }

    private static let stems: [(Float, Float)] = [(-0.14, 0.05), (0.13, 0.08), (0.0, -0.11)]

    // MARK: the plots

    static func build(_ g: GardenBook, now: Double) -> RoomMesh {
        let b = RoomMeshBuilder()
        b.material = .plain
        var r = ParkRandom(0x51A7)
        for i in 0..<GardenTuning.plotCount {
            let p = GardenLayout.plotCentre(i)
            if g.isWet(i, now: now) {
                S.blob(b, V3(p.x, GardenLayout.soilY - 0.03, p.z), rx: 0.405, ry: 0.073, rz: 0.405, color: c(0.24, 0.16, 0.12), segments: 12, rings: 4)
            }
            let stage = g.stage(i)
            guard let kind = g.plots[i].plant, stage > 0 else { sign(b, p, i); continue }
            switch stage {
            case 1: sprout(b, p, kind, &r)
            case 2: bud(b, p, kind, &r)
            default: ripe(b, p, kind, &r)
            }
        }
        return b.mesh
    }

    /// The empty plot's seed-packet stake.
    private static func sign(_ b: RoomMeshBuilder, _ p: V3, _ i: Int) {
        let tags: [V3] = [c(0.99, 0.86, 0.52), c(0.98, 0.72, 0.78), c(0.72, 0.86, 0.98), c(0.80, 0.92, 0.70)]
        S.box(b, V3(p.x + 0.26, 0.42, p.z + 0.3), V3(0.012, 0.12, 0.012), r: 0.005, color: GardenScenery.wood)
        S.box(b, V3(p.x + 0.26, 0.58, p.z + 0.31), V3(0.08, 0.06, 0.01), r: 0.008, color: tags[i % tags.count])
        S.ball(b, V3(p.x + 0.26, 0.585, p.z + 0.325), 0.022, GardenScenery.leafDeep, segments: 5, rings: 3)
    }

    private static func sprout(_ b: RoomMeshBuilder, _ p: V3, _ kind: GardenPlant, _ r: inout ParkRandom) {
        for (k, o) in stems.enumerated() {
            let x = p.x + o.0, z = p.z + o.1
            S.stem(b, x: x, z: z, y0: p.y - 0.02, y1: p.y + 0.07, r: 0.01, color: S.stemC, segments: 4)
            for j in 0..<2 {
                b.leaf(base: V3(x, p.y + 0.06, z), azimuth: Float(j) * 3.14 + Float(k) * 1.1, length: 0.13, width: 0.07, lean: 1.0,
                       colorBase: S.leafA, colorTip: S.leafB)
            }
        }
    }

    private static func bud(_ b: RoomMeshBuilder, _ p: V3, _ kind: GardenPlant, _ r: inout ParkRandom) {
        let green = c(0.55, 0.78, 0.40), pale = c(0.80, 0.90, 0.70)
        switch kind {
        case .daisy, .tulip:
            for (k, o) in stems.enumerated() {
                let x = p.x + o.0, z = p.z + o.1, top = p.y + 0.26 + 0.05 * Float(k % 2)
                S.stem(b, x: x, z: z, y0: p.y - 0.02, y1: top, r: 0.012, color: S.stemC, segments: 4)
                b.leaf(base: V3(x, p.y + 0.02, z), azimuth: Float(k) * 2.1, length: 0.24, width: 0.07, lean: 0.9, colorBase: S.leafA, colorTip: S.leafB)
                b.leaf(base: V3(x, p.y + 0.05, z), azimuth: Float(k) * 2.1 + 3.2, length: 0.2, width: 0.06, lean: 0.9, colorBase: S.leafA, colorTip: S.leafB)
                S.blob(b, V3(x, top + 0.03, z), rx: 0.03, ry: 0.045, rz: 0.03, color: kind == .daisy ? pale : green, segments: 6, rings: 3)
            }
        case .rose:
            S.blob(b, V3(p.x, p.y + 0.15, p.z), rx: 0.26, ry: 0.17, rz: 0.24, color: GardenScenery.leafDeep, segments: 9, rings: 4)
            for (k, o) in stems.enumerated() { S.ball(b, V3(p.x + o.0 * 1.4, p.y + 0.34, p.z + o.1), 0.035, k == 1 ? c(0.96, 0.60, 0.68) : green, segments: 6, rings: 3) }
        case .strawberry:
            for k in 0..<5 {
                b.leaf(base: V3(p.x, p.y, p.z), azimuth: Float(k) * 1.26, length: 0.3, width: 0.16, lean: 1.0, colorBase: S.leafA, colorTip: S.leafB)
            }
            for (_, o) in stems.enumerated() { S.ball(b, V3(p.x + o.0 * 1.5, p.y + 0.09, p.z + o.1 * 1.5), 0.03, pale, segments: 6, rings: 3) }
        case .blueberry:
            S.blob(b, V3(p.x, p.y + 0.24, p.z), rx: 0.26, ry: 0.22, rz: 0.24, color: GardenScenery.leafDeep, segments: 9, rings: 4)
            for k in 0..<5 {
                let a = Float(k) * 1.3
                S.ball(b, V3(p.x + cosf(a) * 0.2, p.y + 0.28 + 0.05 * Float(k % 2), p.z + sinf(a) * 0.2 + 0.05), 0.028, green, segments: 6, rings: 3)
            }
        }
    }

    private static func ripe(_ b: RoomMeshBuilder, _ p: V3, _ kind: GardenPlant, _ r: inout ParkRandom) {
        switch kind {
        case .daisy:
            for (k, o) in stems.enumerated() {
                let h = 0.42 + 0.08 * Float(k)
                leavesAt(b, p, o, h, k)
                S.flower(b, .daisy, x: p.x + o.0, z: p.z + o.1, y0: p.y - 0.02, h: h, color: GardenScenery.daisyColours[k % 3], scale: 1.45, rng: &r)
            }
        case .tulip:
            let cols = [c(0.92, 0.30, 0.34), c(0.98, 0.82, 0.28), c(0.97, 0.58, 0.72)]
            for (k, o) in stems.enumerated() {
                let h = 0.40 + 0.07 * Float(k)
                S.flower(b, .tulip, x: p.x + o.0, z: p.z + o.1, y0: p.y - 0.02, h: h, color: cols[k], scale: 1.4, rng: &r)
            }
        case .rose:
            S.blob(b, V3(p.x, p.y + 0.17, p.z), rx: 0.3, ry: 0.2, rz: 0.27, color: GardenScenery.leafDeep, segments: 9, rings: 4)
            let cols = [c(0.96, 0.50, 0.62), c(0.98, 0.68, 0.74), c(0.90, 0.36, 0.50), c(0.99, 0.90, 0.88), c(0.96, 0.50, 0.62)]
            let spots: [V3] = [V3(-0.14, 0.40, 0.06), V3(0.15, 0.44, 0.08), V3(0.0, 0.50, -0.06), V3(-0.06, 0.34, 0.16), V3(0.1, 0.33, -0.1)]
            for (k, o) in spots.enumerated() {
                S.ball(b, V3(p.x + o.x, p.y + o.y, p.z + o.z), 0.065, cols[k], segments: 7, rings: 4)
                S.ball(b, V3(p.x + o.x, p.y + o.y + 0.04, p.z + o.z + 0.02), 0.04, cols[k] * 1.15, segments: 6, rings: 3)
            }
        case .strawberry:
            for k in 0..<6 {
                b.leaf(base: V3(p.x, p.y, p.z), azimuth: Float(k) * 1.05, length: 0.34, width: 0.18, lean: 1.0, colorBase: S.leafA, colorTip: S.leafB)
            }
            let red = c(0.92, 0.22, 0.28)
            let spots: [V3] = [V3(-0.2, 0.10, 0.14), V3(0.18, 0.12, 0.12), V3(0.0, 0.14, 0.22), V3(-0.1, 0.11, -0.12), V3(0.2, 0.10, -0.06)]
            for o in spots {
                let q = V3(p.x + o.x, p.y + o.y, p.z + o.z)
                S.blob(b, q, rx: 0.052, ry: 0.062, rz: 0.052, color: red, segments: 8, rings: 4)
                S.blob(b, q + V3(0, 0.058, 0), rx: 0.036, ry: 0.012, rz: 0.036, color: S.leafB, segments: 6, rings: 2)
                for j in 0..<4 { let a = Float(j) * 1.6; S.ball(b, q + V3(cosf(a) * 0.04, 0.0 + 0.012 * Float(j % 2), sinf(a) * 0.04), 0.008, c(0.99, 0.90, 0.50), segments: 4, rings: 2) }
            }
        case .blueberry:
            S.blob(b, V3(p.x, p.y + 0.27, p.z), rx: 0.3, ry: 0.25, rz: 0.27, color: GardenScenery.leafDeep, segments: 9, rings: 4)
            let blue = c(0.38, 0.46, 0.82)
            for k in 0..<10 {
                let a = Float(k) * 0.97, e = 0.2 + 0.14 * Float(k % 3)
                S.ball(b, V3(p.x + cosf(a) * 0.27 * cosf(e), p.y + 0.27 + sinf(e) * 0.27, p.z + sinf(a) * 0.25 * cosf(e) + 0.06), 0.04, blue * (0.9 + 0.16 * Float(k % 2)), segments: 7, rings: 4)
            }
        }
    }

    private static func leavesAt(_ b: RoomMeshBuilder, _ p: V3, _ o: (Float, Float), _ h: Float, _ k: Int) {
        b.leaf(base: V3(p.x + o.0, p.y, p.z + o.1), azimuth: Float(k) * 2.1, length: h * 0.6, width: 0.07, lean: 0.9, colorBase: S.leafA, colorTip: S.leafB)
    }
}

// MARK: - live things

enum GardenLive {
    typealias S = GardenShapes
    typealias V3 = SIMD3<Float>
    private static func c(_ r: Float, _ g: Float, _ b: Float) -> V3 { S.srgb(r, g, b) }

    static let butterflyCount = 3
    private static let flutter: [V3] = [c(1.0, 0.62, 0.24), c(0.62, 0.80, 1.0), c(1.0, 0.72, 0.88)]

    /// Where butterfly `i` is at time `t` (they drift over the lawn and beds, never behind the fence).
    static func butterfly(_ i: Int, t: Float) -> V3 {
        let homes: [SIMD2<Float>] = [SIMD2(-2.7, -0.6), SIMD2(2.3, 1.0), SIMD2(0.2, 2.4)]
        let h = homes[i % homes.count], f = Float(i) * 2.1
        return V3(h.x + 1.6 * sinf(0.31 * t + f) + 0.35 * sinf(0.93 * t + f), 0.8 + 0.28 * sinf(1.3 * t + f) + 0.12 * Float(i % 2),
                  h.y + 1.1 * sinf(0.23 * t + 2 * f) + 0.25 * sinf(0.77 * t))
    }
    private static func bee(_ i: Int, t: Float) -> V3 {
        let homes: [V3] = [V3(-1.0, 1.0, -3.2), V3(-4.3, 0.7, 1.6)]
        let h = homes[i % homes.count], f = Float(i) * 1.7
        return h + V3(0.7 * sinf(2.3 * t + f) + 0.2 * sinf(7 * t), 0.15 * sinf(3.1 * t + f) + 0.04 * sinf(30 * t), 0.5 * cosf(1.9 * t + f))
    }

    /// `t` seconds, `night` 0 (day) ... 1 (night), `ripe` = plots with a ripe plant, `can` = the watering can's plot and age.
    static func build(t: Float, night: Float, ripe: [Int], can: (plot: Int, t: Float)?) -> RoomMesh {
        let b = RoomMeshBuilder()
        b.material = .plain
        let day = max(0, 1 - night * 1.6)
        if day > 0.15 {
            for i in 0..<butterflyCount { wingedThing(b, butterfly(i, t: t), butterfly(i, t: t + 0.06), t: t, i: i, size: 0.13, colour: flutter[i % flutter.count], flapRate: 13) }
            for i in 0..<2 {
                let p = bee(i, t: t)
                S.blob(b, p, rx: 0.035, ry: 0.03, rz: 0.045, color: c(0.99, 0.82, 0.20), segments: 6, rings: 3)
                S.blob(b, p + V3(0, 0, 0.032), rx: 0.03, ry: 0.025, rz: 0.018, color: c(0.25, 0.20, 0.18), segments: 5, rings: 3)
                wingedThing(b, p + V3(0, 0.03, 0), p + V3(0, 0.03, 0.05), t: t, i: i + 5, size: 0.05, colour: c(0.95, 0.97, 1.0), flapRate: 45)
            }
        }
        if night > 0.3 {
            for k in 0..<12 {
                let f = Float(k)
                let p = V3(-3.6 + 7.2 * fractf(f * 0.3819) + 0.45 * sinf(0.5 * t + f), 0.35 + 0.8 * fractf(f * 0.6180) + 0.15 * sinf(0.9 * t + f * 2), -3.4 + 5.6 * fractf(f * 0.7071) + 0.4 * cosf(0.4 * t + f))
                let pulse = max(0, sinf(1.6 * t + f * 1.9))
                if pulse < 0.15 { continue }
                S.ball(b, p, 0.026 * (0.5 + pulse) * night, c(0.86, 1.0, 0.42), segments: 5, rings: 3, ao: 2.2)
            }
        }
        for i in ripe {
            let p = GardenLayout.plotCentre(i)
            let c0 = V3(p.x + 0.0, 0.92 + 0.05 * sinf(2.4 * t + Float(i)), p.z + 0.1)
            S.fan(b, c0, n: 4, r0: 0.0, r1: 0.1, width: 0.03, color: c(1.0, 0.96, 0.62), tip: c(1.0, 0.88, 0.3), phase: t * 0.8, ao: 1.7)
            S.fan(b, c0, n: 4, r0: 0.0, r1: 0.06, width: 0.02, color: c(1.0, 1.0, 0.9), tip: c(1.0, 0.95, 0.6), phase: t * 0.8 + 0.785, ao: 1.7)
        }
        if let can { wateringCan(b, can.plot, t: can.t) }
        return b.mesh
    }

    private static func fractf(_ x: Float) -> Float { x - floorf(x) }

    /// Two flapping wings (quads hinged at the body) facing along the velocity.
    private static func wingedThing(_ b: RoomMeshBuilder, _ p: V3, _ next: V3, t: Float, i: Int, size: Float, colour: V3, flapRate: Float) {
        var f = next - p; f.y = 0
        f = simd_length(f) > 1e-5 ? simd_normalize(f) : V3(0, 0, 1)
        let side = V3(f.z, 0, -f.x)
        let flap = 0.15 + 0.95 * abs(sinf(flapRate * t + Float(i) * 1.3))
        let edge = colour * 0.78
        for s: Float in [-1, 1] {
            let out = side * (s * cosf(flap)) + V3(0, sinf(flap), 0)
            let a = p + f * size * 0.35, bk = p - f * size * 0.35
            let tipF = a + out * size, tipB = bk + out * size * 0.8 - f * size * 0.15
            let n = simd_normalize(simd_cross(tipF - a, bk - a))
            for sign: Float in [1, -1] {
                let nn = n * sign
                let i0 = b.vertex(a, nn, color: colour), i1 = b.vertex(bk, nn, color: colour), i2 = b.vertex(tipB, nn, color: edge), i3 = b.vertex(tipF, nn, color: edge)
                b.quad(i0, i1, i2, i3)
            }
        }
        S.blob(b, p, rx: size * 0.08, ry: size * 0.08, rz: size * 0.4, color: c(0.25, 0.2, 0.2), segments: 5, rings: 3)
    }

    private static func wateringCan(_ b: RoomMeshBuilder, _ plot: Int, t: Float) {
        let p = GardenLayout.plotCentre(plot)
        let fade = min(1, t / 0.25) * min(1, max(0, (2.2 - t) / 0.3))
        guard fade > 0.02 else { return }
        let bob = 0.02 * sinf(t * 5)
        let cc = V3(p.x + 0.52, 0.86 + bob, p.z + 0.18)
        let body = c(0.58, 0.82, 0.80)
        S.cylinder(b, x: cc.x, z: cc.z, r: 0.12 * fade, y0: cc.y - 0.1 * fade, y1: cc.y + 0.1 * fade, color: body, segments: 12)
        S.cylinder(b, x: cc.x, z: cc.z, r: 0.125 * fade, y0: cc.y + 0.09 * fade, y1: cc.y + 0.105 * fade, color: body * 1.15, segments: 12)
        let tip = V3(p.x + 0.12, 0.66 + bob, p.z + 0.1)
        let from = V3(cc.x - 0.1, cc.y + 0.02, cc.z)
        for k in 0..<5 {
            let u = Float(k) / 4
            S.ball(b, simd_mix(from, tip, SIMD3(repeating: u)), (0.034 - 0.014 * u) * fade, body * 0.95, segments: 6, rings: 3)
        }
        let water = c(0.52, 0.78, 1.0)
        let fall = tip.y - (GardenLayout.soilY + 0.05)
        for j in 0..<8 {
            let ph = fractf(t * 2.3 + Float(j) / 8)
            S.ball(b, V3(tip.x - 0.025 * ph + 0.012 * sinf(Float(j) * 3), tip.y - ph * fall, tip.z + 0.012 * cosf(Float(j) * 2)), 0.018 * fade, water, segments: 5, rings: 3)
        }
    }
}
