//
//  CafeRegularsTests.swift
//  cafe-regulars-r1: the café's guests. The visit roll (nobody / one / a pair, the shares over many seeds, never more than five bodies), the pair's table (clear of the player's, in the walkable floor,
//  both aspects), the pair's in-place conversation (holds its spot and its facing for 30 s, takes turns), and who the guests are (never special, never twice).
//

import XCTest
import simd
@testable import BobV1

private struct GuestSplitMix: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}

@MainActor
final class CafeRegularsTests: XCTestCase {
    override func tearDown() {
        RoomLayout.apply(RoomCatalog.home)
        DecorField.shared.set([])
        DayClock.shared.forcedHour = 12
        GameCamera.aspect = 440.0 / 956.0
        DiningLayout.ends = false; DiningLayout.sideX = 1.11; DiningLayout.reachFood = false; DiningLayout.endsYaw = DiningLayout.homeEndsYaw
        super.tearDown()
    }

    func testVisitSharesOverManySeeds() {
        var rng = GuestSplitMix(s: 2026)
        var n = [CafeGuestPlan: Int](), N = 30_000
        for _ in 0..<N { n[CafeGuestPlan.roll(slots: 2, using: &rng), default: 0] += 1 }
        let f = { (p: CafeGuestPlan) in Double(n[p] ?? 0) / Double(N) }
        let pair = f(.pairHere) + f(.pairWalkIn)
        XCTAssertEqual(f(.nobody), 1.0 / 3.0, accuracy: 0.05, "nobody else in about one visit in three")
        XCTAssertEqual(pair, 2.0 / 3.0, accuracy: 0.07, "a pair in about two visits in three")
        XCTAssertEqual(f(.pairHere), f(.pairWalkIn), accuracy: 0.03, "half of the pairs are already there, half walk in")
        XCTAssertGreaterThan(f(.solo), 0.03, "a lone guest in some visits"); XCTAssertLessThan(f(.solo), 0.15)
        print("[caferegulars] shares: nobody \(f(.nobody)) solo \(f(.solo)) pairHere \(f(.pairHere)) pairWalkIn \(f(.pairWalkIn))")
    }

    func testNeverMoreThanFiveBodies() {
        var rng = GuestSplitMix(s: 7)
        for owned in 1...6 {
            for _ in 0..<2000 {
                let slots = CafeTuning.regularCount(owned: owned, want: CafeTuning.maxRegulars)
                let plan = CafeGuestPlan.roll(slots: slots, using: &rng)
                XCTAssertLessThanOrEqual(plan.guestCount, slots)
                XCTAssertLessThanOrEqual(plan.guestCount, 2)
                XCTAssertLessThanOrEqual(owned + plan.guestCount, max(owned, CafeTuning.maxBodies))
            }
        }
        XCTAssertEqual(CafeGuestPlan.roll(slots: 0, using: &rng), .nobody)
        for _ in 0..<500 { XCTAssertNotEqual(CafeGuestPlan.roll(slots: 1, using: &rng), .pairHere); XCTAssertNotEqual(CafeGuestPlan.roll(slots: 1, using: &rng), .pairWalkIn) }
    }

    func testCastIsDistinctOrdinaryAndNeverTheSameTwice() {
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        for _ in 0..<40 {
            let cast = r.care.cafeRegularCast(count: 2)
            XCTAssertEqual(cast.count, 2)
            XCTAssertEqual(Set(cast.map(\.id)).count, cast.count, "never the same guest twice")
            for v in cast { XCTAssertNil(v.species, "special kinds are park-only"); XCTAssertNil(v.mergedInto) }
        }
    }

    // the pair's table, both aspects

    private func openCafe(aspect: Float) -> (DiningJellyTests.Room, GameCare) {
        GameCamera.aspect = aspect
        DayClock.shared.forcedHour = 12
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        r.care.bath.wallet.add(100 - r.care.bath.wallet.count, silent: true)
        for j in r.care.jellies { r.care.needs(for: j.id).set(.hunger, 0.3) }
        r.care.requestCafe()
        for _ in 0..<(8 * 60) { r.tick(); r.care.tickRace(r.actors, dt: 1.0 / 60); r.care.tickCafe(r.actors, dt: 1.0 / 60); r.care.tickDecor(dt: 1.0 / 60); if r.care.cafe.phase == .menu { break } }
        XCTAssertEqual(r.care.cafe.phase, .menu)
        return (r, r.care)
    }

