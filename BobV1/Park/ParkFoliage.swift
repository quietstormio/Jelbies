//
//  ParkFoliage.swift
//  The park's trees, bushes and flower patches (redesigned 2026-11-09): Blender-made assets (tools/make_park_foliage: an oak, a beech and a birch with forked limbs under lobed leaf clumps; 2 spruces of drooping bough
//  tiers; shrubs, a clipped hedge, a grass-and-flower clump; cheaper `_far` variants for the back rows) loaded from the bundled park_<id>.bin files
//  (the decor .bin format, vertex colours with the sun / shade / hue / AO baked in) and stamped into the static park mesh with per-instance rotation, scale and tint.
//  The groomer street's backdrop shares `roundTree`. Static and built once: no per-frame cost, no extra draw calls.
//

import simd
import Foundation

extension ParkScenery {
    enum TreeShape { case auto, round, conifer }

    private enum Art {
        static func load(_ ids: [String]) -> [DecorMeshes.Art] { ids.compactMap { DecorMeshes.load($0, prefix: "park_") } }
        static let trees = load(["tree_a", "tree_b", "tree_c"])
        static let treesFar = load(["tree_a_far", "tree_b_far", "tree_c_far"])
        static let pines = load(["pine_a", "pine_b"])
        static let pinesFar = load(["pine_a_far", "pine_b_far"])
        static let bushes = load(["bush_a", "bush_b"])
        static let hedge = load(["hedge"])
        static let hedgeLow = load(["hedge_low"])
        static let flowers = load(["flowers"])
    }
    /// The nominal leaf colour the assets are painted for: an instance's `canopy` colour tints the baked leaves by `canopy / leafRef`.
    private static let leafRef = S.srgb(0.24, 0.45, 0.17)

