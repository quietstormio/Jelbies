//
//  ParkFoliage.swift
//  The park's trees, bushes and flower patches (2026-11-04 redo): trees have a flared, tapering trunk with a few branches and a canopy of 8-10 irregular leaf clumps
//  (varied size, hue and height) or stacked conifer tiers; bushes are clumps of leafy lobes with blossom clusters sitting on the foliage; flower patches are tufts
//  of grass blades with short-stemmed blossoms. Leaf clumps are hand-lit per vertex (sunlit yellow-green tops, dark undersides and inner faces, noise crevices).
//  Everything is built once into the static park mesh (shared by the groomer street's backdrop): no per-frame cost, no extra draw calls.
//

import simd
import Foundation

extension ParkScenery {
    // MARK: leafy lobes (the building block of trees and bushes)

    /// Cheap deterministic 3D noise in about [-1, 1] from sines, so shared pole / seam vertices displace identically.
    private static func leafNoise(_ p: V3, _ seed: Float) -> Float {
        let a = sinf(p.x * 5.3 + p.z * 3.1 + seed) * sinf(p.y * 4.7 + p.x * 2.3 - seed * 0.7)
        let c = sinf(p.x * 11.0 - p.y * 9.0 + p.z * 7.0 + seed * 1.9) * 0.5
        return max(-1, min(1, (a + c) * 0.8))
    }

