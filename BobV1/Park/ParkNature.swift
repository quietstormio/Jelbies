//
//  ParkNature.swift
//  The park's plants, built once into the park's static room mesh (ParkScenery.build) in the living room's calm style: clumped leafy tree canopies (see ParkFoliage.swift:
//  trunks, branches, conifers, flowering bushes, grass-and-flower patches).
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
        var c = S.srgb(0.30, 0.50, 0.25)
        c *= 1 - 0.14 * sstep(1.5, 7.5, z)          // a little darker toward the near edge
        c = simd_mix(c, S.srgb(0.34, 0.56, 0.28), V3(repeating: 0.45 * sstep(0.62, 0.9, vnoise(x * 0.09, z * 0.11, 21))))          // broad sunlit patches
        c = simd_mix(c, S.srgb(0.26, 0.44, 0.22), V3(repeating: 0.45 * sstep(0.62, 0.92, vnoise(x * 0.08, z * 0.1, 33))))          // damp, darker patches
        let band = 0.5 + 0.5 * sinf(z * 0.95 + 1.6 * vnoise(x * 0.12, z * 0.2, 1) + x * 0.06)
        c *= 1 + 0.06 * (2 * band - 1)
        c *= 1 + 0.05 * (2 * vnoise(x * 0.3, z * 0.3, 7) - 1)
        c = simd_mix(c, S.srgb(0.33, 0.54, 0.27), V3(repeating: 0.55 * sstep(0.55, 0.85, vnoise(x * 0.16, z * 0.16, 3))))
        c = simd_mix(c, S.srgb(0.27, 0.46, 0.23), V3(repeating: 0.25 * sstep(0.55, 0.9, vnoise(x * 0.22, z * 0.22, 11))))
        let off = -SIMD2<Float>(sunDir.x, sunDir.z) / sunDir.y
        for sh in shadows {
            let cx = sh.x + off.x * sh.h * 0.35, cz = sh.z + off.y * sh.h * 0.35
            let d = hypotf(x - cx, (z - cz) * 1.15) / (sh.r * 0.95)
            let a = 1 - sstep(0.25, 1.0, d)
            c = simd_mix(c, c * V3(0.74, 0.80, 0.84), V3(repeating: 0.8 * a))
        }
        if z < 13.5, z > -3.9 {
            let dx = fabsf(x - pathX(z)) - 0.62
            let a = (1 - sstep(0.0, 0.13, dx)) * (0.30 + 0.4 * vnoise(x * 0.9, z * 0.9, 5))
            c = simd_mix(c, S.srgb(0.40, 0.34, 0.22), V3(repeating: min(0.55, a)))
        }
        let ld = hypotf((x - 2.9) / 0.62, (z - 3.25) / 0.42)
        c = simd_mix(c, S.srgb(0.40, 0.34, 0.22), V3(repeating: 0.42 * (1 - sstep(0.4, 1.0, ld))))
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

    /// A classic dark-green park lamp post with a real lantern: base plate, slim post, a four-post frame round warm glass, a dark cap with a finial (static, plain material).
    static func lampPost(_ b: RoomMeshBuilder, x: Float, z: Float) {
        let green = S.srgb(0.09, 0.22, 0.15), glass = S.srgb(0.98, 0.88, 0.58)
        S.cylinder(b, x: x, z: z, r: 0.14, y0: 0, y1: 0.12, color: green, segments: 10)
        S.cylinder(b, x: x, z: z, r: 0.09, y0: 0.12, y1: 0.30, color: green, segments: 10)
        S.stem(b, x: x, z: z, y0: 0.3, y1: 2.12, r: 0.04, color: green, segments: 8)
        S.cylinder(b, x: x, z: z, r: 0.14, y0: 2.10, y1: 2.16, color: green, segments: 8)
        b.material = .lamp          // (the glass: material 5 glows with the room's lamp glow, which comes up at dusk)
        S.cylinder(b, x: x, z: z, r: 0.095, y0: 2.16, y1: 2.50, color: glass, segments: 10)
        b.material = .plain
        for (dx, dz) in [(0.115 as Float, 0.0 as Float), (-0.115, 0), (0, 0.115), (0, -0.115)] { S.stem(b, x: x + dx, z: z + dz, y0: 2.14, y1: 2.52, r: 0.016, color: green, segments: 4) }
        b.lathe(cx: x, cz: z, profile: [PP(r: 0.0, y: 2.49, nr: 0, ny: -1), PP(r: 0.19, y: 2.49, nr: 0, ny: -1), PP(r: 0.19, y: 2.53, nr: 1, ny: 0), PP(r: 0.0, y: 2.76, nr: 0.55, ny: 0.85)], segments: 10, color: green)
        S.ball(b, V3(x, 2.79, z), 0.035, green, segments: 6, rings: 3)
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
        // (drawn behind the whole tree line: thin in z, so no ridge ever stands in front of a tree)
        let far = S.srgb(0.62, 0.74, 0.80), mid = S.srgb(0.52, 0.68, 0.58), near = S.srgb(0.38, 0.56, 0.38)
        for (x, rx, ry) in [(-27 as Float, 17 as Float, 6.2 as Float), (-8, 14, 7.4), (12, 16, 5.8), (30, 17, 6.8)] { blob(b, V3(x, -0.6, -9.50), rx: rx, ry: ry, rz: 0.4, color: far, segments: 28, rings: 10) }
        for (x, rx, ry) in [(-21 as Float, 13 as Float, 4.6 as Float), (-1, 12, 5.4), (19, 14, 4.0)] { blob(b, V3(x, -0.6, -9.42), rx: rx, ry: ry, rz: 0.4, color: mid, segments: 28, rings: 10) }
        for (x, rx, ry) in [(-14 as Float, 14 as Float, 3.0 as Float), (8, 12, 3.4), (26, 15, 2.8)] { blob(b, V3(x, -0.6, -9.34), rx: rx, ry: ry, rz: 0.4, color: near, segments: 28, rings: 10) }
    }

    /// A few small, distant, rounded cumulus: bright tops fading to a soft pale blue-grey underside (per-vertex, no flat base), in the sky band between the ridge tops and the top UI.
    static func clouds(_ b: RoomMeshBuilder) {
        let top = S.srgb(1.0, 1.0, 1.0), under = S.srgb(0.80, 0.87, 0.95)
        func puff(_ c: V3, _ rx: Float, _ ry: Float) {
            let first = b.mesh.vertices.count
            blob(b, c, rx: rx, ry: ry, rz: 0.45, color: top, segments: 14, rings: 7)
            for i in first..<b.mesh.vertices.count {
                let t = (b.mesh.vertices[i].pos.y - (c.y - ry)) / (2 * ry)          // 0 at the bottom, 1 at the top
                let k = sstep(0.05, 0.62, t)
                b.mesh.vertices[i].color = SIMD4(simd_mix(under, top, V3(repeating: k)), 1)
            }
        }
        for (x, y, s) in [(-3.6 as Float, 9.6 as Float, 0.75 as Float), (0.8, 10.6, 0.9), (4.2, 9.1, 0.8), (-7.2, 10.2, 0.85), (7.8, 10.4, 0.9), (-0.2, 8.4, 0.55)] {
            puff(V3(x, y, -9.2), 0.95 * s, 0.55 * s)
            puff(V3(x - 0.85 * s, y - 0.12 * s, -9.18), 0.7 * s, 0.42 * s)
            puff(V3(x + 0.85 * s, y - 0.1 * s, -9.19), 0.75 * s, 0.45 * s)
            puff(V3(x + 0.15 * s, y + 0.32 * s, -9.21), 0.6 * s, 0.42 * s)
        }
    }

    /// The park's entrance border (below the roam floor's front edge, z 4.5): low clipped hedge runs either side of the path with the opening where the path comes through, two stone piers,
    /// flower drifts, a few rocks and larger shrubs in the two bottom corners. Nothing here is taller than the rule 1.44 x height < distance in front of z 4.5 allows (hedges 0.5 from z 5.7,
    /// piers 0.7 from z 5.7); the bottom centre (the path, where the Go home pill sits) stays open.
    static func entrance(_ b: RoomMeshBuilder, rng r: inout ParkRandom) {
        let zh: Float = 5.95, px = pathX(zh)
        for (i, x) in ([-1.25, -2.9, -4.55, -6.2, -7.85, -9.5] as [Float]).enumerated() { hedge(b, x: px + x - 0.6 + 0.0 * Float(i), z: zh + (r.unit() - 0.5) * 0.1, scale: 0.85, yaw: (r.unit() - 0.5) * 0.06, low: true, rng: &r) }
        for x in ([2.55, 4.2, 5.85, 7.5, 9.15] as [Float]) { hedge(b, x: px + x - 0.6, z: zh + (r.unit() - 0.5) * 0.1, scale: 0.85, yaw: (r.unit() - 0.5) * 0.06, low: true, rng: &r) }
        // two plain stone gate piers at the opening
        let stone = S.srgb(0.55, 0.53, 0.50)
        for sx: Float in [-1.02, 1.02] {
            b.roundedBox(centre: V3(px + sx, 0.30, zh), half: V3(0.16, 0.30, 0.16), radius: 0.03, segments: 2, aoFloor: false, color: stone)
            b.roundedBox(centre: V3(px + sx, 0.63, zh), half: V3(0.21, 0.04, 0.21), radius: 0.02, segments: 2, aoFloor: false, color: stone * 1.12)
        }
        // flower drifts (natural garden colours) well in front of the hedge, off the path
        let cream = S.srgb(0.95, 0.92, 0.82), butter = S.srgb(0.93, 0.86, 0.58), lavender = S.srgb(0.74, 0.68, 0.84)
        for (x, z, c) in [(-2.5 as Float, 7.3 as Float, cream), (-4.2, 8.7, lavender), (3.0, 7.9, butter)] {
            flowerPatch(b, x: x, z: z, scale: 0.8, bloom: c, rng: &r)
        }
        // rocks
        for (x, z, s) in [(-1.7 as Float, 6.9 as Float, 1.0 as Float), (2.4, 6.7, 0.8), (-3.7, 7.7, 1.2), (4.0, 8.0, 1.0), (-2.7, 9.1, 0.9), (1.9, 8.5, 0.7), (4.6, 7.2, 0.8)] {
            let k = 0.8 + 0.4 * r.unit()
            S.blob(b, V3(x, 0.06 * s, z), rx: 0.26 * s, ry: 0.14 * s, rz: 0.2 * s, color: S.srgb(0.50, 0.46, 0.41) * k, segments: 8, rings: 4, ao: 0.9)
        }
        // larger shrubs frame the two bottom corners
        floweringBush(b, x: -4.2, z: 8.2, scale: 1.1, bloom: S.srgb(0.95, 0.92, 0.82), rng: &r)
        floweringBush(b, x: 4.5, z: 8.4, scale: 1.1, bloom: S.srgb(0.74, 0.68, 0.84), rng: &r)
    }
}
