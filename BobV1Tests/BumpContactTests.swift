//
//  BumpContactTests.swift
//  The bump (two Jelbies face to face: phase 1 stand-off, phase 2/3 the lean-in + bounce-off, phase 4 the happy hops; BlobSocial+Play.driveBump, ContactStance .bump)
//  measured in the Duo with the contact engine live: skin gap at the touch frames (the approved press is -0.3..-0.6 cm), no overlap beyond it, no feature (ear / wing / tail / spike) inside the partner, feet planted through the touch.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BumpContactTests: XCTestCase {
    struct R { var touchGap: Float = .infinity, eggGap: Float = .infinity, minSkin: Float = .infinity, feat: Float = -1, limb: Float = -1, drift: Float = 0, planted = true, touched = false, pitchPeak: Float = 0, squashMin: Float = 1 }

    static let casts: [(String, [JellyFeature])] = [("Bob+Teddy", [.none, .ears]), ("Bob+Lavender", [.none, .wings]), ("Pip+Bob", [.spines, .none])]
    static let seeds: [(UInt64, [SIMD2<Float>])] = [(51, [SIMD2(-1.5, 0.6), SIMD2(1.35, 0.9)]), (52, [SIMD2(1.5, 0.3), SIMD2(-1.2, 1.1)])]

    override func setUp() {
        super.setUp()
        EmoteFeetTests.reset()
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        FeatureClip.enabled = true; LieClearTuning.enabled = true
    }
    override func tearDown() { FeatureClip.enabled = true; FeatureClip.eggs = []; ContactField.reset(); ContactField.enabled = true; EmoteFeetTests.reset(); super.tearDown() }

    func measure(_ feats: [JellyFeature], seed: UInt64, starts: [SIMD2<Float>]) -> R? {
        ContactField.reset(); FeatureClip.eggs = []
        let d = FeatureClipTests.Duo(positions: starts, features: feats, seed: seed)
        d.live = true
        for _ in 0..<3 { d.tick() }
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        guard a.brain.socialStart(.bump, with: b.brain, a.sim) else { return nil }
        var r = R(); var p2Start: [SIMD2<Float>]?
        var afterImpact = -1
        for f in 0..<(60 * 16) {
            d.tick()
            let ph = a.brain.social?.phase ?? 0
            if ph >= 2 && ph <= 3 {
                if p2Start == nil { p2Start = [a.brain.position, b.brain.position] }
                if a.brain.feet.active || b.brain.feet.active || a.brain.stepLive || b.brain.stepLive || a.brain.gait.isBusy || b.brain.gait.isBusy { r.planted = false }
                r.drift = max(r.drift, simd_distance(a.brain.position, p2Start![0]), simd_distance(b.brain.position, p2Start![1]))
                r.pitchPeak = max(r.pitchPeak, abs(a.brain.socialBook.pitch)); r.squashMin = min(r.squashMin, a.brain.socialBook.squash)
                let S = d.contactSurfaces(), Sb = d.contactSurfacesNoSkin(bodyOnly: true)
                let sg = BruteForceContactMetric.skinGap(S[0], S[1]); r.minSkin = min(r.minSkin, sg)
                if ProcessInfo.processInfo.environment["BUMP_TRACE"] != nil, seed == 51, feats[1] == .ears, f % 2 == 0 { MotionLog.write(String(format: "BUMPTRACE f%d ph%d t%.2f gap %.2f cm pitch %.3f/%.3f squash %.3f imp %d kick %.2f", f, ph, a.brain.social?.phaseT ?? 0, sg * 100, a.brain.socialBook.pitch, b.brain.socialBook.pitch, a.brain.socialBook.squash, (a.brain.social?.impacted ?? false) ? 1 : 0, a.brain.jellyKick)) }
                r.eggGap = min(r.eggGap, BruteForceContactMetric.skinGap(Sb[0], Sb[1]))
                if a.brain.social?.impacted == true { afterImpact += 1 }
                if afterImpact >= 0 && afterImpact <= 12 { r.touchGap = min(r.touchGap, sg); r.touched = true }
                if f % 3 == 0 {
                    FeatureClip.enabled = false
                    let rawF = d.skinAll(), rawL = (0..<2).map { d.limbPoints($0) }
                    FeatureClip.enabled = true
                    let clipF = d.skinAll(), clipL = (0..<2).map { d.limbPoints($0) }
                    for i in 0..<2 {
                        r.feat = max(r.feat, d.penetration(clipF[i], owner: i, raw: rawF[i])); r.limb = max(r.limb, d.penetration(clipL[i], owner: i, raw: rawL[i]))
                    }
                }
            }
            if ph >= 4 { break }
        }
        return r
    }

    func testBumpPressesGentlyFeetPlanted() {
        for (cn, feats) in Self.casts {
            for (seed, starts) in Self.seeds {
                guard let r = measure(feats, seed: seed, starts: starts) else { XCTFail("\(cn) \(seed): bump did not start"); continue }
                MotionLog.write(String(format: "BUMP %@ seed %d: touch gap %.4f, min skin %.4f, egg gap %.4f, feature pen %.4f, limb pen %.4f, drift %.3f, planted %d, pitch peak %.3f, squash min %.3f", cn, Int(seed), r.touchGap, r.minSkin, r.eggGap, r.feat, r.limb, r.drift, r.planted ? 1 : 0, r.pitchPeak, r.squashMin))
                XCTAssertTrue(r.touched, "\(cn) \(seed): the bump touches")
                XCTAssertLessThanOrEqual(r.touchGap, 0.005, "\(cn) \(seed): touch gap <= +0.5 cm")
                XCTAssertGreaterThan(r.minSkin, -0.0075, "\(cn) \(seed): never deeper than the -0.3..-0.6 cm press (deepest single frame, the strike's kick, measured -0.70 cm; before the fix -0.88)")
                XCTAssertGreaterThan(r.eggGap, -0.01, "\(cn) \(seed): eggs do not overlap")
                XCTAssertLessThan(r.feat, 0.005, "\(cn) \(seed): no feature inside the partner")
                XCTAssertLessThan(r.limb, 0.005, "\(cn) \(seed): no limb inside the partner")
                XCTAssertTrue(r.planted, "\(cn) \(seed): feet planted through the bump")
                XCTAssertLessThan(r.drift, 0.03, "\(cn) \(seed): no foot slide")
            }
        }
    }
}
