//
//  CareMeshes.swift
//  The Blender-made soap bars (tools/make_care1, exported like make_food4 and converted by tools/convert_food_art.py into Store/Resources/food_care_soap_<scent>.bin).
//  One loader for the Shop / Bag / pick-card pictures (a RoomMesh) and the bar in his hand (BathOverlay). Base centre at the origin, bottom at y = 0, linear vertex colours.
//

import simd
import Foundation

nonisolated enum CareMeshes {
    private static let cache: [Soap: FoodMeshes.Mesh] = {
        var out: [Soap: FoodMeshes.Mesh] = [:]
        for s in Soap.allCases { if let m = FoodMeshes.load(s.mesh) { out[s] = m } }
        return out
    }()
    static func mesh(soap: Soap) -> FoodMeshes.Mesh? { cache[soap] }
    /// The bar of the soap with Shop id `id` (nil for any other item).
    static func mesh(_ id: String) -> FoodMeshes.Mesh? { Soap.of(storeID: id).flatMap { cache[$0] } }
    /// How many of the six bars have their bundled mesh (the bundle test wants all of them).
    static var loadedCount: Int { cache.count }

    static func roomMesh(soap: Soap) -> RoomMesh? {
        guard let m = cache[soap] else { return nil }
        var r = RoomMesh()
        r.vertices = (0..<m.positions.count).map { RoomVertex(pos: SIMD4(m.positions[$0], RoomMaterial.plain.rawValue), normal: SIMD4(m.normals[$0], m.ao[$0]), color: SIMD4(m.colors[$0], 1)) }
        r.indices = m.indices.map { UInt32($0) }
        return r
    }
    static func roomMesh(_ id: String) -> RoomMesh? { Soap.of(storeID: id).flatMap { roomMesh(soap: $0) } }
}
