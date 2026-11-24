//
//  IntegrateBuddySoccerTests.swift
//  integrate-r1: the two wires between best-friend-r1 and soccer-room-r1.
//  (1) a member of a running soccer session counts as "away" for buddy blocks (BondMoment.soccerMember, set by SoccerSession);
//  (2) the soccer director does not recruit a body that holds a buddy flag or is in a block (BlobBrain.inBuddyBlock).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class IntegrateBuddySoccerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BondMoment.blocksAtHome = true; BondMoment.active = nil
        SoccerState.shared.reset(); SoccerEvents.clear(); SoccerEvents.sink = nil; DecorField.shared.clear(); DecorField.shared.bodies = []
        SoccerSession.shared.reset(); MoveMix.soccerNextAt = 0; MoveMix.ballBadSince = -1; SoccerSessionTuning.roomShots = true
    }
    override func tearDown() {
        BondMoment.blocksAtHome = false; BondMoment.active = nil
        SoccerEvents.sink = nil; DecorField.shared.clear(); DecorField.shared.bodies = []; SoccerState.shared.reset(); SoccerSession.shared.reset()
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SoccerSessionTuning.roomShots = false
        super.tearDown()
    }

    private func lab(n: Int, seed: UInt64) -> SocialTests.Lab {
        let aspect: Float = 440.0 / 956.0
        GameCamera.configureRoom(count: max(n, 1), option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect); _ = GameCamera.refreshRoam(aspect: aspect)
        RoomLayout.dynamicBoxes = []
        let l = SocialTests.Lab(n: n, positions: SocialTests.starts, quiet: false, seed: seed)
        SoccerTests.keep.append(l)
        for (i, r) in l.rigs.enumerated() {
            let b = r.brain
            b.sleepEnabled = false; b.anticsEnabled = true; b.watching = true; b.homeRoom = true
            b.idleMood = .happy; b.idleNight = 0; b.idleDeepNight = 0; b.idleMorning = 0
            b.socialBook.cooldown = 6 + Float(i) * 3; b.idleState.cooldown = 8 + Float(i) * 2; b.restTimer = 0.5 + Float(i)
            b.socialBook.bestFriends = [(i + 1) % n]; b.socialBook.close[(i + 1) % n] = FriendTuning.closeMul[3]
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
        }
        return l
    }
    private func run(_ l: SocialTests.Lab, seconds: Float, until: (() -> Bool)? = nil) {
        for _ in 0..<Int(60 * seconds) {
            l.tick(watching: false)
            DecorField.shared.bodies = l.rigs.map { ($0.brain.steerID, $0.brain.position) }; DecorField.shared.tick(dt: 1.0 / 60)
            if let u = until, u() { return }
        }
    }
    private func finish(_ l: SocialTests.Lab) { for r in l.rigs { r.brain.abortScript(r.sim, r.skinner); r.brain.sessRelease() }; DecorField.shared.clear() }

    /// Direction 1: SoccerSession installs the closure itself; a member of a running session is away, a body outside it is not.
    func testASoccerSessionMemberCountsAsAwayForBuddyBlocks() {
        BondMoment.soccerMember = nil
        let l = lab(n: 3, seed: 71)
        run(l, seconds: 1)
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.0, z: 1.0)])
        run(l, seconds: 60, until: { SoccerSession.shared.isActive && !SoccerSession.shared.memberIDs.isEmpty })
        defer { finish(l) }
        XCTAssertNotNil(BondMoment.soccerMember, "the session director installs the hook by itself")
        XCTAssertTrue(SoccerSession.shared.isActive, "a session started")
        let ids = SoccerSession.shared.memberIDs
        for r in l.rigs {
            let isMember = ids.contains(r.brain.steerID)
            XCTAssertEqual(BondMoment.soccerMember?(r.brain.steerID), isMember)
            if isMember { XCTAssertTrue(r.brain.buddyAway, "member \(r.brain.steerID) is away for buddy blocks") }
        }
        SoccerSession.shared.reset()
        XCTAssertEqual(BondMoment.soccerMember?(l.rigs[0].brain.steerID), false, "no running session: nobody is away because of soccer")
    }

    /// Direction 2: a body holding a buddy flag is not eligible for the session, so neither the start nor the late joiners take it.
    func testTheSoccerDirectorSkipsBodiesInABuddyBlock() {
        BondMoment.soccerMember = nil
        let l = lab(n: 3, seed: 72)
        let a = l.rigs[0].brain, b = l.rigs[1].brain, c = l.rigs[2].brain
        for r in l.rigs { r.brain.abortScript(r.sim, r.skinner); r.brain.idleState.kind = nil }
        a.socialBook.bondNextAt = a.variety.now - 1
        _ = a.bondUrge(l.rigs[0].sim)
        XCTAssertTrue(a.inBuddyBlock && b.inBuddyBlock, "the pair is flagged")
        XCTAssertEqual(a.sessBlock(inSession: false), "buddyBlock")
        XCTAssertFalse(a.sessEligible(inSession: false)); XCTAssertFalse(b.sessEligible(inSession: false))
        XCTAssertNil(c.sessBlock(inSession: false), "an unflagged body is still free to play")
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.0, z: 1.0)])
        // (the flags stay for the whole run of this check: members must never include the flagged pair)
        for _ in 0..<(60 * 40) {
            l.tick(watching: false)
            DecorField.shared.bodies = l.rigs.map { ($0.brain.steerID, $0.brain.position) }; DecorField.shared.tick(dt: 1.0 / 60)
            if a.inBuddyBlock || b.inBuddyBlock {
                XCTAssertFalse(SoccerSession.shared.memberIDs.contains(a.steerID) && a.inBuddyBlock, "a flagged body is never a member")
                XCTAssertFalse(SoccerSession.shared.memberIDs.contains(b.steerID) && b.inBuddyBlock, "a flagged body is never a member")
            }
        }
        finish(l)
    }
}
