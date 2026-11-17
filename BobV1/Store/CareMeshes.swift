//
//  CareMeshes.swift
//  The Blender-made Care items (tools/make_care1, exported like make_food4 and converted by tools/convert_food_art.py into Store/Resources/food_care_<id>.bin).
//  One loader for the Shop / Bag thumbnails (a RoomMesh) and for the bath props (BathOverlay). Base centre at the origin, bottom at y = 0, linear vertex colours.
//

import simd
import Foundation

nonisolated enum CareMeshes {
    private static let cache: [String: FoodMeshes.Mesh] = {
        var out: [String: FoodMeshes.Mesh] = [:]
        for id in CareItems.all { if let m = CareItems.mesh(id).flatMap({ FoodMeshes.load($0) }) { out[id] = m } }
        return out
    }()
    /// The raw mesh of the Care item with store id `id` (nil: none or the resource is missing).
    static func mesh(_ id: String) -> FoodMeshes.Mesh? { cache[id] }
    /// How many of the eight Care items have their bundled mesh (the bundle test wants all of them).
    static var loadedCount: Int { cache.count }

    /// As a RoomMesh (plain material) for a thumbnail.
    static func roomMesh(_ id: String) -> RoomMesh? {
        guard let m = mesh(id) else { return nil }
        var r = RoomMesh()
        r.vertices = (0..<m.positions.count).map { RoomVertex(pos: SIMD4(m.positions[$0], RoomMaterial.plain.rawValue), normal: SIMD4(m.normals[$0], m.ao[$0]), color: SIMD4(m.colors[$0], 1)) }
        r.indices = m.indices.map { UInt32($0) }
        return r
    }
}
