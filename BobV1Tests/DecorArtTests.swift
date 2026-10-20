//
//  DecorArtTests.swift
//  The Blender decor resources (decor_<id>.bin): each loads, stays inside its triangle budget, has the sub-meshes the code poses, and fits within
//  1.2x of the old procedural piece's bounds.
//

import XCTest
import simd
@testable import BobV1

final class DecorArtTests: XCTestCase {
    private static let parts: [DecorKind: [String]] = [
        .beanbag: ["bag"], .cushion: ["cushion"], .plant: ["pot", "leaves"], .ball: ["ball"], .rug: ["rug"],
        .toybox: ["box", "lid", "toy_bear", "toy_block", "toy_star"], .nightlight: ["base", "glow"], .bouncymat: ["frame", "top"]]
    private static let big: Set<DecorKind> = [.beanbag, .bouncymat, .toybox]
    /// The old procedural pieces' half extents (x, z) and heights.
    private static let old: [DecorKind: (SIMD2<Float>, Float)] = [
        .beanbag: (SIMD2(0.72, 0.72), 0.78), .cushion: (SIMD2(0.40, 0.40), 0.22), .plant: (SIMD2(0.30, 0.30), 1.10), .ball: (SIMD2(0.27, 0.27), 0.54),
        .rug: (SIMD2(0.95, 0.65), 0.06), .toybox: (SIMD2(0.50, 0.38), 0.84), .nightlight: (SIMD2(0.24, 0.24), 0.65), .bouncymat: (SIMD2(0.88, 0.88), 0.12)]

    func testEveryDecorResourceLoadsWithinBudgetWithItsSubMeshesAndBounds() {
        for k in DecorKind.allCases {
            guard let art = DecorMeshes.loaded[k] else { XCTFail("\(k): resource missing"); continue }
            let budget = Self.big.contains(k) ? 2500 : 1500
            XCTAssertLessThanOrEqual(art.triangles, budget, "\(k) tris")
            XCTAssertGreaterThan(art.triangles, 100, "\(k) has geometry")
            for n in Self.parts[k]! { XCTAssertNotNil(art.part(n), "\(k) part \(n)") }
            XCTAssertEqual(art.parts.count, Self.parts[k]!.count, "\(k) parts")
            for p in art.parts { XCTAssertTrue(p.indices.allSatisfy { Int($0) < p.positions.count }, "\(k).\(p.name) indices") }
            let b = art.bounds, (half, h) = Self.old[k]!
            XCTAssertGreaterThanOrEqual(b.lo.y, -0.001, "\(k) stands on the floor")
            XCTAssertLessThanOrEqual(max(-b.lo.x, b.hi.x), half.x * 1.2, "\(k) x")
            XCTAssertLessThanOrEqual(max(-b.lo.z, b.hi.z), half.y * 1.2, "\(k) z")
            XCTAssertLessThanOrEqual(b.hi.y, h * 1.2, "\(k) height")
            XCTAssertEqual(art.part(Self.parts[k]!.last == "glow" ? "glow" : Self.parts[k]![0])?.material, k == .nightlight ? .lamp : .plain, "\(k) material")
        }
        XCTAssertEqual(DecorMeshes.loaded[.nightlight]?.part("base")?.material, .plain)
        // the meshes the room draws are the art, not the fallback
        for k in DecorKind.allCases { XCTAssertGreaterThan(DecorModels.thumbnail(k).indices.count / 3, 100, "\(k) thumbnail") }
        XCTAssertEqual(DecorModels.thumbnail(.beanbag).indices.count / 3, DecorMeshes.loaded[.beanbag]!.triangles)
    }

    func testObstacleFootprintsCoverTheNewMeshes() {
        for k in DecorKind.allCases {
            guard let art = DecorMeshes.loaded[k] else { continue }
            let b = art.bounds, s = k.spec
            XCTAssertLessThanOrEqual(max(-b.lo.x, b.hi.x), s.half.x + 0.06, "\(k) footprint x")
            XCTAssertLessThanOrEqual(max(-b.lo.z, b.hi.z), s.half.y + 0.06, "\(k) footprint z")
        }
    }
}
