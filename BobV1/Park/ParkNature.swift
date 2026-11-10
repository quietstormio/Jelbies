//
//  ParkNature.swift
//  The park's plants, built once into the park's static room mesh (ParkScenery.build) in the living room's calm style: clumped leafy tree canopies (see ParkFoliage.swift:
//  trunks, branches, conifers, flowering bushes, grass-and-flower patches) and the pond's lily pads.
//  Static only: no per-frame cost, no extra draw calls.
//

import simd
import Foundation

extension ParkScenery {
    typealias S = ParkShapes
    typealias V3 = SIMD3<Float>

    /// The sun side of the park's key light (up, a little right and toward the camera): clump faces turned this way brighten, the rest sink into shade.
    static let sunDir = simd_normalize(V3(0.45, 0.8, 0.4))

    /// An ellipsoid whose vertex colours are lit by hand: bright toward the sun, deep in the shade underneath.
    static func lit(_ b: RoomMeshBuilder, _ c: V3, rx: Float, ry: Float, rz: Float, color: V3, segments: Int = 10, rings: Int = 5, lift: Float = 1, soft: Float = 1) {
        let first = b.mesh.vertices.count
        blob(b, c, rx: rx, ry: ry, rz: rz, color: color, segments: segments, rings: rings)
        for i in first..<b.mesh.vertices.count {
            let p = V3(b.mesh.vertices[i].pos.x - c.x, b.mesh.vertices[i].pos.y - c.y, b.mesh.vertices[i].pos.z - c.z) / V3(rx, ry, rz)
            let d = simd_dot(simd_normalize(p + V3(0, 0.0001, 0)), sunDir)
            let k = (1 - (1 - 0.66) * soft + (0.40 * soft) * max(-0.4, d) * (soft < 1 ? 0.8 : 1)) * lift
            let col = b.mesh.vertices[i].color
            b.mesh.vertices[i].color = SIMD4(col.x * k * (1 + 0.04 * max(0, d)), col.y * k * (1 + 0.10 * max(0, d)), col.z * k * 0.97, col.w)
        }
    }

    /// Lily pads (notched discs) with a couple of blossoms, floating on the pond.
    static func lilyPads(_ b: RoomMeshBuilder, centre c: SIMD2<Float>, rng r: inout ParkRandom) {
        let spots: [(Float, Float, Float)] = [(-0.45, 0.35, 0.27), (0.3, -0.45, 0.23), (0.45, 0.35, 0.22), (-0.2, -0.2, 0.18)]
        for (k, p) in spots.enumerated() {
            let col = S.srgb(0.15, 0.36, 0.17) * (0.95 + 0.1 * r.unit())
            let px = c.x + p.0, pz = c.y + p.1
            // a disc with a wedge missing: a fan of triangles
            let hub = b.vertex(V3(px, 0.045, pz), V3(0, 1, 0), color: col * 1.1)
            let notch = r.unit() * 6.283
            var ring: [UInt32] = []
            let n = 20
            for j in 0...n {
                let a = notch + 0.35 + Float(j) / Float(n) * (6.283 - 0.7)
                ring.append(b.vertex(V3(px + cosf(a) * p.2, 0.04, pz + sinf(a) * p.2), V3(0, 1, 0), color: col))
            }
            for j in 0..<n { b.triangle(hub, ring[j + 1], ring[j]) }
            if k == 0 || k == 2 {
                let f = V3(px + 0.03, 0.07, pz - 0.02)
                S.ball(b, f + V3(0, 0.03, 0), 0.075, S.srgb(0.97, 0.97, 0.93), segments: 10, rings: 5)
            }
        }
    }

    // MARK: 2026-11-09 natural look

    /// A tree or bush that throws a soft shadow pool on the lawn: ground position, rough canopy radius, height.
    struct ParkShadow { var x: Float, z: Float, r: Float, h: Float }

