//
//  FeatureMeshes.swift
//  The character features' art (feature_<id>.bin, tools/convert_char_art.py), prepared for the game like the wardrobe (WearMeshes): one flat vertex
//  list in rest space, grouped in rigid PARTS. Every part has a pivot bound to the rest egg surface (WearBody) and its vertices stored as offsets from
//  that pivot, so at runtime a part is: carried pivot (the skinned surface under it) + the body's carry rotation / squash x the part's own animation
//  rotation x offset. Pip's spines pivot at their sunk bases, the daisy's stem and leaves at the stem root and its flower at the flower centre (each
//  petal also keeps its root hinge for the night close), Lavender's wings at their hinges.
//  Placement variants (the on-hat daisy at a hat's anchor / tilt / sink, the wings shifted by dy) are prepared and cached per placement key.
//

import simd
import Foundation

nonisolated final class FeaturePrepared: @unchecked Sendable {
    struct Part {
        var name: String
        var first = 0, count = 0
        /// Rest-space pivot (absolute) and its surface bind.
        var pivot = SIMD3<Float>.zero
        var bind = SurfaceBind()
        /// Petals: the root hinge (rest, absolute) and the axis the petal closes about (unit, rest frame).
        var hinge = SIMD3<Float>.zero, hingeAxis = SIMD3<Float>.zero
        var isPetal = false
        var side = 0           // wings: 0 right (+x), 1 left (-x); spines: index; else 0
        var group = 0          // daisy: 0 stem / leaves, 1 flower
    }
    let art: String
    let key: String
    var parts: [Part] = []
    /// Rest-space positions (absolute), offsets from the part pivot, normals, linear colours, AO; triangle indices.
    var rest: [SIMD3<Float>] = [], off: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = [], ao: [Float] = []
    var idx: [UInt32] = []
    var partOfVertex: [Int] = []
    /// Where the whole feature scales about when it pops on / off.
    var anchor = SIMD3<Float>.zero
    var triangles: Int { idx.count / 3 }
    init(art: String, key: String) { self.art = art; self.key = key }
    func part(_ n: String) -> Part? { parts.first { $0.name == n } }
}

