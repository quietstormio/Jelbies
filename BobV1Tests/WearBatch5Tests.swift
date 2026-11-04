//
//  WearBatch5Tests.swift
//  The 2026-11-04 wearables (sunny bandana, honey / mint jersey bibs, plum cosy scarf, honey bucket hat, mint pom-pom beanie): sold, art bundled, and kept off the
//  mouth (keep-out ellipse c(0,.651) r(.15,.10)); body and neck pieces stay at y <= 0.575 on the front belly (the jersey band is y <= .51).
//

import XCTest
import simd
@testable import BobV1

final class WearBatch5Tests: XCTestCase {
    static let looks: [WearLook] = [.bandanaSun, .bibHoney, .bibMint, .scarfPlum, .bucketHatHoney, .beanieMint]

    func testTheNewLooksAreSoldWithArt() {
        for l in Self.looks {
            let item = StoreCatalog.item(wearing: l)
            XCTAssertNotNil(item, "\(l) is in the shop")
            XCTAssertGreaterThan(item?.price ?? 0, 0)
            XCTAssertNotNil(WearMeshes.art(l), "\(l) art is bundled")
            XCTAssertGreaterThan(WearMeshes.art(l)?.triangles ?? 0, 100)
        }
    }

    func testTheNewLooksNeverCoverTheMouth() {
        for l in Self.looks where l.slot == .neck || l.slot == .body || l.slot == .face {
            guard let art = WearMeshes.art(l) else { XCTFail("\(l) art"); continue }
            let a = l.row.anchorRest
            var worst: Float = 9, top: Float = -9
            for p in art.parts { for v in p.positions {
                let x = v.x + a.x, y = v.y + a.y, z = v.z + a.z
                guard z >= 0.1 else { continue }
                worst = min(worst, hypotf(x / 0.15, (y - 0.651) / 0.10))
                if abs(x) < 0.3 { top = max(top, y) }
            } }
            XCTAssertGreaterThanOrEqual(worst, 1.0, "\(l) is inside the mouth keep-out")
            if l.slot != .face { XCTAssertLessThanOrEqual(top, 0.575, "\(l) is high on the front") }
        }
    }

    func testTheHatsSitOnTheHeadAnchorLikeTheOtherHats() {
        XCTAssertEqual(WearLook.bucketHatHoney.slot, WearLook.bucketHat.slot); XCTAssertEqual(WearLook.bucketHatHoney.anchor, WearLook.bucketHat.anchor)
        XCTAssertEqual(WearLook.beanieMint.slot, WearLook.beaniePink.slot); XCTAssertEqual(WearLook.beanieMint.anchor, WearLook.beaniePink.anchor)
    }
}
