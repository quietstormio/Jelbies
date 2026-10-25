//
//  ParkNature.swift
//  The park's plants and stones, built once into the park's static room mesh (ParkScenery.build): layered, clumpy tree canopies with a curved trunk and
//  roots, rounded shrubs (some flowering), wildflower / meadow patches, grass tufts along the path, rocks and the pond's lily pads. The flower heads
//  are the Garden's (GardenShapes) so the two places share one set of good builders; here they are wild and scattered, not tidy beds. Static only: no
//  per-frame cost, no extra draw calls.
//

import simd
import Foundation

extension ParkScenery {
    typealias S = GardenShapes
    typealias V3 = SIMD3<Float>

    /// The sun side of the park's key light (up, a little right and toward the camera): clump faces turned this way brighten, the rest sink into shade.
    private static let sunDir = simd_normalize(V3(0.45, 0.8, 0.4))

    /// An ellipsoid whose vertex colours are lit by hand: bright toward the sun, deep in the shade underneath.
    static func lit(_ b: RoomMeshBuilder, _ c: V3, rx: Float, ry: Float, rz: Float, color: V3, segments: Int = 10, rings: Int = 5, lift: Float = 1) {
        let first = b.mesh.vertices.count
        blob(b, c, rx: rx, ry: ry, rz: rz, color: color, segments: segments, rings: rings)
        for i in first..<b.mesh.vertices.count {
            let p = V3(b.mesh.vertices[i].pos.x - c.x, b.mesh.vertices[i].pos.y - c.y, b.mesh.vertices[i].pos.z - c.z) / V3(rx, ry, rz)
            let d = simd_dot(simd_normalize(p + V3(0, 0.0001, 0)), sunDir)
            let k = (0.66 + 0.40 * max(-0.4, d)) * lift
            let col = b.mesh.vertices[i].color
            b.mesh.vertices[i].color = SIMD4(col.x * k * (1 + 0.04 * max(0, d)), col.y * k * (1 + 0.10 * max(0, d)), col.z * k * 0.97, col.w)
        }
    }

    // MARK: trees

