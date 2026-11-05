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
