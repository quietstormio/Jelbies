//
//  FoodMeshes.swift
//  The Blender-made store foods, loaded from the bundled food_<id>.bin files (tools/convert_food_art.py builds them from the OBJ exports).
//  Format (little endian): u32 vertexCount, u32 indexCount, vertexCount x 10 float32 (pos, normal, LINEAR rgb, ao), indexCount x u16.
//  Each mesh is modelled around the piece centre (plate surface at y = -0.056, the mini pizza at -0.026), so a piece is appended by a transform:
//  scaled by the serving scale, turned by the food's fixed yaw, shifted to the anchor. A missing resource returns false and the caller falls back
//  to the procedural builder in StoreFoodModels.
//

import simd
import Foundation

nonisolated enum FoodMeshes {
    struct Mesh: Sendable {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var colors: [SIMD3<Float>] = []
        var ao: [Float] = []
        var indices: [UInt16] = []
        var triangles: Int { indices.count / 3 }
    }

    private final class Token {}

    /// All meshes that loaded, by resource id ("nuggets", "nuggets_1", ...). Thread-safe lazy static.
    static let loaded: [String: Mesh] = {
        var out: [String: Mesh] = [:]
        for id in resourceIDs { if let m = load(id) { out[id] = m } }
        return out
    }()
    static let resourceIDs = ["nuggets", "nuggets_1", "nuggets_2", "fries", "sushi", "sandwich", "minipizza", "taco", "donut", "popsicle", "onigiri", "cookie",
                                         "swirl", "pancakes", "sundae", "fizzmac", "cafetable_1", "cafetable_2", "cafetable_3"]

    static func load(_ id: String) -> Mesh? {
        let url = Bundle.main.url(forResource: "food_\(id)", withExtension: "bin") ?? Bundle(for: Token.self).url(forResource: "food_\(id)", withExtension: "bin")
        guard let url, let d = try? Data(contentsOf: url), d.count >= 8 else { return nil }
        return d.withUnsafeBytes { raw -> Mesh? in
            let nv = Int(raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self)), ni = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            guard d.count == 8 + nv * 40 + ni * 2, ni % 3 == 0 else { return nil }
            var m = Mesh()
            m.positions.reserveCapacity(nv); m.normals.reserveCapacity(nv); m.colors.reserveCapacity(nv); m.ao.reserveCapacity(nv)
            for k in 0..<nv {
                func f(_ i: Int) -> Float { raw.loadUnaligned(fromByteOffset: 8 + k * 40 + i * 4, as: Float.self) }
                m.positions.append(SIMD3(f(0), f(1), f(2))); m.normals.append(SIMD3(f(3), f(4), f(5))); m.colors.append(SIMD3(f(6), f(7), f(8))); m.ao.append(f(9))
            }
            let base = 8 + nv * 40
            for k in 0..<ni { m.indices.append(raw.loadUnaligned(fromByteOffset: base + k * 2, as: UInt16.self)) }
            return m
        }
    }

    /// Resource id for a piece (the nuggets use their three variants across the three slots).
    static func resource(_ food: String, variant j: Int) -> String {
        food == "nuggets" ? ["nuggets", "nuggets_1", "nuggets_2"][((j % 3) + 3) % 3] : food
    }
    /// How a mesh is placed: a fixed yaw (the taco's long axis runs along x) and a shift of its origin in xz (the ice pop is held by its stick).
    static func placement(_ food: String) -> (yaw: Float, shift: SIMD3<Float>) {
        switch food {
        case "taco": return (.pi / 2, .zero)
        case "popsicle": return (0, SIMD3(0, 0, 0.12))          // grip point (0, -0.04, -0.12) of the stick sits on the piece centre
        default: return (0, .zero)
        }
    }

    /// Appends food `id` centred on `c`, scaled by `s`. False if its resource is missing (use the procedural fallback).
    static func append(_ b: RoomMeshBuilder, id food: String, centre c: SIMD3<Float>, variant j: Int, scale s: Float) -> Bool {
        guard let m = loaded[resource(food, variant: j)] else { return false }
        let pl = placement(food), cy = cosf(pl.yaw), sy = sinf(pl.yaw)
        func rot(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy) }
        let base = UInt32(b.mesh.vertices.count)
        let saved = b.material
        b.material = .plain
        for k in 0..<m.positions.count {
            let p = rot(m.positions[k] + pl.shift) * s + c
            b.mesh.vertices.append(RoomVertex(pos: SIMD4(p, RoomMaterial.plain.rawValue), normal: SIMD4(rot(m.normals[k]), m.ao[k]), color: SIMD4(m.colors[k], 1)))
        }
        b.material = saved
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            // keep the winding agreeing with the vertex normals, like RoomMeshBuilder.triangle
            let a = base + UInt32(m.indices[t]), bb = base + UInt32(m.indices[t + 1]), cc = base + UInt32(m.indices[t + 2])
            b.triangle(a, bb, cc)
        }
        return true
    }

    /// A whole bundled mesh as a RoomMesh, untransformed (the café table skins), or nil when its resource is missing.
    static func mesh(id: String) -> RoomMesh? {
        guard let m = loaded[id] else { return nil }
        var out = RoomMesh()
        for k in 0..<m.positions.count {
            out.vertices.append(RoomVertex(pos: SIMD4(m.positions[k], RoomMaterial.plain.rawValue), normal: SIMD4(m.normals[k], m.ao[k]), color: SIMD4(m.colors[k], 1)))
        }
        out.indices = m.indices.map { UInt32($0) }
        return out
    }
}
