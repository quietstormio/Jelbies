//
//  WelcomePartyTests.swift
//  The bought Jelmiko's welcome party (GameCare+Newcomer.swift + Park/GuestParty.swift, `begin(cheer: true)`): hug, then a group cheer, then the ring (or circle) dance, then
//  the finale hops; with one other at home the pair hug (swayHug / spinHug) and the hops. Cancelled by anything the player does: nobody is left in a script.
//  The Lab is the stage (SocialTests.Lab), the last rig is the newcomer.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WelcomePartyTests: XCTestCase {
    override func setUp() { super.setUp(); GroupEmoteFeetTests.reset() }
    override func tearDown() { GroupEmoteFeetTests.reset(); super.tearDown() }

    struct Seq { var order: [SocialKind] = [], finished = false, allFree = false, seconds: Float = 0, cheerCrew = 0, hops: [Int] = [] }

    private func lab(_ n: Int, seed: UInt64 = 31) -> SocialTests.Lab {
        _ = OnePieceInvariantTests.configured
        let l = SocialTests.Lab(n: n, positions: n <= 3 ? Array(SocialTests.starts.prefix(n)) : Array(GroupSocialTests.five.prefix(n)), seed: seed)
        for r in l.rigs { r.brain.anticsEnabled = true; r.brain.autonomy = true }
        return l
    }

    private func note(_ order: inout [SocialKind], _ brains: [BlobBrain]) {
        if let k = brains.compactMap({ $0.social?.kind }).first, order.last != k { order.append(k) }
    }

    /// 2+ others: the hug, then GuestParty with the cheer stage.
    private func runGroup(n: Int) -> Seq {
        let l = lab(n)
        let brains = l.rigs.map(\.brain), sims = l.rigs.map(\.sim)
        var r = Seq()
        XCTAssertTrue(brains[n - 1].socialStartGroup(.groupHug, with: Array(brains.dropLast()), sims[n - 1]), "the newcomer starts the hug")
        var party = GuestParty(); party.begin(cheer: true)
        var frame = 0
        while frame < 60 * 90 {
            l.tick(watching: false)
            party.step(brains: brains, sims: sims, dt: 1.0 / 60) { _, _ in }
            note(&r.order, brains)
            if let s = brains.compactMap({ $0.social }).first(where: { $0.kind == .groupCheer }) { r.cheerCrew = max(r.cheerCrew, s.crewIDs.count) }
            frame += 1
            if party.stage == .done, l.rigs.allSatisfy({ $0.brain.fxFree && $0.brain.social == nil }) { break }
        }
        r.finished = party.stage == .done; r.seconds = Float(frame) / 60; r.hops = party.hops
        r.allFree = l.rigs.allSatisfy { $0.brain.fxFree && $0.brain.social == nil && !$0.brain.commanded && !$0.brain.held }
        return r
    }

    func testPartyWithTwoOthers_hugCheerRingDanceThenFree() {
        let r = runGroup(n: 3)
        XCTAssertEqual(r.order, [.groupHug, .groupCheer, .ringDance], "hug, cheer, ring dance in that order (saw \(r.order))")
        XCTAssertEqual(r.cheerCrew, 3, "the newcomer is in the cheer")
        XCTAssertTrue(r.finished); XCTAssertTrue(r.allFree, "everyone is free at the end")
        for h in r.hops { XCTAssertGreaterThanOrEqual(h, 2) }
        MotionLog.write(String(format: "WELCOMEPARTY x3 %@ | %.1f s", r.order.map(\.rawValue).description, r.seconds))
    }

    func testPartyWithThreeOthers_circleDance() {
        let r = runGroup(n: 4)
        XCTAssertEqual(r.order, [.groupHug, .groupCheer, .circleDance], "saw \(r.order)")
        XCTAssertTrue(r.finished); XCTAssertTrue(r.allFree)
    }

    /// 1 other: a pair body hug (the welcome's second round), then the finale's happy hops together.
    func testPartyWithOneOther_pairHugThenHops() {
        XCTAssertEqual(GameCare.newcomerKinds(place: 0, round2: true, avoiding: .swayHug).first, .spinHug)
        XCTAssertEqual(GameCare.newcomerKinds(place: 0, round2: true, avoiding: .spinHug).first, .swayHug)
        XCTAssertEqual(GameCare.newcomerKinds(place: 0, round2: true, avoiding: .shyWave).first, .swayHug)
        for hug in [SocialKind.swayHug, .spinHug] {
            GroupEmoteFeetTests.reset()
            let l = lab(2)
            let brains = l.rigs.map(\.brain), sims = l.rigs.map(\.sim)
            var order: [SocialKind] = []
            var started = false
            for _ in 0..<(60 * 4) { l.tick(watching: false); if !started { started = brains[0].socialStart(hug, with: brains[1], sims[0]) } else { break } }
            XCTAssertTrue(started, "\(hug) starts with one other")
            var party = GuestParty(); var frame = 0, finale = false
            while frame < 60 * 40 {
                l.tick(watching: false); note(&order, brains)
                if !finale, !l.anySocial, frame > 30 { party.begin(at: .finale, cheer: true); finale = true }
                if finale { party.step(brains: brains, sims: sims, dt: 1.0 / 60) { _, _ in } }
                frame += 1
                if finale, party.stage == .done, l.rigs.allSatisfy({ $0.brain.fxFree && $0.brain.social == nil }) { break }
            }
            XCTAssertEqual(order.first, hug, "the pair hug ran (saw \(order))")
            XCTAssertEqual(party.stage, .done)
            for h in party.hops { XCTAssertGreaterThanOrEqual(h, 2, "both hop together") }
            XCTAssertTrue(l.rigs.allSatisfy { $0.brain.fxFree && $0.brain.social == nil && !$0.brain.held }, "everyone free")
        }
    }

    /// The cheer stage is opt-in: the friend's party (default) never runs one.
    func testFriendsPartyUnchanged_noCheer() {
        let l = lab(3)
        let brains = l.rigs.map(\.brain), sims = l.rigs.map(\.sim)
        XCTAssertTrue(brains[0].socialStartGroup(.groupHug, with: Array(brains.dropFirst()), sims[0]))
        var party = GuestParty(); party.begin()
        var order: [SocialKind] = []
        for _ in 0..<(60 * 60) {
            l.tick(watching: false); party.step(brains: brains, sims: sims, dt: 1.0 / 60) { _, _ in }; note(&order, brains)
            if party.stage == .done { break }
        }
        XCTAssertFalse(order.contains(.groupCheer)); XCTAssertEqual(order, [.groupHug, .ringDance])
    }

    /// Cancelled mid-hug / mid-cheer / mid-dance the way `endNewcomerWelcome(interrupted:)` does it: nobody is scripted afterwards.
    func testCancelAtEveryStageLeavesNoOneScripted() {
        for cutAt: Float in [3, 9, 13, 20, 26] {
            GroupEmoteFeetTests.reset()
            let l = lab(3)
            let brains = l.rigs.map(\.brain), sims = l.rigs.map(\.sim)
            XCTAssertTrue(brains[2].socialStartGroup(.groupHug, with: [brains[0], brains[1]], sims[2]))
            var party = GuestParty(); party.begin(cheer: true)
            for _ in 0..<Int(cutAt * 60) { l.tick(watching: false); party.step(brains: brains, sims: sims, dt: 1.0 / 60) { _, _ in } }
            party.cancel()
            for b in brains where b.social != nil { b.stop() }
            for b in brains { b.autonomy = false }          // (so the check sees only what the cancel left behind, not a fresh idle or session of their own)
            XCTAssertFalse(party.active, "cut at \(cutAt) s: the party is off")
            for _ in 0..<(60 * 12) { l.tick(watching: false) }
            for (i, r) in l.rigs.enumerated() {
                XCTAssertNil(r.brain.social, "cut at \(cutAt) s: rig \(i) has no session")
                XCTAssertTrue(r.brain.fxFree, "cut at \(cutAt) s: rig \(i) is free")
                XCTAssertFalse(r.brain.socialBook.hold, "cut at \(cutAt) s: rig \(i) is not held by a script")
                XCTAssertFalse(r.brain.commanded)
            }
        }
    }
}