    /// A tree: a gently curved trunk with root flares, then a canopy of soft clumps in three layers (wide skirt, fuller middle, a rounded crown).
    /// `detail` 1 = the near trees, 0 = the far tree line (fewer, plainer clumps).
    static func tree(_ b: RoomMeshBuilder, x: Float, z: Float, height h: Float, scale s: Float, hue: V3, blossom: V3? = nil, detail: Int = 1, rng r: inout ParkRandom) {
        let bark = V3(0.22, 0.125, 0.07) * (0.85 + 0.3 * r.unit())
        let lean = (r.unit() - 0.5) * 0.9 * s          // the trunk's slight bend, in x
        let bendZ = (r.unit() - 0.5) * 0.3 * s
        let trunkTop = h * 0.60
        // roots: low flattened lobes at the foot
        for k in 0..<(detail > 0 ? 5 : 3) {
            let a = Float(k) / 5 * 2 * .pi + r.unit() * 0.8
            let rr = 0.30 * s
            lit(b, V3(x + cosf(a) * rr, 0.05 * s, z + sinf(a) * rr), rx: 0.22 * s, ry: 0.09 * s, rz: 0.14 * s, color: bark * 0.9, segments: 6, rings: 3, lift: 0.9)
        }
        // trunk: stacked tapering pieces whose centre drifts along an S-curve
        let pieces = detail > 0 ? 6 : 3
        var cxPrev: Float = 0, czPrev: Float = 0
        for k in 0..<pieces {
            let t0 = Float(k) / Float(pieces), t1 = Float(k + 1) / Float(pieces)
            func off(_ t: Float) -> (Float, Float) { (lean * sinf(t * 2.4) * t, bendZ * sinf(t * 3)) }
            let (ox0, oz0) = off(t0), (ox1, oz1) = off(t1)
            func rad(_ t: Float) -> Float { s * (0.30 - 0.12 * t + 0.07 * (1 - t) * (1 - t) * (1 - t)) }
            // each piece is a lathe at its own bottom centre, leaning to the next by shifting its top vertices
            let first = b.mesh.vertices.count
            b.lathe(cx: x + ox0, cz: z + oz0, profile: [PP(r: rad(t0), y: t0 * trunkTop, nr: 1, ny: 0, ao: 0.65 + 0.35 * t0),
                                                         PP(r: rad(t1), y: t1 * trunkTop, nr: 1, ny: 0.05, ao: 0.65 + 0.35 * t1)], segments: detail > 0 ? 9 : 6, color: bark)
            for i in first..<b.mesh.vertices.count {
                let yy = b.mesh.vertices[i].pos.y
                let u = (yy - t0 * trunkTop) / max(trunkTop * (t1 - t0), 0.001)
                b.mesh.vertices[i].pos.x += (ox1 - ox0) * u
                b.mesh.vertices[i].pos.z += (oz1 - oz0) * u
            }
            cxPrev = ox1; czPrev = oz1
        }
        let tx = x + cxPrev, tz = z + czPrev
        // the two forks that carry the canopy
        if detail > 0 {
            for sgn: Float in [-1, 1] {
                lit(b, V3(tx + sgn * 0.3 * s, trunkTop + 0.1 * s, tz), rx: 0.11 * s, ry: 0.42 * s, rz: 0.11 * s, color: bark, segments: 6, rings: 3)
            }
        }
        // canopy
        let cy = trunkTop + h * 0.04
        func shade(_ k: Float) -> V3 { hue * (0.82 + 0.34 * r.unit()) * k }
        // layer 1: the wide skirt (low and dark)
        let n1 = detail > 0 ? 6 : 4
        for k in 0..<n1 {
            let a = Float(k) / Float(n1) * 2 * .pi + r.unit() * 0.5
            let rr = (1.15 + 0.35 * r.unit()) * s
            lit(b, V3(tx + cosf(a) * rr, cy + (0.0 + 0.2 * r.unit()) * s, tz + sinf(a) * rr * 0.9), rx: 0.95 * s, ry: 0.62 * s, rz: 0.85 * s, color: shade(0.9), segments: 9, rings: 4)
        }
        // layer 2: the full middle
        let n2 = detail > 0 ? 5 : 3
        for k in 0..<n2 {
            let a = Float(k) / Float(n2) * 2 * .pi + 0.6 + r.unit() * 0.5
            let rr = (0.7 + 0.3 * r.unit()) * s
            lit(b, V3(tx + cosf(a) * rr, cy + (0.75 + 0.25 * r.unit()) * s, tz + sinf(a) * rr * 0.9), rx: 0.95 * s, ry: 0.70 * s, rz: 0.88 * s, color: shade(1.0), segments: 9, rings: 4)
        }
        // layer 3: the crown, lightest
        lit(b, V3(tx + (r.unit() - 0.5) * 0.3 * s, cy + 1.55 * s, tz), rx: 1.05 * s, ry: 0.78 * s, rz: 0.95 * s, color: shade(1.12), segments: 11, rings: 5)
        if detail > 0 {
            lit(b, V3(tx + 0.55 * s, cy + 1.25 * s, tz + 0.4 * s), rx: 0.6 * s, ry: 0.45 * s, rz: 0.55 * s, color: shade(1.2), segments: 8, rings: 4)
            // a few bright leaf puffs on the sunny, camera side
            for _ in 0..<4 {
                let a = (r.unit() - 0.2) * 1.8, e = 0.5 + r.unit() * 0.9
                let p = V3(tx + sinf(a) * 1.5 * s, cy + (0.5 + e) * s, tz + cosf(a) * 1.3 * s)
                lit(b, p, rx: 0.36 * s, ry: 0.27 * s, rz: 0.32 * s, color: shade(1.28), segments: 7, rings: 3)
            }
            if let bl = blossom {
                for _ in 0..<10 {
                    let a = r.unit() * 6.28, e = r.unit() * 0.9
                    let p = V3(tx + cosf(a) * 1.5 * s * cosf(e), cy + (0.5 + 1.3 * sinf(e)) * s, tz + sinf(a) * 1.4 * s * cosf(e) + 0.2 * s)
                    S.ball(b, p, 0.1 * s, bl * (0.9 + 0.2 * r.unit()), segments: 5, rings: 3)
                }
            }
        }
    }

