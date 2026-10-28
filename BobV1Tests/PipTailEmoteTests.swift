//
//  PipTailEmoteTests.swift
//  Pip's tail antics (BlobBrain+TailPlay.swift) belong to Pip only: the pick weight is 0 for every other character, an explicit start is refused, and the
//  emotes run to the end on Pip and leave the tail at rest.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PipTailEmoteTests: XCTestCase {
    private func lab(_ feature: JellyFeature) -> SocialTests.Lab {
        let l = SocialTests.Lab(n: 1, positions: [SIMD2(0.4, 0.6)], quiet: true, seed: 5)
        SocialTests.keep.append(l)
        let r = l.rigs[0]
        r.brain.feature = feature; r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = feature == .spines; r.brain.skinnerRef = r.skinner
        r.brain.autonomy = false
        for _ in 0..<60 { l.tick(watching: false) }
        return l
    }

    func testTailKindsOnlyForPip() {
        let kinds: [IdleKind] = [.tail, .tailThump, .tailHug]
        for f in [JellyFeature.none, .daisy, .wings] {
            let l = lab(f), b = l.rigs[0].brain
            for k in kinds {
                XCTAssertEqual(b.varietyScale(k), 0, "\(f) must never pick \(k)")
                if k != .tail { b.idleForced = true; XCTAssertFalse(b.idleStart(k, l.rigs[0].sim), "\(f) cannot start \(k)"); XCTAssertNil(b.idleState.kind) }
            }
        }
        let p = lab(.spines), b = p.rigs[0].brain
        for k in kinds { XCTAssertGreaterThan(b.varietyScale(k), 0, "Pip can pick \(k)") }
    }

    func testPersonalityTables() {
        XCTAssertFalse(VarietyTuning.personality[.wings]!.idle.contains { $0.0.contains(.tail) }, "Lavender lost the tail boost")
        XCTAssertTrue(VarietyTuning.personality[.spines]!.idle.contains { $0.0.contains(.tail) && $0.0.contains(.tailThump) }, "Pip has it")
    }

    func testEmotesRunToTheEnd() {
        for k in [IdleKind.tailThump, .tailHug] {
            let l = lab(.spines), r = l.rigs[0]
            r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(k, r.sim), "\(k) starts on Pip")
            var t = 0
            while r.brain.idleState.kind != nil && t < 60 * 12 { l.tick(watching: false); t += 1 }
            XCTAssertNil(r.brain.idleState.kind, "\(k) finished")
            for _ in 0..<90 { l.tick(watching: false) }
            XCTAssertEqual(r.brain.tailPlay.played[k], 1)
            XCTAssertLessThan(abs(r.brain.tailPlay.lift) + abs(r.brain.tailPlay.curl), 1, "\(k): the tail is back at rest")
        }
    }
}