nonisolated enum FeatureMeshes {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var arts: [String: DecorMeshes.Art?] = [:]
    nonisolated(unsafe) private static var prepared: [String: FeaturePrepared] = [:]

    /// Budget: like the wardrobe (every feature is rebuilt every frame for every Jelly).
    static let vertexBudget = 1000, triangleBudget = 1500
    /// Lavender's wings, uniformly scaled about each wing's hinge at build time (the art is drawn full size; 0.85 = the "slightly smaller" wings of
    /// 2026-10-21). The hinges, binds and the measured clearance tables are untouched: smaller wings only clear the worn items by more. (A var for the
    /// before / after captures; the cache key carries it.)
    nonisolated(unsafe) static var wingScale: Float = 0.85

    static func art(_ id: String) -> DecorMeshes.Art? {
        lock.lock(); defer { lock.unlock() }
        if let a = arts[id] { return a }
        let a = DecorMeshes.load(id, prefix: "feature_")
        arts[id] = .some(a)
        return a
    }
    static func clearCache() { lock.lock(); prepared = [:]; lock.unlock() }

    /// The placement of a feature: the daisy on a hat (anchor / tilt / sink, work/daisy.py) or the wings shifted by dy.
    struct Placement: Hashable, Sendable {
        var onHat = false
        var anchor = SIMD3<Float>(0, 1.3458, 0), tilt: Float = 0, sink: Float = 0
        var dy: Float = 0
        var key: String { onHat ? String(format: "hat:%.4f,%.4f,%.4f/%.1f/%.3f", anchor.x, anchor.y, anchor.z, tilt, sink) : String(format: "dy:%.3f", dy) }
    }

    /// The prepared feature (cached per placement). `body` binds the part pivots.
    static func prepare(_ f: JellyFeature, placement p: Placement = Placement(), body: WearBody, spec: FeatureSpec = .shared) -> FeaturePrepared? {
        guard f != .none else { return nil }
        let id = (f == .daisy && p.onHat) ? spec.daisyOnHat.id : f.art
        let key = id + "|" + p.key + (f == .wings ? String(format: "|s%.3f", wingScale) : "")
        lock.lock(); let c = prepared[key]; lock.unlock()
        if let c { return c }
        guard let a = art(id) else { return nil }
        let r = build(f, id: id, art: a, placement: p, body: body, spec: spec)
        lock.lock(); prepared[key] = r; lock.unlock()
        return r
    }

    static func rotX(_ deg: Float) -> simd_float3x3 { simd_float3x3(simd_quatf(angle: deg * .pi / 180, axis: SIMD3(1, 0, 0))) }

    static func build(_ f: JellyFeature, id: String, art a: DecorMeshes.Art, placement p: Placement, body: WearBody, spec: FeatureSpec) -> FeaturePrepared {
        let r = FeaturePrepared(art: id, key: p.key)
        // the rest-space placement of every vertex: anchor + offset, then the variant transform
        let anchorRest: SIMD3<Float>
        switch f {
        case .spines: anchorRest = SIMD3(0, spec.top, 0)
        case .daisy: anchorRest = (p.onHat ? spec.daisyOnHat : spec.daisy).anchor.v3
        case .wings: anchorRest = spec.wings.anchor.v3
        case .none: anchorRest = .zero
        }
        let crown = SIMD3<Float>(0, spec.top, 0)
        let RT = rotX(p.tilt)
        let shift = SIMD3<Float>(0, p.dy, 0)
        func place(_ v: SIMD3<Float>) -> SIMD3<Float> {
            let q = anchorRest + v
            if f == .daisy && p.onHat { return RT * (q - crown) + p.anchor - (RT * SIMD3<Float>(0, 1, 0)) * p.sink }
            if f == .wings { return q + shift }
            return q
        }
        func placeN(_ n: SIMD3<Float>) -> SIMD3<Float> { (f == .daisy && p.onHat) ? RT * n : n }
        func placePoint(_ q: SIMD3<Float>) -> SIMD3<Float> {       // an absolute rest point (pivot / hinge) under the same transform
            if f == .daisy && p.onHat { return RT * (q - crown) + p.anchor - (RT * SIMD3<Float>(0, 1, 0)) * p.sink }
            if f == .wings { return q + shift }
            return q
        }
        r.anchor = placePoint(f == .wings ? SIMD3(0, 0.8, -0.35) : crown)
        let daisy = p.onHat ? spec.daisyOnHat : spec.daisy
        let flowerC = placePoint(daisy.flowerCentre.v3), flowerN = simd_normalize(placeN(daisy.flowerNormal.v3))
        for (pi, part) in a.parts.enumerated() {
            var pr = FeaturePrepared.Part(name: part.name)
            pr.first = r.rest.count; pr.count = part.positions.count
            var pivot: SIMD3<Float>
            switch f {
            case .spines:
                let s = spec.spines.first { $0.part == part.name }
                pivot = placePoint(crown + (s?.pivot.v3 ?? .zero)); pr.side = spec.spines.firstIndex { $0.part == part.name } ?? pi
            case .daisy:
                if part.name == "stem" || part.name.hasPrefix("leaf") { pivot = placePoint(daisy.stemPivot.v3); pr.group = 0 }
                else { pivot = flowerC; pr.group = 1 }
            case .wings:
                let side = part.name.hasPrefix("wing_l") ? "l" : "r"
                pivot = placePoint(spec.wings.sides[side]?.hinge.v3 ?? .zero); pr.side = side == "l" ? 1 : 0
            case .none: pivot = .zero
            }
            pr.pivot = pivot
            pr.bind = body.bind(pivot) ?? SurfaceBind()
            var centroid = SIMD3<Float>.zero
            let partScale: Float = f == .wings ? wingScale : 1
            for k in 0..<part.positions.count {
                var q = place(part.positions[k])
                if partScale != 1 { q = pivot + (q - pivot) * partScale }           // the wings: smaller about their hinge, still rooted there
                r.rest.append(q); r.off.append(q - pivot); r.nrm.append(simd_normalize(placeN(part.normals[k]))); r.col.append(part.colors[k]); r.ao.append(part.ao[k])
                r.partOfVertex.append(pi)
                centroid += q
            }
            centroid /= Float(max(part.positions.count, 1))
            if f == .daisy, daisy.petals.contains(part.name) {
                // the root = the petal vertex nearest the flower centre; it closes about the tangent (root x normal), tip toward the normal
                pr.isPetal = true
                var best = Float.infinity, root = centroid
                for k in pr.first..<(pr.first + pr.count) { let d = simd_distance_squared(r.rest[k], flowerC); if d < best { best = d; root = r.rest[k] } }
                pr.hinge = root
                var radial = centroid - flowerC
                radial -= flowerN * simd_dot(radial, flowerN)
                let rl = simd_length(radial)
                radial = rl > 1e-6 ? radial / rl : SIMD3(1, 0, 0)
                pr.hingeAxis = simd_normalize(simd_cross(radial, flowerN))
            }
            // trust the vertex normals over the file's winding (the renderer culls back faces)
            let base = UInt32(pr.first)
            var t = 0
            while t + 2 < part.indices.count {
                let i0 = part.indices[t], i1 = part.indices[t + 1], i2 = part.indices[t + 2]
                let g = simd_cross(part.positions[Int(i1)] - part.positions[Int(i0)], part.positions[Int(i2)] - part.positions[Int(i0)])
                let nn = part.normals[Int(i0)] + part.normals[Int(i1)] + part.normals[Int(i2)]
                if simd_dot(g, nn) >= 0 { r.idx += [base + i0, base + i1, base + i2] } else { r.idx += [base + i0, base + i2, base + i1] }
                t += 3
            }
            r.parts.append(pr)
        }
        return r
    }
}