    // MARK: bushes

    /// A rounded shrub: five or six overlapping lobes, lit from the sun side; `bloom` studs it with flowers.
    static func shrub(_ b: RoomMeshBuilder, x: Float, z: Float, scale s: Float, hue: V3, bloom: V3? = nil, rng r: inout ParkRandom) {
        let lobes: [(V3, V3)] = [(V3(0, 0.40, 0), V3(0.95, 0.62, 0.85)), (V3(-0.62, 0.30, 0.1), V3(0.65, 0.46, 0.6)), (V3(0.62, 0.32, 0.12), V3(0.7, 0.5, 0.6)),
                                 (V3(0.12, 0.30, 0.45), V3(0.7, 0.42, 0.5)), (V3(-0.15, 0.78, -0.05), V3(0.6, 0.4, 0.55)), (V3(0.3, 0.6, 0.15), V3(0.5, 0.36, 0.45))]
        for (k, l) in lobes.enumerated() {
            lit(b, V3(x + l.0.x * s, l.0.y * s, z + l.0.z * s), rx: l.1.x * s, ry: l.1.y * s, rz: l.1.z * s,
                color: hue * (0.85 + 0.3 * r.unit()) * (1 + 0.07 * Float(k)), segments: 9, rings: 4)
        }
        guard let bloom else { return }
        for _ in 0..<(8 + Int(r.next() % 6)) {
            let a = (r.unit() - 0.15) * 3.0 - 0.2, e = 0.1 + r.unit() * 0.9
            let p = V3(x + cosf(a) * 0.9 * s * cosf(e), 0.42 * s + sinf(e) * 0.6 * s, z + sinf(a) * 0.8 * s * cosf(e) + 0.1 * s)
            S.ball(b, p, 0.06 * s, bloom * (0.88 + 0.24 * r.unit()), segments: 5, rings: 3)
        }
    }

    // MARK: meadow

    static let wildColours: [V3] = [S.srgb(0.97, 0.45, 0.35), S.srgb(0.99, 0.84, 0.30), S.srgb(0.99, 0.97, 0.92), S.srgb(0.72, 0.56, 0.92), S.srgb(0.98, 0.64, 0.78), S.srgb(0.55, 0.72, 0.98)]

    /// A wild patch of flowers (mixed kinds and heights, uneven edge) around (x, z), with tufts of grass between.
    static func meadow(_ b: RoomMeshBuilder, x: Float, z: Float, radius R: Float, count: Int, rng r: inout ParkRandom) {
        let mix = [wildColours[Int(r.next() % 6)], wildColours[Int(r.next() % 6)], wildColours[Int(r.next() % 6)]]
        for _ in 0..<count {
            let a = r.unit() * 6.283, d = R * sqrtf(r.unit())
            let fx = x + cosf(a) * d * 1.2, fz = z + sinf(a) * d * 0.8
            let col = r.unit() < 0.7 ? mix[Int(r.next() % 3)] : wildColours[Int(r.next() % 6)]
            let h = 0.14 + 0.22 * r.unit()
            let kind: S.Bloom = [.daisy, .daisy, .poppy, .tulip, .lavender][Int(r.next() % 5)]
            S.flower(b, kind, x: fx, z: fz, h: h, color: col, scale: 1.2 + 0.5 * r.unit(), rng: &r)
        }
        for _ in 0..<(count / 2) {
            let a = r.unit() * 6.283, d = R * 1.1 * sqrtf(r.unit())
            tuft(b, x: x + cosf(a) * d * 1.2, z: z + sinf(a) * d * 0.8, scale: 0.8 + 0.5 * r.unit(), rng: &r)
        }
    }

