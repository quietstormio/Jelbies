//
//  DecorMeshes.swift
//  The Blender-made decor, loaded from the bundled decor_<id>.bin files (tools/convert_decor_art.py builds them from the OBJ exports).
//  Format (little endian): u32 vertexCount, u32 indexCount, u32 partCount, partCount x { char name[16], u32 firstIndex, u32 indexCount, u32 material,
//  f32 pivot[3] }, vertexCount x 11 float32 (pos, normal, LINEAR rgb, ao, w), indexCount x u16 (global vertex indices).
//  Each part is split out with its own vertex list at load. Game coordinates, y up, piece origin = footprint centre on the floor. `DecorModels`
//  poses the parts (squish by w, sway by w, roll, dip, lid, toy jumps) and falls back to the procedural builders when a resource is missing.
//

import simd
import Foundation

nonisolated enum DecorMeshes {
    struct Part: Sendable {
        var name: String
        var material: RoomMaterial
        var pivot: SIMD3<Float>
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var colors: [SIMD3<Float>] = []
        var ao: [Float] = []
        var w: [Float] = []
        var indices: [UInt32] = []
        var triangles: Int { indices.count / 3 }
    }
    struct Art: Sendable {
        var parts: [Part]
        var triangles: Int { parts.reduce(0) { $0 + $1.triangles } }
        func part(_ n: String) -> Part? { parts.first { $0.name == n } }
        /// Every position and pivot times `k` (normals and the rest unchanged): the in-game size of a piece authored small.
        func scaled(_ k: Float, x kx: Float? = nil) -> Art {
            var a = self
            let m = SIMD3<Float>(kx ?? k, k, k)
            for i in a.parts.indices { a.parts[i].pivot *= m; a.parts[i].positions = a.parts[i].positions.map { $0 * m } }
            return a
        }
        var bounds: (lo: SIMD3<Float>, hi: SIMD3<Float>) {
            var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
            for p in parts { for v in p.positions { lo = simd_min(lo, v); hi = simd_max(hi, v) } }
            return (lo, hi)
        }
    }

    private final class Token {}

    /// Every piece that loaded, by kind. Thread-safe lazy static.
    static let loaded: [DecorKind: Art] = {
        var out: [DecorKind: Art] = [:]
        for k in DecorKind.allCases { if let a = load(k.rawValue) { out[k] = k.scale == 1 ? a : a.scaled(k.scale, x: k.scaleX) } }
        return out
    }()

    static func load(_ id: String, prefix: String = "decor_") -> Art? {
        let url = Bundle.main.url(forResource: "\(prefix)\(id)", withExtension: "bin") ?? Bundle(for: Token.self).url(forResource: "\(prefix)\(id)", withExtension: "bin")
        guard let url, let d = try? Data(contentsOf: url), d.count >= 12 else { return nil }
        return d.withUnsafeBytes { raw -> Art? in
            func u32(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
            func f32(_ o: Int) -> Float { raw.loadUnaligned(fromByteOffset: o, as: Float.self) }
            let nv = u32(0), ni = u32(4), np = u32(8)
            let headEnd = 12 + np * 40, vertEnd = headEnd + nv * 44
            guard d.count == vertEnd + ni * 2, ni % 3 == 0 else { return nil }
            var parts: [Part] = []
            for p in 0..<np {
                let o = 12 + p * 40
                let nameBytes = (0..<16).map { raw.loadUnaligned(fromByteOffset: o + $0, as: UInt8.self) }.prefix { $0 != 0 }
                var part = Part(name: String(decoding: nameBytes, as: UTF8.self), material: { switch u32(o + 24) { case 5: return .lamp; case 4: return .glow; default: return .plain } }(),
                                pivot: SIMD3(f32(o + 28), f32(o + 32), f32(o + 36)))
                let first = u32(o + 16), count = u32(o + 20)
                var remap: [Int: UInt32] = [:]
                for t in first..<(first + count) {
                    let g = Int(raw.loadUnaligned(fromByteOffset: vertEnd + t * 2, as: UInt16.self))
                    if let l = remap[g] { part.indices.append(l); continue }
                    let vo = headEnd + g * 44
                    let l = UInt32(part.positions.count)
                    remap[g] = l
                    part.positions.append(SIMD3(f32(vo), f32(vo + 4), f32(vo + 8)))
                    part.normals.append(SIMD3(f32(vo + 12), f32(vo + 16), f32(vo + 20)))
                    part.colors.append(SIMD3(f32(vo + 24), f32(vo + 28), f32(vo + 32)))
                    part.ao.append(f32(vo + 36)); part.w.append(f32(vo + 40))
                    part.indices.append(l)
                }
                parts.append(part)
            }
            return Art(parts: parts)
        }
    }

    /// Appends one part, each vertex moved by `pose(position, normal, w)` (both in piece space), then shifted by `offset`.
    static func emit(_ part: Part, into b: RoomMeshBuilder, offset: SIMD3<Float>, pose: ((SIMD3<Float>, SIMD3<Float>, Float) -> (SIMD3<Float>, SIMD3<Float>))? = nil) {
        let base = UInt32(b.mesh.vertices.count)
        let mat = part.material.rawValue
        for k in 0..<part.positions.count {
            var p = part.positions[k], n = part.normals[k]
            if let pose { (p, n) = pose(p, n, part.w[k]) }
            b.mesh.vertices.append(RoomVertex(pos: SIMD4(p + offset, mat), normal: SIMD4(n, part.ao[k]), color: SIMD4(part.colors[k], 1)))
        }
        for t in stride(from: 0, to: part.indices.count, by: 3) { b.triangle(base + part.indices[t], base + part.indices[t + 1], base + part.indices[t + 2]) }
    }
}