    /// One leaf clump: an ellipsoid whose surface is broken up by noise, hand-lit (sunlit top, shaded underside, darker where it faces the canopy's inside and in the
    /// noise crevices). `tree` is the whole canopy's (centre, bottom y, top y) so every lobe shares one vertical gradient.
    static func leafLobe(_ b: RoomMeshBuilder, _ c: V3, rx: Float, ry: Float, rz: Float, color: V3, tree: (centre: V3, y0: Float, y1: Float),
                         seed: Float, bump: Float = 0.06, segments: Int = 16, rings: Int = 8) {
        var ids: [[UInt32]] = []
        for i in 0...rings {
            let el = -Float.pi / 2 + Float.pi * Float(i) / Float(rings)
            var row: [UInt32] = []
            for j in 0...segments {
                let az = Float(j) / Float(segments) * 2 * .pi
                let d = V3(cosf(el) * cosf(az), sinf(el), cosf(el) * sinf(az))
                let n0 = leafNoise(c + d * 0.9, seed)
                let p = c + V3(d.x * rx, d.y * ry, d.z * rz) * (1 + bump * n0)
                let wob = V3(leafNoise(p * 1.7, seed + 3), leafNoise(p * 1.7, seed + 5), leafNoise(p * 1.7, seed + 7)) * bump * 0.6
                let nrm = simd_normalize(V3(d.x / rx, d.y / ry, d.z / rz) * min(rx, ry, rz) + wob)
                let sun = max(-0.5, simd_dot(nrm, sunDir))
                let h = max(0, min(1, (p.y - tree.y0) / max(0.01, tree.y1 - tree.y0)))
                var inward = V3(tree.centre.x - p.x, 0, tree.centre.z - p.z)
                inward = simd_length(inward) > 0.01 ? simd_normalize(inward) : V3(0, 0, 0)
                let facingIn = max(0, simd_dot(V3(d.x, 0, d.z), inward))
                var shade = (0.58 + 0.30 * h) + 0.30 * sun
                shade *= 1 - 0.16 * facingIn
                shade *= 0.93 + 0.07 * n0
                let vary = V3(1 + 0.06 * leafNoise(p * 2.3, seed + 11), 1 + 0.07 * leafNoise(p * 2.1, seed + 13), 1 + 0.06 * leafNoise(p * 2.5, seed + 17))          // crevices darker, bumps brighter
                let warm = max(0, sun) * 0.12 * (0.4 + h)          // sunlit tops lean yellow-green
                let col = V3(color.x * shade * (1 + warm * 1.1), color.y * shade * (1 + warm * 0.5), color.z * shade * (1 - warm * 0.6)) * vary
                row.append(b.vertex(p, nrm, ao: 1, color: col))
            }
            ids.append(row)
        }
        for i in 0..<rings { for j in 0..<segments { b.quad(ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]) } }
    }

    /// A tapered 5-sided branch between two points.
    static func limb(_ b: RoomMeshBuilder, from a: V3, to e: V3, r0: Float, r1: Float, color: V3) {
        let axis = simd_normalize(e - a)
        let up: V3 = abs(axis.y) > 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)
        let u = simd_normalize(simd_cross(axis, up)), v = simd_cross(axis, u)
        let n = 5
        var lo: [UInt32] = [], hi: [UInt32] = []
        for j in 0...n {
            let t = Float(j) / Float(n) * 2 * .pi
            let d = u * cosf(t) + v * sinf(t)
            lo.append(b.vertex(a + d * r0, d, ao: 0.8, color: color * 0.9))
            hi.append(b.vertex(e + d * r1, d, ao: 1, color: color))
        }
        for j in 0..<n { b.quad(lo[j], lo[j + 1], hi[j + 1], hi[j]) }
    }

    // MARK: trees

    enum TreeShape { case auto, round, conifer }

    /// A tree with a visible tapered trunk, a few branches and a canopy of irregular leaf clumps, or a stacked conifer. Size, hue and clump layout vary per tree
    /// from `rng`. `canopy` is the leaf colour, `radius` the canopy's rough radius.
    static func roundTree(_ b: RoomMeshBuilder, x: Float, z: Float, trunk h0: Float, radius R0: Float, canopy: V3, shape: TreeShape = .auto, rng r: inout ParkRandom) {
        let R = R0 * (0.88 + 0.26 * r.unit()), h = h0 * (0.9 + 0.3 * r.unit())
        let leaf = canopy * V3(0.93 + 0.14 * r.unit(), 0.94 + 0.12 * r.unit(), 0.90 + 0.18 * r.unit())
        let seed = r.unit() * 40
        let bark = S.srgb(0.50, 0.37, 0.28) * (0.9 + 0.2 * r.unit())
        var conifer = shape == .conifer
        if shape == .auto { conifer = r.unit() < 0.26 }
        if conifer {
            let tall = R * 1.9
            let tcol0 = leaf * V3(0.78, 0.86, 0.92)
            b.lathe(cx: x, cz: z, profile: [PP(r: 0.17 * R * 0.7, y: 0, nr: 1, ny: 0, ao: 0.7), PP(r: 0.11 * R * 0.7, y: h * 0.9, nr: 1, ny: 0.05)], segments: 8, color: bark)
            let tiers = 4
            for t in 0..<tiers {
                let f = Float(t) / Float(tiers)
                let y0 = h * 0.7 + tall * f * 0.82, rb = R * (0.78 - 0.5 * f) * (0.94 + 0.12 * r.unit()), tip = y0 + tall * 0.42
                let first = b.mesh.vertices.count
                let tcol = tcol0 * (1 + 0.10 * f)
                b.lathe(cx: x, cz: z, profile: [
                    PP(r: 0, y: y0 - rb * 0.1, nr: 0, ny: -1, ao: 0.55), PP(r: rb * 0.8, y: y0 - rb * 0.03, nr: 0.3, ny: -0.95, ao: 0.6), PP(r: rb, y: y0 + 0.02, nr: 0.8, ny: -0.3, ao: 0.7),
                    PP(r: rb * 0.9, y: y0 + 0.12, nr: 0.9, ny: 0.4, ao: 0.85), PP(r: rb * 0.5, y: (y0 + tip) * 0.5 + 0.03, nr: 0.85, ny: 0.55, ao: 0.95),
                    PP(r: 0, y: tip, nr: 0.4, ny: 0.9, ao: 1)], segments: 18, color: tcol)
                let ph = r.unit() * 6.28
                for i in first..<b.mesh.vertices.count {
                    var p = b.mesh.vertices[i].pos
                    let n = b.mesh.vertices[i].normal
                    let dx = p.x - x, dz = p.z - z, rad = sqrtf(dx * dx + dz * dz), ang = atan2f(dz, dx)
                    let wob = 1 + 0.09 * sinf(ang * 3 + ph) * min(1, rad / max(0.01, rb)) + 0.03 * sinf(ang * 5 + ph * 2)
                    p.x = x + dx * wob; p.z = z + dz * wob
                    let sun = max(-0.5, simd_dot(simd_normalize(V3(n.x, n.y, n.z)), sunDir))
                    let k = (0.64 + 0.5 * max(0, sun + 0.2) - 0.1 * max(0, -n.y)) * (1 + 0.05 * sinf(ang * 4 + p.y * 3))
                    b.mesh.vertices[i].pos = p
                    b.mesh.vertices[i].color = SIMD4(tcol.x * k, tcol.y * k * (1 + 0.05 * max(0, sun)), tcol.z * k, 1)
                }
            }
            return
        }
        // trunk: flared foot, tapering up into the canopy
        let cy = h + R * 0.80
        b.lathe(cx: x, cz: z, profile: [PP(r: 0.30 * R * 0.7, y: 0, nr: 1, ny: 0.3, ao: 0.6), PP(r: 0.19 * R * 0.7, y: h * 0.25, nr: 1, ny: 0.05, ao: 0.8),
                                        PP(r: 0.14 * R * 0.7, y: h, nr: 1, ny: 0), PP(r: 0.10 * R * 0.7, y: h + R * 0.55, nr: 1, ny: 0)], segments: 9, color: bark)
        // branches reaching up and out into the clumps
        let nb = 3, a0 = r.unit() * 6.28
        for i in 0..<nb {
            let a = a0 + Float(i) / Float(nb) * 2 * .pi + 0.4 * (r.unit() - 0.5)
            let from = V3(x, h * (0.75 + 0.2 * r.unit()), z)
            let to = V3(x + cosf(a) * R * 0.55, cy - R * 0.05 + 0.2 * R * r.unit(), z + sinf(a) * R * 0.5)
            limb(b, from: from, to: to, r0: 0.06 * R, r1: 0.025 * R, color: bark * 0.95)
        }
        // canopy: a centre clump, a ring of side clumps and a couple of small top clumps
        let tree = (centre: V3(x, cy, z), y0: cy - R * 0.62, y1: cy + R * 0.95)
        leafLobe(b, V3(x, cy + R * 0.12, z), rx: R * 0.72, ry: R * 0.60, rz: R * 0.68, color: leaf, tree: tree, seed: seed)
        let ring = 5 + Int(r.unit() * 2.5), off = r.unit() * 6.28
        for i in 0..<ring {
            let a = off + Float(i) / Float(ring) * 2 * .pi + 0.35 * (r.unit() - 0.5)
            let dist = R * (0.52 + 0.24 * r.unit()), rr = R * (0.40 + 0.20 * r.unit())
            let yy = cy + R * (-0.22 + 0.42 * r.unit())
            leafLobe(b, V3(x + cosf(a) * dist, yy, z + sinf(a) * dist * 0.92), rx: rr, ry: rr * (0.78 + 0.12 * r.unit()), rz: rr * 0.94,
                     color: leaf * (0.92 + 0.16 * r.unit()), tree: tree, seed: seed + Float(i) * 1.7)
        }
        for i in 0..<2 {
            let a = off + 1.3 + Float(i) * 2.9 + r.unit()
            let rr = R * (0.30 + 0.12 * r.unit())
            leafLobe(b, V3(x + cosf(a) * R * 0.3, cy + R * (0.60 + 0.14 * r.unit()), z + sinf(a) * R * 0.28), rx: rr, ry: rr * 0.85, rz: rr,
                     color: leaf * 1.06, tree: tree, seed: seed + 9 + Float(i), segments: 14, rings: 7)
        }
    }

    // MARK: flowering bushes and patches

    /// A leafy mound of 6-8 irregular clumps (varied size, hue and height), with blossom clusters sitting on the foliage.
    static func floweringBush(_ b: RoomMeshBuilder, x: Float, z: Float, scale s0: Float, bloom: V3, rng r: inout ParkRandom) {
        let s = s0 * 1.3 * (0.92 + 0.16 * r.unit())
        let leaf = S.srgb(0.46, 0.74, 0.38) * V3(0.95 + 0.1 * r.unit(), 0.96 + 0.08 * r.unit(), 0.94 + 0.12 * r.unit())
        let seed = r.unit() * 40
        let tree = (centre: V3(x, 0.4 * s, z), y0: Float(0), y1: 0.95 * s)
        var lobes: [(V3, Float)] = [(V3(0, 0.42, 0), 0.52)]
        let n = 5 + Int(r.unit() * 2.5), off = r.unit() * 6.28
        for i in 0..<n {
            let a = off + Float(i) / Float(n) * 2 * .pi + 0.3 * (r.unit() - 0.5), d = 0.55 + 0.30 * r.unit()
            lobes.append((V3(cosf(a) * d * 1.1, 0.20 + 0.28 * r.unit(), sinf(a) * d * 0.8), 0.30 + 0.14 * r.unit()))
        }
        for (i, l) in lobes.enumerated() {
            let c = V3(x, 0, z) + l.0 * s
            leafLobe(b, c, rx: l.1 * s, ry: l.1 * s * 0.82, rz: l.1 * s * 0.92, color: leaf * (0.92 + 0.16 * r.unit()), tree: tree, seed: seed + Float(i) * 2.3, bump: 0.08, segments: 14, rings: 7)
        }
        // blossoms: little clusters resting on the upper, outward half of random lobes
        for _ in 0..<15 {
            let l = lobes[min(lobes.count - 1, Int(r.unit() * Float(lobes.count)))]
            let az = r.unit() * 6.28, el = 0.2 + r.unit() * 1.0
            let d = V3(cosf(el) * cosf(az), sinf(el), cosf(el) * sinf(az))
            let base = V3(x, 0, z) + l.0 * s + d * (l.1 * s)
            for _ in 0..<(2 + Int(r.unit() * 2)) {
                let o = V3(r.unit() - 0.5, r.unit() * 0.4, r.unit() - 0.5) * 0.11 * s
                S.ball(b, base + o + d * 0.01, 0.075 * s * (0.8 + 0.4 * r.unit()), bloom * (0.92 + 0.14 * r.unit()), segments: 7, rings: 4)
            }
        }
    }

    /// A small tuft of grass blades (two-sided, dark at the foot and bright at the tip) with short-stemmed blossoms among them.
    static func flowerPatch(_ b: RoomMeshBuilder, x: Float, z: Float, scale s0: Float, bloom: V3, rng r: inout ParkRandom) {
        let s = s0 * 1.7
        let g0 = S.srgb(0.34, 0.62, 0.30), g1 = S.srgb(0.62, 0.86, 0.44), gm = simd_mix(g0, g1, SIMD3(repeating: 0.5))
        for _ in 0..<38 {
            let a = r.unit() * 6.28, d = sqrtf(r.unit()) * 0.5 * s
            let p0 = V3(x + cosf(a) * d * 1.15, 0, z + sinf(a) * d * 0.85)
            let hgt = (0.16 + 0.20 * r.unit()) * s * (1.1 - 0.5 * d / (0.5 * s))
            let dir = a + (r.unit() - 0.5) * 1.2
            let lean = V3(cosf(dir), 0, sinf(dir)) * hgt * (0.25 + 0.4 * r.unit())
            let side = V3(-sinf(dir), 0, cosf(dir)) * 0.028 * s
            let p1 = p0 + lean * 0.35 + V3(0, hgt * 0.55, 0), p2 = p0 + lean + V3(0, hgt, 0)
            let tint = 0.9 + 0.2 * r.unit()
            for face: Float in [1, -1] {
                let nrm = simd_normalize(V3(cosf(dir), 0.6, sinf(dir)) * face * 0.5 + V3(0, 0.8, 0))
                let va = b.vertex(p0 - side, nrm, ao: 0.7, color: g0 * tint), vb = b.vertex(p0 + side, nrm, ao: 0.7, color: g0 * tint)
                let vc = b.vertex(p1 - side * 0.7, nrm, ao: 0.9, color: gm * tint), vd = b.vertex(p1 + side * 0.7, nrm, ao: 0.9, color: gm * tint)
                let ve = b.vertex(p2, nrm, ao: 1, color: g1 * tint)
                b.quad(va, vb, vd, vc); b.triangle(vc, vd, ve)
            }
        }
        for k in 0..<9 {
            let a = Float(k) / 9 * 2 * .pi + r.unit() * 0.6, d = (k == 0 ? 0.05 : 0.18 + 0.2 * r.unit()) * s
            let fx = x + cosf(a) * d, fz = z + sinf(a) * d * 0.8, fh = (0.20 + 0.10 * r.unit()) * s
            S.stem(b, x: fx, z: fz, y0: 0, y1: fh, r: 0.008 * s, color: g0 * 1.2, segments: 4)
            S.ball(b, V3(fx, fh + 0.015, fz), 0.07 * s, bloom * (0.94 + 0.12 * r.unit()), segments: 7, rings: 4)
            S.ball(b, V3(fx, fh + 0.03, fz), 0.02 * s, S.srgb(0.99, 0.85, 0.35), segments: 5, rings: 3)
        }
    }
}
