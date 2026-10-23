//
//  RoomDefTests.swift
//  Per-room definitions (Room/RoomDef.swift): the home room must stay exactly as it was, every room keeps the front floor free.
//

import XCTest
import simd
@testable import BobV1

final class RoomDefTests: XCTestCase {
    static func fnv(_ mesh: RoomMesh) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        func feed(_ p: UnsafeRawBufferPointer) { for b in p { h ^= UInt64(b); h = h &* 0x100000001b3 } }
        mesh.vertices.withUnsafeBytes(feed)
        mesh.indices.withUnsafeBytes(feed)
        return h
    }

    func testHomeGeometryHash() {
        let m = RoomGeometry.build(theme: RoomTheme())
        // measured on the untouched round-1022 code (before the per-room refactor)
        XCTAssertEqual(m.vertices.count, 23544)
        XCTAssertEqual(m.indices.count, 121314)
        XCTAssertEqual(Self.fnv(m), 10948828446133751937, "home geometry must stay bit-identical")
    }
}
