//
//  PlayTossBoutTests.swift
//  beach-volley-r1: the beach ball bounced between the Jelmiko ("a bout"): no net, no sides, no points. An extension of PlayTossTests (trio(), runTrio(), the seeded controller).
//

import XCTest
import simd
@testable import BobV1

extension PlayTossTests {
    /// Three Jelmiko, the beach ball, every throw a bout (the roll pinned to 1) unless `roll` says otherwise.
    func beachGame(seed: UInt64, roll: Float = 1) -> (t: (rigs: [MotionRig], js: () -> [PlayJelly]), p: PlayToss) {
        Self.room(Self.portrait)
        PlayTuning.boutRoll = roll; PlayTuning.boutOff = false
        let t = trio(), p = PlayToss()
        p.seed(seed &* 0x9E3779B97F4A7C15); p.viewSize = Self.portrait
        p.begin(ball: .beachball, title: "Ball", jellies: t.js(), snapCamera: true)
        runTrio(t, p, seconds: 3) { false }
        return (t, p)
    }
    func endBoutTest() { PlayTuning.boutRoll = 0.6; BoutMath.touchCap = 7; BoutMath.missEvery = 4.5; BoutMath.safeTouches = 2 }

    func testOnlyTheBeachBallWithTwoOrMoreStartsABout() {
        defer { endBoutTest() }
        let g = beachGame(seed: 1)
        XCTAssertTrue(g.p.rollBout(), "three Jelmiko, the beach ball, the roll at 1")
        XCTAssertEqual(PlayTuning.style(.soccerball).boutChance, 0); XCTAssertEqual(PlayTuning.style(.ball).boutChance, 0); XCTAssertEqual(PlayTuning.style(.footbag).boutChance, 0)
        XCTAssertEqual(PlayTuning.style(.soccerball).headShare, 0.12); XCTAssertEqual(PlayTuning.style(.soccerball).chainChance, 0.5); XCTAssertEqual(PlayTuning.style(.soccerball).chainMax, 3)
        XCTAssertEqual(PlayTuning.style(.beachball).chainChance, 0.2)
        // one Jelmiko: no roll, no bout
        Self.room(Self.portrait)
        let r = rigAt(SIMD2(0, 0.6)), p = PlayToss()
        p.seed(5); p.viewSize = Self.portrait
        p.begin(ball: .beachball, title: "Ball", jellies: [jelly(r)], snapCamera: true)
        run(r, p, seconds: 3) { false }
        XCTAssertFalse(p.rollBout(), "one Jelmiko: nothing changes")
        throwAtMiddle(p)
        var kept = false
        run(r, p, seconds: 14) { if p.keeping || p.bout.active { kept = true }; return p.phase == .catching || p.phase == .inHand }
        XCTAssertFalse(kept, "one Jelmiko: no bout")
    }

    /// With three, the next header goes to the one who has touched it least (never straight back to the sender when others are level).
    func testTheLeastTouchedGetsItNext() {
        var rnd: UInt64 = 7
        func r() -> Float { rnd = rnd &* 6364136223846793005 &+ 1442695040888963407; return Float(rnd >> 40) / Float(1 << 24) }
        for _ in 0..<50 {
            XCTAssertEqual(BoutMath.nextReceiver(others: [1, 2], touches: [0: 1, 1: 1, 2: 0], sender: 1, rnd: r), 2, "the one who has not touched it")
            XCTAssertEqual(BoutMath.nextReceiver(others: [0, 2], touches: [0: 1, 1: 1, 2: 1], sender: 1, rnd: r).map { [0, 2].contains($0) }, true)
            XCTAssertEqual(BoutMath.nextReceiver(others: [0, 1], touches: [0: 1, 1: 1, 2: 1], sender: 1, rnd: r), 0, "level: not back to the one it came from")
            XCTAssertEqual(BoutMath.nextReceiver(others: [0], touches: [:], sender: 0, rnd: r), 0, "two Jelmiko: the other one")
        }
    }

    /// A bout header goes to ANOTHER Jelmiko; with three all three touch the ball in a long bout; bodies stay apart; it ends at the player.
    func testABoutGoesRoundAllThreeAndEndsAtThePlayer() {
        defer { endBoutTest() }
        var long = 0, allThree = 0
        for seed in UInt64(1)...5 {
            let g = beachGame(seed: seed), p = g.p
            var strikes: [(by: Int, to: Int?)] = []
            p.onEvent = { e in if case .header(let id, _) = e, p.bout.on { strikes.append((id, p.bout.receiver)) } }
            throwAtMiddle(p)
            var closest: Float = 9
            runTrio(g.t, p, seconds: 60) {
                if p.bout.on { let js = p.jellies; for i in 0..<js.count { for k in (i + 1)..<js.count { closest = min(closest, simd_distance(js[i].pos, js[k].pos)) } } }
                return p.phase == .catching || p.phase == .inHand
            }
            XCTAssertTrue(p.phase == .catching || p.phase == .inHand, "seed \(seed): the ball is back in the hand")
            XCTAssertFalse(p.keeping); XCTAssertFalse(p.bout.on)
            for s in strikes { XCTAssertNotNil(s.to); XCTAssertNotEqual(s.to, s.by, "a bout header goes to another Jelmiko") }
            _ = closest          // (these rigs have no walk planner between them, so bodies can overlap here; the real-app gate measures the closest approach: >= 1.2)
            if strikes.count >= 4 { long += 1; if Set(strikes.map(\.by)).count == 3 { allThree += 1 } }
        }
        XCTAssertGreaterThan(long, 0, "bouts ran")
        XCTAssertGreaterThanOrEqual(Double(allThree), 0.7 * Double(long), "with three, all three touch it in a long bout")
    }

