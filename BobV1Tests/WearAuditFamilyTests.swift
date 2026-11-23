//
//  WearAuditFamilyTests.swift
//  wear-audit-r1: the mouth keep-out for the art VARIANTS the body families wear (Pip's `_pip` capes / backpacks and the nopom / nobutton / short hats Moss's daisy and Pip's
//  spikes put on), not only the plain art of `WearTests.testNoWearableVertexIsInsideTheMouthKeepOutAtRest`.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WearAuditFamilyTests: XCTestCase {
    func testEveryArtVariantStaysOutOfTheMouthAtRest() {
        WearBody.install(MotionRig.renderMesh)
        let body = WearBody.shared
        let variantArts = ["beanie_honey_nopom", "beanie_pink_nopom", "cap_team_pink_nobutton", "cap_team_sky_nobutton", "party_hat_nopom", "party_hat_short"]
        var checked = 0
        for l in WearLook.pieces where !WearRules.isArm(l) {
            var arts: [String] = [l.art + "_pip"]
            arts += variantArts.filter { $0.hasPrefix(l.art + "_") }
            for a in arts {
                guard let p = WearMeshes.prepare(l, body: body, art: a), p.rest.count > 0 else { continue }
                checked += 1
                for (i, r) in p.rest.enumerated() where r.z > 0.15 {
                    XCTAssertGreaterThanOrEqual(WearTests.ellipse(r), 1.0, "\(l) art \(a) vertex \(i) at \(r) is on the mouth")
                }
            }
        }
        XCTAssertGreaterThan(checked, 5, "the variants were found")
    }
}