    /// Stamps one asset at `o`: yawed, scaled (`k` = across, `ky` = up) and tinted per part name (parts without an entry keep their baked colour).
    private static func stamp(_ b: RoomMeshBuilder, _ art: DecorMeshes.Art, at o: V3, yaw: Float, k: Float, ky: Float, tint: [String: V3], desat: Float = 0, hue: V3 = V3(repeating: 1)) {
        let c = cosf(yaw), s = sinf(yaw)
        func rot(_ v: V3) -> V3 { V3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c) }
        for part in art.parts {
            let t = tint[part.name] ?? V3(repeating: 1), leafy = part.name == "leaf" && desat > 0
            let base = UInt32(b.mesh.vertices.count), mat = part.material.rawValue
            for i in 0..<part.positions.count {
                let p = part.positions[i], n = part.normals[i]
                var col = part.colors[i] * t
                if leafy { let l = simd_dot(col, V3(0.2126, 0.7152, 0.0722)); col = simd_mix(col, hue * l * 0.86, V3(repeating: desat)) }          // (a touch darker: the street's muted sage, not lime)
                b.mesh.vertices.append(RoomVertex(pos: SIMD4(o + rot(V3(p.x * k, p.y * ky, p.z * k)), mat), normal: SIMD4(rot(n), part.ao[i]), color: SIMD4(col, 1)))
            }
            for i in stride(from: 0, to: part.indices.count, by: 3) { b.triangle(base + part.indices[i], base + part.indices[i + 1], base + part.indices[i + 2]) }
        }
    }

    /// A tree (a deciduous or a conifer, per `shape`) at (x, z): `radius` is the canopy's rough radius, `canopy` the leaf colour (the baked greens are re-tinted by canopy / leafRef, so
    /// natural greens near it barely change); yaw, size and hue vary per tree from `rng`. `species` picks the deciduous asset (0 oak, 1 beech, 2 birch; nil = random);
    /// `far` picks the cheap variant (nil = trees behind z -6, i.e. the back rows and the groomer's street). (`trunk` is kept for the callers; the assets carry their own trunk.)
    static func roundTree(_ b: RoomMeshBuilder, x: Float, z: Float, trunk h0: Float, radius R0: Float, canopy: V3, shape: TreeShape = .auto, species: Int? = nil, far: Bool? = nil, rng r: inout ParkRandom) {
        let sc = 0.88 + 0.26 * r.unit(), tall = 0.92 + 0.16 * r.unit(), yaw = r.unit() * 6.283
        let hue = V3(0.98 + 0.04 * r.unit(), 0.98 + 0.04 * r.unit(), 0.97 + 0.06 * r.unit())          // (barely varied: one green family)
        var conifer = shape == .conifer
        if shape == .auto { conifer = r.unit() < 0.26 }
        let pick = species.map { (Float($0) + 0.5) / 3 } ?? r.unit()
        let isFar = far ?? (z < -6)
        let ratio = canopy * hue / leafRef
        // a muted canopy colour (the groomer street's sage trees) pulls the baked greens toward that hue instead of just tinting them
        let sat = (max(canopy.x, canopy.y, canopy.z) - min(canopy.x, canopy.y, canopy.z)) / max(0.001, max(canopy.x, canopy.y, canopy.z))
        let desat = min(1, max(0, (0.6 - sat) / 0.4)) * 1.0, lum = max(0.001, simd_dot(canopy, V3(0.2126, 0.7152, 0.0722)))
        let tint = ["leaf": simd_clamp(simd_mix(V3(repeating: 1), ratio, V3(repeating: 0.55)), V3(repeating: 0.3), V3(repeating: 1.8))]
        let pines = isFar && !Art.pinesFar.isEmpty ? Art.pinesFar : Art.pines, trees = isFar && !Art.treesFar.isEmpty ? Art.treesFar : Art.trees
        if conifer, !pines.isEmpty {
            let a = pines[min(pines.count - 1, Int(pick * Float(pines.count)))]
            let k = R0 * sc * 0.78
            stamp(b, a, at: V3(x, 0, z), yaw: yaw, k: k, ky: k * tall, tint: tint, desat: desat, hue: canopy * hue / lum)
        } else if !trees.isEmpty {
            let a = trees[min(trees.count - 1, Int(pick * Float(trees.count)))]
            let k = R0 * sc * 0.9
            stamp(b, a, at: V3(x, 0, z), yaw: yaw, k: k, ky: k * tall, tint: tint, desat: desat, hue: canopy * hue / lum)
        }
    }

    /// A clipped hedge run at (x, z), `s` times the asset's 2 m length.
    static func hedge(_ b: RoomMeshBuilder, x: Float, z: Float, scale s: Float, yaw: Float, low: Bool = false, rng r: inout ParkRandom) {
        guard let a = (low ? Art.hedgeLow.first ?? Art.hedge.first : Art.hedge.first) else { return }
        stamp(b, a, at: V3(x, 0, z), yaw: yaw, k: s, ky: s * (0.95 + 0.1 * r.unit()), tint: ["leaf": V3(0.95 + 0.1 * r.unit(), 1.0, 0.95 + 0.1 * r.unit())])
    }

    /// A flowering bush at (x, z): two bush variants, yawed and sized per bush; `bloom` tints the blossoms.
    static func floweringBush(_ b: RoomMeshBuilder, x: Float, z: Float, scale s0: Float, bloom: V3, rng r: inout ParkRandom) {
        let pick = r.unit(), s = s0 * 1.25 * (0.92 + 0.16 * r.unit()), yaw = r.unit() * 6.283
        let leaf = V3(0.95 + 0.1 * r.unit(), 1.0, 0.95 + 0.1 * r.unit())
        guard !Art.bushes.isEmpty else { return }
        let a = Art.bushes[min(Art.bushes.count - 1, Int(pick * Float(Art.bushes.count)))]
        stamp(b, a, at: V3(x, 0, z), yaw: yaw, k: s, ky: s * (0.95 + 0.1 * r.unit()), tint: ["leaf": leaf, "bloom": bloom])
    }

    /// A flower-and-grass clump at (x, z); `bloom` tints the flowers.
    static func flowerPatch(_ b: RoomMeshBuilder, x: Float, z: Float, scale s: Float, bloom: V3, rng r: inout ParkRandom) {
        guard let a = Art.flowers.first else { return }
        let k = s * 1.7 * (0.92 + 0.16 * r.unit())
        stamp(b, a, at: V3(x, 0, z), yaw: r.unit() * 6.283, k: k, ky: k, tint: ["leaf": V3(1.0, 1.05, 1.0), "bloom": bloom])
    }
}