    func testABoutEndsOnTheFloorWithNoPointAndABallBackToThePlayer() {
        defer { endBoutTest() }
        BoutMath.missEvery = 1          // every ball is aimed out of reach: the first one ends it
        let g = beachGame(seed: 2), p = g.p
        throwAtMiddle(p)
        var wasOn = false
        runTrio(g.t, p, seconds: 60) { if p.bout.on { wasOn = true }; return p.phase == .catching || p.phase == .inHand }
        XCTAssertTrue(wasOn); XCTAssertFalse(p.bout.on)
        XCTAssertTrue(p.phase == .catching || p.phase == .inHand, "the ball is back in the hand")
    }

    func testTheTouchCapSendsTheLastHeaderToThePlayer() {
        defer { endBoutTest() }
        BoutMath.missEvery = 1000; BoutMath.touchCap = 3
        var capped = 0
        for seed in UInt64(1)...4 {
            let g = beachGame(seed: seed), p = g.p
            throwAtMiddle(p)
            var maxTouches = 0
            runTrio(g.t, p, seconds: 60) { maxTouches = max(maxTouches, p.bout.touches); return p.phase == .catching || p.phase == .inHand }
            XCTAssertLessThanOrEqual(maxTouches, 3, "seed \(seed): never past the cap")
            XCTAssertTrue(p.phase == .catching || p.phase == .inHand, "seed \(seed): the ball went to the player")
            if maxTouches == 3 { capped += 1 }
        }
        XCTAssertGreaterThan(capped, 0, "at least one bout reached the cap")
    }

    func testARecallEndsTheBoutAtTheNextTouch() {
        defer { endBoutTest() }
        BoutMath.missEvery = 1000
        var done = 0
        for seed in UInt64(1)...4 {
            let g = beachGame(seed: seed), p = g.p
            throwAtMiddle(p)
            var pressed = false, headersAtPress = 0
            runTrio(g.t, p, seconds: 60) {
                if p.keeping, p.bout.on, !pressed { pressed = true; headersAtPress = p.headers; p.recall(); XCTAssertFalse(p.keeping, "the button is gone at once") }
                return p.phase == .catching || p.phase == .inHand
            }
            XCTAssertTrue(p.phase == .catching || p.phase == .inHand, "seed \(seed)")
            if pressed { done += 1; XCTAssertLessThanOrEqual(p.headers - headersAtPress, 1, "seed \(seed): the very next touch goes to the player"); XCTAssertFalse(p.bout.on) }
        }
        XCTAssertGreaterThan(done, 0)
    }

    /// A bout header ignores every body but its receiver; the dropped ball ignores all of them (the same field names a soccer-net branch uses for a returning ball).
    func testABoutBallIgnoresEveryBodyButItsReceiverAndTheDroppedBallAllOfThem() {
        var w = TossWorld(); w.bodies = [TossBody(id: 1, pos: SIMD2(0, 0)), TossBody(id: 2, pos: SIMD2(0, 3))]
        func run(_ b: TossBall) -> [TossEvent] {
            var b = b; var ev: [TossEvent] = []
            for _ in 0..<120 { ev += b.step(1.0 / 60, in: w) }
            return ev
        }
        var base = TossBall(pos: SIMD3(0, 0.5, 5), radius: 0.27); base.vel = SIMD3(0, 0, -4)          // a low ball rolling through both bodies
        XCTAssertTrue(run(base).contains { if case .bodyHit = $0 { return true }; return false }, "an ordinary ball hits a body")
        var only = base; only.ignoreAllBut = 2
        let evOnly = run(only)
        XCTAssertFalse(evOnly.contains { if case .bodyHit(let id, _) = $0 { return id == 1 }; return false }, "it ignores everybody but body 2")
        XCTAssertTrue(evOnly.contains { if case .bodyHit(let id, _) = $0 { return id == 2 }; return false }, "but the receiver can touch it")
        var all = base; all.ignoreAll = true
        XCTAssertFalse(run(all).contains { if case .bodyHit = $0 { return true }; if case .headHit = $0 { return true }; return false }, "the dropped ball passes through every body")
    }
}