    func testPairTableIsClearAndWalkableInBothAspects() {
        for (name, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(956.0 / 440.0))] {
            let (r, c) = openCafe(aspect: aspect)
            XCTAssertTrue(c.cafeOpenPairTable(floors: r.actors.map(\.floor), landscape: aspect >= 1), name)
            let g = c.cafeBook.guests
            XCTAssertEqual(g.stands.count, 2, name)
            XCTAssertGreaterThan(simd_distance(g.origin, c.cafeBook.origin), 2.2, "\(name): clear of the player's table")
            for s in g.stands {
                for a in r.actors { XCTAssertGreaterThanOrEqual(simd_distance(s, a.floor), GameCare.regularMargin, "\(name): keeps the margin to the player's bodies") }
                for st in c.cafeBook.stands.values { XCTAssertGreaterThanOrEqual(simd_distance(s, st), GameCare.regularMargin, "\(name): keeps the margin to the player's stands") }
                XCTAssertLessThanOrEqual(abs(s.x), 4.0, "\(name): the stand \(s) is inside the floor"); XCTAssertTrue(s.y > -0.6 && s.y < 2.2, "\(name): the stand \(s) is in the open front floor")
            }
            // opposite ends, facing each other
            XCTAssertEqual(g.yaws.count, 2)
            XCTAssertEqual(g.yaws[0], -g.yaws[1], accuracy: 1e-4, "\(name): mirrored")
            XCTAssertGreaterThan(abs(g.stands[0].x - g.stands[1].x), 2.0, "\(name): opposite sides of the table")
            XCTAssertEqual(Set(g.placeOf), [1, 2])
            print("[caferegulars] \(name): table \(g.origin) stands \(g.stands) yaws \(g.yaws) player table \(c.cafeBook.origin)")
        }
    }

    // the in-place conversation (the shared tickCafeChat): five bodies (the rig's last two are the guests)

    func testPairTalksInPlaceFor30Seconds() {
        GameCamera.aspect = 440.0 / 956.0
        let r = DiningJellyTests.Room(count: 3)          // (the rig cannot make more than three bodies: two of them stand in for the guests)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        let c = r.care
        let g = [r.actors[1], r.actors[2]]
        let stands: [SIMD2<Float>] = [SIMD2(-1.6, 1.1), SIMD2(1.0, 1.1)], yaws: [Float] = [DiningLayout.cafeEndsYaw, -DiningLayout.cafeEndsYaw]
        for (k, a) in g.enumerated() { c.rehome(a, at: stands[k]); a.brain?.startTurn(to: yaws[k], sim: a.sim) }
        let seats = g.enumerated().map { CafeChatSeat(id: $1.id, brain: $1.brain!, sim: $1.sim, skinner: $1.skinner, stand: stands[$0], yaw: yaws[$0]) }
        let st = CafeChatState(seed: 11)
        var voices = [Int: Int]()
        var maxMove: [Float] = [0, 0], maxYaw: [Float] = [0, 0]
        let dt: Float = 1.0 / 60
        for step in 0..<(34 * 60) {
            r.tick()
            c.tickCafeChat(seats, state: st, dt: dt) { s, _ in voices[s.id, default: 0] += 1 }
            if step > 4 * 60 {          // (4 s to square up, then 30 s measured)
                for (k, a) in g.enumerated() {
                    guard let b = a.brain else { continue }
                    maxMove[k] = max(maxMove[k], simd_distance(GameCare.floorPos(b, a.sim), stands[k]))
                    maxYaw[k] = max(maxYaw[k], abs(GameCare.wrapAngle(b.yaw + b.twist + b.chat.twist - yaws[k])))
                }
            }
        }
        print("[caferegulars] talk 30 s: move \(maxMove) yaw \(maxYaw) lines \(st.lines) answers \(st.answers) laughs \(st.laughs) corrections \(st.corrections) voices \(voices)")
        for k in 0..<2 {
            XCTAssertLessThan(maxMove[k], 0.05, "guest \(k) holds his spot")
            XCTAssertLessThan(maxYaw[k], 0.15, "guest \(k) holds his facing")
        }
        XCTAssertEqual(Set(voices.keys), Set(g.map(\.id)), "they take turns: both speak")
        XCTAssertGreaterThanOrEqual(st.lines, 4, "a conversation, not a statue")
        XCTAssertEqual(st.corrections, 0, "never walked or turned back")
        XCTAssertGreaterThan(simd_distance(g[0].floor, g[1].floor), 2.0, "faces never close (opposite sides of the table)")
    }

    /// MEASURE (the base code's rule): over 20 visits with three Jelmiko, how many guests the OLD single tables seat (one or two asked for each visit), per aspect.
    func testMeasureOldSingleTablePlacement() {
        for (name, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(956.0 / 440.0))] {
            let (r, c) = openCafe(aspect: aspect)
            let floors = r.actors.map(\.floor)
            var seatable: [SIMD2<Float>] = []
            for t in GameCare.regularTables(landscape: aspect >= 1) {
                let stand = t + SIMD2(0, -0.735 + GameCare.eatCloser)
                let free = simd_distance(t, c.cafeBook.origin) > 2.2 && floors.allSatisfy { simd_distance($0, stand) >= GameCare.regularMargin }
                let nearest = floors.map { simd_distance($0, stand) }.min() ?? 0
                print("[caferegulars] OLD \(name): table \(t) free=\(free) nearest player body \(nearest) (margin \(GameCare.regularMargin)) player table \(c.cafeBook.origin)")
                if free { seatable.append(t) }
            }
            var tally = [0, 0, 0]
            for _ in 0..<20 { let want = Int.random(in: 1...2); tally[min(want, seatable.count)] += 1 }
            print("[caferegulars] OLD \(name): over 20 visits guests seated 0/1/2 = \(tally) (tables usable \(seatable.count))")
        }
    }
}
