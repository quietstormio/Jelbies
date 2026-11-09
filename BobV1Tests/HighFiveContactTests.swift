//
//  HighFiveContactTests.swift
//  The high five (side by side facing the camera: phase 2 = the wind-up, both near arms lift and swing back in; phase 3 = the hands meet, the slap; BlobSocial+Friends.driveHighFive, BlobSocial+Hands.swift)
//  measured at the contact frame in the Duo: hand-to-hand gap 0 +- 0.5 cm, the bodies do not overlap (no hand inside the partner's egg, egg-to-egg gap >= -1 cm), the feet stay planted.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HighFiveContactTests: XCTestCase {
    func testHighFiveHandsMeetAtZeroGapFeetPlanted() {
        for (seed, starts) in [(UInt64(41), [SIMD2<Float>(-1.5, 0.6), SIMD2<Float>(1.35, 0.9)]), (UInt64(42), [SIMD2<Float>(1.5, 0.3), SIMD2<Float>(-1.2, 1.1)])] {
            let d = FeatureClipTests.Duo(positions: starts, features: [.none, .none], seed: seed)
            d.live = true
            for _ in 0..<3 { d.tick() }
            let a = d.lab.rigs[0], b = d.lab.rigs[1]
            XCTAssertTrue(a.brain.socialStart(.highFive, with: b.brain, a.sim))
            var hhFirst: Float?, hhMin: Float = .infinity, handInBody: Float = .infinity, eggGap: Float = .infinity, skinGapMin: Float = .infinity
            var planted = true, p2Start: [SIMD2<Float>]?, drift: Float = 0, framesSinceImpact = -1
            var windUpPeakGap: Float = 0, sawPhase2 = false, sawPhase3 = false
            for _ in 0..<(60 * 14) {
                d.tick()
                let ph = a.brain.social?.phase ?? 0
                if ph >= 2 {
                    if p2Start == nil { p2Start = [a.brain.position, b.brain.position] }
                    if a.brain.feet.active || b.brain.feet.active || a.brain.stepLive || b.brain.stepLive || a.brain.gait.isBusy || b.brain.gait.isBusy { planted = false }
                    drift = max(drift, simd_distance(a.brain.position, p2Start![0]), simd_distance(b.brain.position, p2Start![1]))
                }
                if ph == 2 {          // the wind-up: the hands open up (the arms lift and the pole's reach shrinks)
                    sawPhase2 = true
                    d.skinForContact()
                    let h = ContactPolishTests.handHandNow(d, n: 2)
                    if h < BruteForceContactMetric.farApart { windUpPeakGap = max(windUpPeakGap, h) }
                }
                if ph == 3 { sawPhase3 = true }
                if ph == 3, a.brain.social?.impacted == true {
                    framesSinceImpact += 1
                    if framesSinceImpact <= 10 {          // (the impact frame and the next ten: the drive sets `impacted` on the touch gate's event, the closest approach is within a few ticks)
                        let S = d.contactSurfaces()          // (skins every body once)
                        let Sb = d.contactSurfacesNoSkin(bodyOnly: true)
                        let h = ContactPolishTests.handHandNow(d, n: 2)
                        if hhFirst == nil { hhFirst = h }
                        hhMin = min(hhMin, h)
                        for i in 0..<2 { for tip in d.contactHandTips(i) { for j in 0..<2 where j != i { handInBody = min(handInBody, BruteForceContactMetric.handGap(tip: tip, against: Sb[j])) } } }
                        eggGap = min(eggGap, BruteForceContactMetric.skinGap(Sb[0], Sb[1]))
                        skinGapMin = min(skinGapMin, BruteForceContactMetric.skinGap(S[0], S[1]))
                    }
                }
                if ph >= 4 { break }
            }
            MotionLog.write(String(format: "HIGHFIVE seed %d: wind-up peak hand gap %.4f, hand-hand first %.4f min %.4f, hand vs body %.4f, egg gap min %.4f, whole-skin gap min %.4f, drift %.3f, planted %d", Int(seed), windUpPeakGap, hhFirst ?? -1, hhMin, handInBody, eggGap, skinGapMin, drift, planted ? 1 : 0))
            XCTAssertTrue(sawPhase2 && sawPhase3, "seed \(seed): the wind-up (phase 2) runs, then the slap (phase 3)")
            guard let first = hhFirst else { XCTFail("seed \(seed): the hands never met (no impact in phase 3)"); continue }
            XCTAssertGreaterThan(windUpPeakGap, 0.02, "seed \(seed): the wind-up visibly opens the hands (>2 cm) before they meet")
            XCTAssertLessThan(hhMin, BruteForceContactMetric.farApart, "seed \(seed): the arms are drawn at the touch")
            XCTAssertLessThanOrEqual(hhMin, 0.005, "seed \(seed): hand-to-hand gap within 0.5 cm at the contact frame")
            XCTAssertLessThanOrEqual(first, 0.012, "seed \(seed): and already within ~1 cm at the impact frame itself")
            XCTAssertGreaterThan(handInBody, -0.005, "seed \(seed): no hand inside the partner's body")
            XCTAssertGreaterThan(eggGap, -0.01, "seed \(seed): the bodies (eggs) do not overlap")
            XCTAssertGreaterThan(skinGapMin, -0.015, "seed \(seed): nor the whole skins (the arms are the contact)")
            XCTAssertTrue(planted, "seed \(seed): feet stay planted through the act")
            XCTAssertLessThan(drift, 0.03, "seed \(seed): no foot slide (the roots stay put through the act)")
        }
    }
}
