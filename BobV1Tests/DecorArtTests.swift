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
        .toybox: ["box", "lid", "toy_bear", "toy_block", "toy_star"], .nightlight: ["base", "glow"], .bouncymat: ["frame", "top"],
        // the second batch
        .loveseat: ["sofa", "seat"], .petbed: ["rim", "mat"], .pouf: ["pouf"], .rockingchair: ["runners", "chair", "cushion"], .armchair: ["chair", "seat"],
        .swing: ["stand", "seat"], .diningset: ["table", "stool_l", "stool_r"], .bookshelf: ["shelf", "plant"], .wardrobe: ["wardrobe", "door_l", "clothes"],
        .divider: ["screen"], .floorlamp: ["stand", "shade"], .slide: ["slide"], .monstera: ["pot", "leaves"], .duck: ["duck"],
        .blocks: ["block0", "block1", "block2", "block3", "block4"], .spintop: ["top"], .toycar: ["body", "wheel_fl", "wheel_rl", "wheel_fr", "wheel_rr"],
        .yarnball: ["ball", "strand"], .drum: ["body", "head"], .football: ["ball"]]
    private static let big: Set<DecorKind> = [.beanbag, .bouncymat, .toybox, .loveseat, .diningset]
    /// Parts that stick out past the footprint on purpose (a canopy, an open door, a trailing strand, a lamp shade).
    private static let canopy: Set<String> = ["leaves", "strand", "door_l", "shade", "clothes"]
    /// The old procedural pieces' half extents (x, z) and heights.
    private static let old: [DecorKind: (SIMD2<Float>, Float)] = [
        .beanbag: (SIMD2(0.72, 0.72), 0.78), .cushion: (SIMD2(0.40, 0.40), 0.22), .plant: (SIMD2(0.30, 0.30), 1.10), .ball: (SIMD2(0.27, 0.27), 0.54),
        .rug: (SIMD2(0.95, 0.65), 0.06), .toybox: (SIMD2(0.50, 0.38), 0.84), .nightlight: (SIMD2(0.24, 0.24), 0.65), .bouncymat: (SIMD2(0.88, 0.88), 0.12)]

    func testEveryDecorResourceLoadsWithinBudgetWithItsSubMeshesAndBounds() {
        for k in DecorKind.allCases {
            guard let art = DecorMeshes.loaded[k] else { XCTFail("\(k): resource missing"); continue }
            if !DecorKind.original.contains(k) { checkBatch2(k, art); continue }
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

    /// A second-batch piece: loads, within budget, has every sub-mesh the code poses (and no more), indices in range, stands on the floor, and is drawn from its art.
    private func checkBatch2(_ k: DecorKind, _ art: DecorMeshes.Art) {
        XCTAssertLessThanOrEqual(art.triangles, Self.big.contains(k) ? 2500 : 1500, "\(k) tris")
        XCTAssertGreaterThan(art.triangles, 100, "\(k) has geometry")
        for n in Self.parts[k]! { XCTAssertNotNil(art.part(n), "\(k) part \(n)"); XCTAssertGreaterThan(art.part(n)?.triangles ?? 0, 0, "\(k).\(n) is not empty") }
        XCTAssertEqual(art.parts.count, Self.parts[k]!.count, "\(k) parts")
        for p in art.parts { XCTAssertTrue(p.indices.allSatisfy { Int($0) < p.positions.count }, "\(k).\(p.name) indices") }
        XCTAssertGreaterThanOrEqual(art.bounds.lo.y, -0.03, "\(k) stands on the floor")
        for p in art.parts { XCTAssertEqual(p.material, k == .floorlamp && p.name == "shade" ? .lamp : .plain, "\(k).\(p.name): only the lamp shade glows") }
        XCTAssertEqual(DecorModels.thumbnail(k).indices.count / 3, art.triangles, "\(k) thumbnail is the whole art")
    }

    func testObstacleFootprintsCoverTheNewMeshes() {
        for k in DecorKind.allCases {
            guard let art = DecorMeshes.loaded[k] else { continue }
            let s = k.spec
            // (the 1.25x swing keeps its authored depth and the slide its authored width as walking footprints: the room has no space for more, see DecorKind.spec)
            let slack: Float = k == .swing || k == .slide ? 0.3 : 0.06
            for p in art.parts where !Self.canopy.contains(p.name) || DecorKind.original.contains(k) {
                let lo = p.positions.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }, hi = p.positions.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
                XCTAssertLessThanOrEqual(max(-lo.x, hi.x), s.half.x + slack, "\(k).\(p.name) footprint x")
                XCTAssertLessThanOrEqual(max(-lo.z, hi.z), s.half.y + slack, "\(k).\(p.name) footprint z")
            }
        }
    }
}
