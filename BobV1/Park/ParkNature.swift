//
//  ParkNature.swift
//  The park's plants, built once into the park's static room mesh (ParkScenery.build) in the living room's calm style: smooth round tree canopies on short
//  trunks, puffy flowering bushes (round blossoms in blush, butter, cream and lilac), low round-blossom patches (never stems) and the pond's lily pads.
//  Static only: no per-frame cost, no extra draw calls.
//

import simd
import Foundation

extension ParkScenery {
    typealias S = ParkShapes
    typealias V3 = SIMD3<Float>

    /// The sun side of the park's key light (up, a little right and toward the camera): clump faces turned this way brighten, the rest sink into shade.
    private static let sunDir = simd_normalize(V3(0.45, 0.8, 0.4))

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

    // MARK: trees

    /// A soft round tree: a short chunky trunk and one smooth round canopy (plus two smaller lobes for a gently lumpy outline). `canopy` is the leaf colour.
    static func roundTree(_ b: RoomMeshBuilder, x: Float, z: Float, trunk h: Float, radius R: Float, canopy: V3, rng r: inout ParkRandom) {
        let bark = S.srgb(0.60, 0.44, 0.32)
        b.lathe(cx: x, cz: z, profile: [PP(r: 0.20 * R * 0.7, y: 0, nr: 1, ny: 0, ao: 0.7), PP(r: 0.14 * R * 0.7, y: h, nr: 1, ny: 0.05)], segments: 12, color: bark)
        let cy = h + R * 0.62
        lit(b, V3(x, cy, z), rx: R, ry: R * 0.86, rz: R * 0.92, color: canopy, segments: 24, rings: 12, soft: 0.5)
        lit(b, V3(x - R * 0.62, cy - R * 0.22, z + R * 0.12), rx: R * 0.55, ry: R * 0.5, rz: R * 0.52, color: canopy * 0.97, segments: 20, rings: 10, soft: 0.5)
        lit(b, V3(x + R * 0.64, cy - R * 0.18, z + R * 0.1), rx: R * 0.52, ry: R * 0.48, rz: R * 0.5, color: canopy * 1.03, segments: 20, rings: 10, soft: 0.5)
    }

    // MARK: flowering bushes and patches (round blossoms only)

    /// A puffy green mound of three overlapping lobes studded with round blossoms of `bloom`.
    static func floweringBush(_ b: RoomMeshBuilder, x: Float, z: Float, scale s: Float, bloom: V3, rng r: inout ParkRandom) {
        let leaf = S.srgb(0.40, 0.66, 0.36)
        let lobes: [(V3, V3)] = [(V3(0, 0.38, 0), V3(0.95, 0.62, 0.8)), (V3(-0.7, 0.28, 0.08), V3(0.6, 0.44, 0.55)), (V3(0.7, 0.3, 0.1), V3(0.62, 0.46, 0.55))]
        for (k, l) in lobes.enumerated() {
            lit(b, V3(x + l.0.x * s, l.0.y * s, z + l.0.z * s), rx: l.1.x * s, ry: l.1.y * s, rz: l.1.z * s, color: leaf * (0.96 + 0.04 * Float(k)), segments: 20, rings: 10, soft: 0.5)
        }
        for _ in 0..<26 {
            let a = (r.unit() - 0.5) * 3.4 - .pi / 2 + .pi / 2 * 0, e = 0.15 + r.unit() * 0.8
            let px = x + sinf(a) * 1.05 * s * cosf(e), py = 0.34 * s + sinf(e) * 0.62 * s, pz = z + cosf(a) * 0.82 * s * cosf(e) + 0.05 * s
            S.ball(b, V3(px, py, pz), 0.085 * s * (0.85 + 0.3 * r.unit()), bloom * (0.94 + 0.12 * r.unit()), segments: 8, rings: 4)
        }
    }

    /// A low round patch of blossoms: a flat green cushion with a cluster of round blossoms (no stems).
    static func flowerPatch(_ b: RoomMeshBuilder, x: Float, z: Float, scale s: Float, bloom: V3, rng r: inout ParkRandom) {
        lit(b, V3(x, 0.04, z), rx: 0.62 * s, ry: 0.13 * s, rz: 0.46 * s, color: S.srgb(0.40, 0.66, 0.36), segments: 18, rings: 6, soft: 0.5)
        for k in 0..<7 {
            let a = Float(k) / 7 * 2 * .pi + r.unit() * 0.5, d = (k == 0 ? 0 : 0.34 + 0.12 * r.unit()) * s
            S.ball(b, V3(x + cosf(a) * d, 0.15 * s, z + sinf(a) * d * 0.7), 0.10 * s, bloom * (0.95 + 0.1 * r.unit()), segments: 8, rings: 4)
        }
    }

    /// Lily pads (notched discs) with a couple of blossoms, floating on the pond.
    static func lilyPads(_ b: RoomMeshBuilder, centre c: SIMD2<Float>, rng r: inout ParkRandom) {
        let spots: [(Float, Float, Float)] = [(-0.45, 0.35, 0.27), (0.3, -0.45, 0.23), (0.45, 0.35, 0.22), (-0.2, -0.2, 0.18)]
        for (k, p) in spots.enumerated() {
            let col = S.srgb(0.36, 0.66, 0.40) * (0.95 + 0.1 * r.unit())
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
                S.ball(b, f + V3(0, 0.03, 0), 0.075, S.srgb(0.99, 0.84, 0.88), segments: 10, rings: 5)
            }
        }
    }
}