    /// A little fan of grass blades.
    static func tuft(_ b: RoomMeshBuilder, x: Float, z: Float, scale s: Float, rng r: inout ParkRandom) {
        let n = 4 + Int(r.next() % 3)
        for k in 0..<n {
            b.leaf(base: V3(x, 0.01, z), azimuth: Float(k) / Float(n) * 6.283 + r.unit(), length: (0.22 + 0.16 * r.unit()) * s, width: 0.05 * s,
                   lean: 0.35 + 0.5 * r.unit(), colorBase: V3(0.06, 0.18, 0.04), colorTip: V3(0.17, 0.42, 0.10) * (0.9 + 0.3 * r.unit()))
        }
    }

    /// A rock: a squat lumpy mound of two or three overlapping stones, with a pebble or two.
    static func rock(_ b: RoomMeshBuilder, x: Float, z: Float, scale s: Float, rng r: inout ParkRandom) {
        let g = 0.9 + 0.25 * r.unit()
        let base = V3(0.34, 0.33, 0.31) * g
        lit(b, V3(x, 0.14 * s, z), rx: 0.42 * s, ry: 0.22 * s, rz: 0.34 * s, color: base, segments: 8, rings: 4, lift: 1.1)
        lit(b, V3(x + 0.28 * s, 0.10 * s, z + 0.12 * s), rx: 0.26 * s, ry: 0.16 * s, rz: 0.22 * s, color: base * 1.08, segments: 7, rings: 3, lift: 1.1)
        lit(b, V3(x - 0.2 * s, 0.09 * s, z - 0.2 * s), rx: 0.2 * s, ry: 0.13 * s, rz: 0.17 * s, color: base * 0.94, segments: 7, rings: 3, lift: 1.1)
        lit(b, V3(x + 0.1 * s, 0.025, z + 0.5 * s), rx: 0.08 * s, ry: 0.045 * s, rz: 0.07 * s, color: base * 1.05, segments: 6, rings: 3)
        tuft(b, x: x - 0.4 * s, z: z + 0.2 * s, scale: 0.8, rng: &r)
    }

    /// Lily pads (notched discs) with a couple of blossoms, floating on the pond.
    static func lilyPads(_ b: RoomMeshBuilder, centre c: SIMD2<Float>, rng r: inout ParkRandom) {
        let spots: [(Float, Float, Float)] = [(-0.45, 0.35, 0.24), (0.2, -0.5, 0.2), (-0.15, -0.1, 0.17), (0.55, 0.3, 0.19), (-0.7, -0.25, 0.14), (0.0, 0.62, 0.15)]
        for (k, p) in spots.enumerated() {
            let col = V3(0.09, 0.30, 0.07) * (0.9 + 0.35 * r.unit())
            let px = c.x + p.0, pz = c.y + p.1
            // a disc with a wedge missing: a fan of triangles
            let hub = b.vertex(V3(px, 0.045, pz), V3(0, 1, 0), color: col * 1.1)
            let notch = r.unit() * 6.283
            var ring: [UInt32] = []
            let n = 14
            for j in 0...n {
                let a = notch + 0.35 + Float(j) / Float(n) * (6.283 - 0.7)
                ring.append(b.vertex(V3(px + cosf(a) * p.2, 0.04, pz + sinf(a) * p.2), V3(0, 1, 0), color: col))
            }
            for j in 0..<n { b.triangle(hub, ring[j + 1], ring[j]) }
            if k == 0 || k == 3 {
                let f = V3(px + 0.03, 0.07, pz - 0.02)
                S.fan(b, f, n: 7, r0: 0.0, r1: 0.1, width: 0.032, color: S.srgb(0.99, 0.86, 0.92), tip: S.srgb(0.97, 0.56, 0.72), phase: r.unit() * 6)
                S.face(b, f + S.headN * 0.01, radius: 0.025, color: S.srgb(0.98, 0.84, 0.30))
            }
        }
    }
}
