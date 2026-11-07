//
//  BowTieNoBandTests.swift
//  A bow tie is ONLY the bow, sitting on the chest: no band or strap round the body (2026-11-06, the park screenshot of Pickle).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BowTieNoBandTests: XCTestCase {
    static let bows: [WearLook] = [.bowtiePink, .bowtieSky]

    func testBowTiesBuildNoBand() throws {
        WearBody.install(MotionRig.renderMesh)
        WearMeshes.clearCache()
        XCTAssertFalse(WearRules.bowKeepsBand)
        for l in Self.bows {
            XCTAssertFalse(WearLevel.tilts(l), "\(l) is not a necklace-class tilted piece")
            XCTAssertNil(WearRules.neckLift(l), "\(l) has no neck lift (it was for the band)")
            guard let p = WearMeshes.prepare(l, body: WearBody.shared) else { XCTFail("no art"); continue }
            XCTAssertFalse(p.partNames.contains("band"), "\(l) has no band part")
            XCTAssertFalse(p.levelPiece, "\(l): no ring, nothing levelled")
            XCTAssertFalse(p.tilted)
            XCTAssertTrue(p.anyBound)
            // the whole bow rides the skin (a half-bound bow would tear), partNames line up with partOfVertex
            XCTAssertTrue(p.w.allSatisfy { $0 > 0.99 }, "\(l): every bow vertex is skin-bound")
            XCTAssertTrue(p.partOfVertex.allSatisfy { Int($0) < p.partNames.count })
            // no encircling geometry: the azimuth coverage round the body axis is small (a band covers the whole circle)
            let zc = WearBody.shared.axisZ
            var bins = Set<Int>()
            for q in p.rest { bins.insert(min(35, Int((atan2(q.x, q.z - zc) + .pi) / (2 * .pi) * 36))) }
            XCTAssertLessThan(bins.count, 12, "\(l): the bow covers \(bins.count)/36 azimuth bins")
            // the bow stays out of the mouth keep-out ellipse c(0,.651) r(.15,.10) in the rest frame
            for q in p.rest { let x = q.x / 0.15, y = (q.y - 0.651) / 0.10; XCTAssertGreaterThanOrEqual(x * x + y * y, 1, "\(l) vertex in the mouth keep-out") }
            // the same bow vertices as before, minus the band
            let kept = WearMeshes.art(l)!.parts.filter { $0.name != "band" }.reduce(0) { $0 + $1.positions.count }
            XCTAssertEqual(p.rest.count, kept)
        }
    }

    func testLegacySwitchKeepsBand() throws {
        WearBody.install(MotionRig.renderMesh)
        WearRules.bowKeepsBand = true; WearMeshes.clearCache()
        defer { WearRules.bowKeepsBand = false; WearMeshes.clearCache() }
        let p = WearMeshes.prepare(.bowtieSky, body: WearBody.shared)!
        XCTAssertTrue(p.partNames.contains("band"))
    }
}
