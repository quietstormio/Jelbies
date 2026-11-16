//
//  ParkMeshGoldenTests.swift
//  The park's own static mesh is pinned (vertex count, index count, FNV-1a of the raw bytes) so the Camp yard's scenery work (camp-yard-r1) provably leaves the park byte-identical.
//  The pins were taken from the tree BEFORE any Camp change (the base + the art only).
//

import XCTest
import simd
@testable import BobV1

final class ParkMeshGoldenTests: XCTestCase {
    static func fnv(_ mesh: RoomMesh) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        func feed(_ p: UnsafeRawBufferPointer) { for b in p { h ^= UInt64(b); h = h &* 0x100000001b3 } }
        mesh.vertices.withUnsafeBytes(feed); mesh.indices.withUnsafeBytes(feed)
        return h
    }
    static let pinVertices = 97152, pinIndices = 522321, pinHash: UInt64 = 6753943185295414633

    func testParkMeshIsPinned() {
        let m = ParkScenery.build(theme: RoomCatalog.park.theme)
        let h = Self.fnv(m)
        NSLog("[parkgolden] vertices=%d indices=%d hash=%llu", m.vertices.count, m.indices.count, h)
        XCTAssertGreaterThan(m.vertices.count, 20000, "the foliage did not load")
        XCTAssertEqual(m.vertices.count, Self.pinVertices)
        XCTAssertEqual(m.indices.count, Self.pinIndices)
        XCTAssertEqual(h, Self.pinHash)
    }
}