    /// Smooth value noise in 0...1 (deterministic).
    static func vnoise(_ x: Float, _ z: Float, _ seed: Float = 0) -> Float {
        func h(_ i: Int, _ j: Int) -> Float {
            var n = UInt32(truncatingIfNeeded: i &* 374761393 &+ j &* 668265263 &+ Int(seed * 977))
            n = (n ^ (n >> 13)) &* 1274126177
            return Float((n ^ (n >> 16)) & 0xFFFF) / 65535
        }
        let xi = Int(floorf(x)), zi = Int(floorf(z))
        var fx = x - floorf(x), fz = z - floorf(z)
        fx = fx * fx * (3 - 2 * fx); fz = fz * fz * (3 - 2 * fz)
        let a = h(xi, zi), b = h(xi + 1, zi), c = h(xi, zi + 1), d = h(xi + 1, zi + 1)
        return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fz
    }
    static func sstep(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
    static func pathX(_ z: Float) -> Float { 0.7 * sinf(z * 0.34) }

    /// The lawn's colour at (x, z): real grass with broad soft mowing bands, sunlit yellower patches, cool shadow pools under trees and shrubs (thrown away from the sun) and
    /// worn earth where the path meets the grass and at the slide's landing.
    static func lawnColor(_ x: Float, _ z: Float, shadows: [ParkShadow]) -> V3 {
        var c = S.srgb(0.29, 0.51, 0.21)
        let band = 0.5 + 0.5 * sinf(z * 0.95 + 1.6 * vnoise(x * 0.12, z * 0.2, 1) + x * 0.06)
        c *= 1 + 0.12 * (2 * band - 1)
        c *= 1 + 0.09 * (2 * vnoise(x * 0.3, z * 0.3, 7) - 1)
        c = simd_mix(c, S.srgb(0.43, 0.59, 0.21), V3(repeating: 0.55 * sstep(0.55, 0.85, vnoise(x * 0.16, z * 0.16, 3))))
        c = simd_mix(c, S.srgb(0.23, 0.46, 0.22), V3(repeating: 0.25 * sstep(0.55, 0.9, vnoise(x * 0.22, z * 0.22, 11))))
        let off = -SIMD2<Float>(sunDir.x, sunDir.z) / sunDir.y
        for sh in shadows {
            let cx = sh.x + off.x * sh.h * 0.35, cz = sh.z + off.y * sh.h * 0.35
            let d = hypotf(x - cx, (z - cz) * 1.15) / (sh.r * 0.95)
            let a = 1 - sstep(0.25, 1.0, d)
            c = simd_mix(c, c * V3(0.55, 0.70, 0.82), V3(repeating: 0.9 * a))
        }
        if z < 13.5, z > -3.9 {
            let dx = fabsf(x - pathX(z)) - 0.62
            let a = (1 - sstep(0.0, 0.22, dx)) * (0.25 + 0.5 * vnoise(x * 0.9, z * 0.9, 5))
            c = simd_mix(c, S.srgb(0.47, 0.38, 0.25), V3(repeating: min(0.6, a)))
        }
        let ld = hypotf((x - 2.9) / 0.95, (z - 3.2) / 0.7)
        c = simd_mix(c, S.srgb(0.47, 0.38, 0.25), V3(repeating: 0.6 * (1 - sstep(0.35, 1.0, ld)) * (0.6 + 0.4 * vnoise(x * 2, z * 2, 9))))
        return c
    }

    /// One tessellated lawn quad grid: ~0.4 m cells over the visible area, coarse beyond.
    static func lawn(_ b: RoomMeshBuilder, shadows: [ParkShadow]) {
        func axis(_ pre: [Float], _ lo: Float, _ hi: Float, _ step: Float, _ post: [Float]) -> [Float] {
            var out = pre; var v = lo
            while v < hi - 0.001 { out.append(v); v += step }
            out.append(hi); return out + post
        }
        let xs = axis([-70, -40, -24, -14, -10.5], -9.0, 9.0, 0.4, [10.5, 14, 24, 40, 70])
        let zs = axis([-9.5], -9.0, 8.4, 0.4, [12, 20, 45])
        var ids: [[UInt32]] = []
        for z in zs {
            ids.append(xs.map { x in b.vertex(V3(x, 0, z), V3(0, 1, 0), color: lawnColor(x, z, shadows: shadows)) })
        }
        for j in 0..<(zs.count - 1) { for i in 0..<(xs.count - 1) {
            // (the far row of cells runs from the back edge toward the camera, +z)
            b.quad(ids[j][i], ids[j + 1][i], ids[j + 1][i + 1], ids[j][i + 1])
        } }
    }

    /// The gravel path (exact centreline x = 0.7 sin(0.34 z), half-width 0.62, z 13 ... -3.7): speckled compacted sand with a narrow stone edging.
    static func gravelPath(_ b: RoomMeshBuilder, rng r: inout ParkRandom) {
        let w: Float = 0.62, e: Float = 0.09
        let us: [Float] = [-w + e, -0.3, 0, 0.3, w - e]
        func gravel(_ x: Float, _ z: Float) -> V3 {
            let sp = 1 + 0.10 * (vnoise(x * 6, z * 6, 2) - 0.5) * 2 + 0.06 * (vnoise(x * 1.5, z * 1.5, 4) - 0.5) * 2
            return S.srgb(0.72, 0.62, 0.46) * sp
        }
        var z: Float = 13
        var row = 0
        while z > -3.7 {
            let z2 = max(-3.7, z - 0.3)
            func vtx(_ zz: Float) -> [UInt32] { us.map { u in b.vertex(V3(pathX(zz) + u, 0.012, zz), V3(0, 1, 0), color: gravel(pathX(zz) + u, zz)) } }
            let a = vtx(z), c = vtx(z2)
            for i in 0..<(us.count - 1) { b.quad(a[i], c[i], c[i + 1], a[i + 1]) }
            // edging: alternating stone / timber blocks
            for sd: Float in [-1, 1] {
                let k = 0.82 + 0.28 * Float((row * 7 + (sd > 0 ? 3 : 0)) % 5) / 4
                let col = S.srgb(0.48, 0.43, 0.37) * k
                let ix = sd < 0 ? -w : w - e, ox = sd < 0 ? -w + e : w
                b.flatQuad(V3(pathX(z) + ix, 0.016, z), V3(pathX(z) + ox, 0.016, z), V3(pathX(z2) + ox, 0.016, z2), V3(pathX(z2) + ix, 0.016, z2), normal: V3(0, 1, 0), colors: [col, col, col, col])
            }
            z = z2; row += 1
        }
    }

    /// The pond: dark mud ring, irregular grey-brown rim stones, deep teal water lightening toward a sky-reflecting centre, reeds with cattails at the back, lily pads.
    static func pond(_ b: RoomMeshBuilder, rng r: inout ParkRandom) {
        let c = pondCentre
        disc(b, cx: c.x, cz: c.y, radius: 1.55, y: 0.008, color: S.srgb(0.27, 0.23, 0.16))
        // water: a radial gradient fan
        let radii: [Float] = [0, 0.45, 0.85, 1.12, 1.27]
        let cols = [S.srgb(0.42, 0.64, 0.76), S.srgb(0.34, 0.56, 0.68), S.srgb(0.24, 0.46, 0.56), S.srgb(0.18, 0.40, 0.48), S.srgb(0.15, 0.34, 0.42)]
        let n = 40
        var rings: [[UInt32]] = []
        for (k, rad) in radii.enumerated() {
            if k == 0 { rings.append([b.vertex(V3(c.x + 0.25, 0.03, c.y + 0.15), V3(0, 1, 0), color: cols[0])]); continue }
            rings.append((0..<n).map { j in
                let a = Float(j) / Float(n) * 2 * .pi
                return b.vertex(V3(c.x + cosf(a) * rad + (k < 4 ? 0.25 * (1 - Float(k) / 4) : 0), 0.03, c.y + sinf(a) * rad + (k < 4 ? 0.15 * (1 - Float(k) / 4) : 0)), V3(0, 1, 0), color: cols[k])
            })
        }
        for j in 0..<n { b.triangle(rings[0][0], rings[1][(j + 1) % n], rings[1][j]) }
        for k in 1..<(radii.count - 1) { for j in 0..<n { b.quad(rings[k][j], rings[k][(j + 1) % n], rings[k + 1][(j + 1) % n], rings[k + 1][j]) } }
        // rim stones
        let stones = 22
        for j in 0..<stones {
            let a = (Float(j) + 0.5 * r.unit()) / Float(stones) * 2 * .pi
            let rad = 1.36 + 0.08 * (r.unit() - 0.5)
            let k = 0.78 + 0.4 * r.unit()
            let col = S.srgb(0.47, 0.43, 0.38) * V3(k, k * 0.98, k * 0.96)
            S.blob(b, V3(c.x + cosf(a) * rad, 0.07, c.y + sinf(a) * rad), rx: 0.19 + 0.12 * r.unit(), ry: 0.08 + 0.06 * r.unit(), rz: 0.17 + 0.10 * r.unit(), color: col, segments: 8, rings: 4, ao: 0.9)
        }
        // reeds and cattails on the far side
        for j in 0..<16 {
            let a = (205 + 130 * Float(j) / 15 + 8 * (r.unit() - 0.5)) * .pi / 180
            let rad = 1.5 + 0.45 * r.unit()
            let x = c.x + cosf(a) * rad, z = c.y + sinf(a) * rad
            let h = 0.7 + 0.45 * r.unit()
            let g = S.srgb(0.30, 0.44, 0.17) * (0.85 + 0.3 * r.unit())
            S.stem(b, x: x, z: z, y0: 0, y1: h, r: 0.014, color: g, segments: 4)
            S.stem(b, x: x + 0.05, z: z + 0.03, y0: 0, y1: h * 0.7, r: 0.010, color: g * 0.9, segments: 4)
            if j % 2 == 0 { S.blob(b, V3(x, h - 0.07, z), rx: 0.03, ry: 0.10, rz: 0.03, color: S.srgb(0.30, 0.18, 0.10), segments: 6, rings: 4) }
        }
        lilyPads(b, centre: c, rng: &r)
    }

    /// A slatted timber bench on cast-iron frames (the exact footprint of the old one: x +-1.28, z -4.78 ... -4.22).
    static func bench(_ b: RoomMeshBuilder) {
        let iron = S.srgb(0.13, 0.16, 0.15)
        for (i, dz) in ([-0.225, -0.075, 0.075, 0.225] as [Float]).enumerated() {
            let k = 0.94 + 0.1 * Float(i % 3) / 2
            b.roundedBox(centre: V3(0, 0.50, -4.48 + dz), half: V3(1.28, 0.05, 0.066), radius: 0.02, segments: 2, aoFloor: false, color: S.srgb(0.52, 0.36, 0.21) * k)
        }
        for (i, y) in ([0.74, 0.87, 1.0] as [Float]).enumerated() {
            let k = 0.96 + 0.08 * Float(i % 2)
            b.roundedBox(centre: V3(0, y, -4.80), half: V3(1.28, 0.052, 0.04), radius: 0.018, segments: 2, aoFloor: false, color: S.srgb(0.52, 0.36, 0.21) * k)
        }
        for sx: Float in [-1.1, 1.1] {
            b.roundedBox(centre: V3(sx, 0.23, -4.30), half: V3(0.04, 0.23, 0.04), radius: 0.02, segments: 2, aoFloor: false, color: iron)
            b.roundedBox(centre: V3(sx, 0.52, -4.80), half: V3(0.04, 0.52, 0.04), radius: 0.02, segments: 2, aoFloor: false, color: iron)
            b.roundedBox(centre: V3(sx, 0.40, -4.55), half: V3(0.035, 0.035, 0.27), radius: 0.015, segments: 2, aoFloor: false, color: iron)
            b.roundedBox(centre: V3(sx * 1.07, 0.76, -4.55), half: V3(0.05, 0.03, 0.28), radius: 0.02, segments: 2, aoFloor: false, color: iron)          // armrest
            b.roundedBox(centre: V3(sx * 1.07, 0.60, -4.30), half: V3(0.03, 0.17, 0.03), radius: 0.015, segments: 2, aoFloor: false, color: iron)
        }
    }

    /// A classic dark-green park lamp post (static, plain material).
    static func lampPost(_ b: RoomMeshBuilder, x: Float, z: Float) {
        let green = S.srgb(0.09, 0.22, 0.15)
        S.cylinder(b, x: x, z: z, r: 0.13, y0: 0, y1: 0.22, color: green, segments: 10)
        S.stem(b, x: x, z: z, y0: 0.2, y1: 2.15, r: 0.045, color: green, segments: 8)
        S.cylinder(b, x: x, z: z, r: 0.075, y0: 1.95, y1: 2.02, color: green, segments: 8)
        S.blob(b, V3(x, 2.33, z), rx: 0.15, ry: 0.22, rz: 0.15, color: S.srgb(0.96, 0.92, 0.74), segments: 10, rings: 5)
        S.blob(b, V3(x, 2.58, z), rx: 0.20, ry: 0.07, rz: 0.20, color: green, segments: 10, rings: 4)
    }

    /// A low timber post-and-rail fence along z, in front of the tree line (`skip` = a span left open where the hedge stands).
    static func fence(_ b: RoomMeshBuilder, z: Float, x0: Float, x1: Float, skip: ClosedRange<Float>) {
        let wood = S.srgb(0.42, 0.32, 0.21)
        var x = x0, prev: Float?
        while x <= x1 {
            if !skip.contains(x) {
                b.roundedBox(centre: V3(x, 0.40, z), half: V3(0.05, 0.40, 0.05), radius: 0.02, segments: 2, aoFloor: false, color: wood * (0.9 + 0.2 * vnoise(x, 3)))
                if let p = prev, x - p < 1.5 {
                    for y: Float in [0.30, 0.62] { b.roundedBox(centre: V3((x + p) / 2, y, z), half: V3((x - p) / 2, 0.035, 0.025), radius: 0.012, segments: 2, aoFloor: false, color: wood * 1.05) }
                }
                prev = x
            } else { prev = nil }
            x += 1.4
        }
    }

    /// Three overlapping ridges fading with haze (far bluish, mid, near).
    static func hills(_ b: RoomMeshBuilder) {
        let far = S.srgb(0.42, 0.58, 0.56), mid = S.srgb(0.33, 0.52, 0.38), near = S.srgb(0.28, 0.48, 0.27)
        for (x, rx, ry) in [(-27 as Float, 17 as Float, 5.0 as Float), (-8, 14, 6.2), (12, 16, 4.6), (30, 17, 5.6)] { blob(b, V3(x, -0.6, -9.4), rx: rx, ry: ry, rz: 0.9, color: far, segments: 28, rings: 10) }
        for (x, rx, ry) in [(-21 as Float, 13 as Float, 3.6 as Float), (-1, 12, 4.2), (19, 14, 3.2)] { blob(b, V3(x, -0.6, -9.1), rx: rx, ry: ry, rz: 1.4, color: mid, segments: 28, rings: 10) }
        for (x, rx, ry) in [(-14 as Float, 14 as Float, 2.6 as Float), (8, 12, 2.9), (26, 15, 2.4)] { blob(b, V3(x, -0.6, -8.8), rx: rx, ry: ry, rz: 1.9, color: near, segments: 28, rings: 10) }
    }

    /// A few soft white cumulus with grey-blue undersides.
    static func clouds(_ b: RoomMeshBuilder) {
        let top = S.srgb(0.98, 0.99, 1.0), under = S.srgb(0.72, 0.79, 0.90)
        for (x, y, s) in [(-10 as Float, 12 as Float, 1.0 as Float), (7, 10.5, 1.25), (-1, 14.5, 0.8), (17, 14, 0.9)] {
            blob(b, V3(x, y - 0.35 * s, -9.25), rx: 2.6 * s, ry: 0.45 * s, rz: 0.4, color: under, segments: 14, rings: 5)
            for (k, (dx, dy, rr)) in ([(-1.5, 0.0, 0.85), (-0.5, 0.35, 1.1), (0.7, 0.3, 1.0), (1.7, 0.0, 0.75)] as [(Float, Float, Float)]).enumerated() {
                blob(b, V3(x + dx * s, y + dy * s, -9.2 + 0.01 * Float(k)), rx: rr * 1.1 * s, ry: rr * 0.62 * s, rz: 0.5, color: top, segments: 14, rings: 6)
            }
        }
    }
}
