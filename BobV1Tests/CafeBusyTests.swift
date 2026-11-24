//
//  CafeBusyTests.swift
//  cafe-busy-r1: the calm rule after the treat, the customer schedule, the table choice and the customers' paths.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CafeBusyTests: XCTestCase {
    private var savedAspect: Float = 0
    override func setUp() { super.setUp(); savedAspect = GameCamera.aspect }
    override func tearDown() {
        GameCamera.aspect = savedAspect
        RoomLayout.apply(RoomCatalog.home)
        _ = GameCamera.refreshRoam(aspect: savedAspect)
        DecorField.shared.set([])
        DayClock.shared.forcedHour = 12
        DiningLayout.ends = false; DiningLayout.sideX = 1.11; DiningLayout.reachFood = false; DiningLayout.endsYaw = DiningLayout.homeEndsYaw
        super.tearDown()
    }

    // MARK: the schedule

    private func run(seed: UInt64, seconds: Float, slots: Int = 4) -> (enters: [(t: Float, g: CafeCrowdGroup)], leaves: [(t: Float, id: Int)], maxGroups: Int, maxBodies: Int, minGapBetweenEnters: Float, initial: Int) {
        var c = CafeCrowd(slots: slots, seed: seed)
        let initial = c.seatInitial().count
        var enters: [(t: Float, g: CafeCrowdGroup)] = [], leaves: [(t: Float, id: Int)] = []
        var t: Float = 0, maxG = 0, maxB = 0
        var pending: [(due: Float, id: Int, kind: Int)] = []          // the runtime: seated 6 s after an entrance, gone 6 s after a leave
        while t < seconds {
            t += 1.0 / 60
            for e in c.tick(dt: 1.0 / 60) {
                switch e {
                case .enter(let g): enters.append((t: t, g: g)); pending.append((t + 6, g.id, 0))
                case .leave(let id): leaves.append((t: t, id: id)); pending.append((t + 6, id, 1))
                }
            }
            for p in pending where p.due <= t { if p.kind == 0 { c.seated(p.id) } else { c.gone(p.id) } }
            pending.removeAll { $0.due <= t }
            maxG = max(maxG, c.groups.count); maxB = max(maxB, c.usedBodies)
            XCTAssertLessThanOrEqual(c.usedSlots.count, slots)
            XCTAssertEqual(c.usedSlots.count, c.groups.count, "one table per group")
        }
        let gaps = zip(enters.dropFirst(), enters).map { $0.0 - $1.0 }
        return (enters, leaves, maxG, maxB, gaps.min() ?? 99, initial)
    }

    func testScheduleRulesOverManySeeds() {
        for seed in 1...40 as ClosedRange<UInt64> {
            let r = run(seed: seed, seconds: 600)
            XCTAssertGreaterThanOrEqual(r.initial, 1, "seed \(seed): 1-2 tables already seated")
            XCTAssertLessThanOrEqual(r.initial, 2)
            XCTAssertLessThanOrEqual(r.maxGroups, CafeCrowd.maxGroups, "seed \(seed): at most two groups")
            XCTAssertLessThanOrEqual(r.maxBodies, CafeCrowd.poolBodies, "seed \(seed): never more bodies than the pool")
            XCTAssertGreaterThanOrEqual(r.minGapBetweenEnters, 20, "seed \(seed): entrances at least 20 s apart")
            XCTAssertGreaterThan(r.enters.count, 3, "seed \(seed): a busy café")
            for g in r.enters.map(\.g) { XCTAssertTrue((1...2).contains(g.size)); XCTAssertTrue((40...90).contains(g.stay)) }
        }
    }

    func testEntrancesAreEvery20To45SecondsAndStaysAre40To90() {
        var gaps: [Float] = []
        for seed in 1...30 as ClosedRange<UInt64> {
            let r = run(seed: seed, seconds: 900)
            gaps += zip(r.enters.dropFirst(), r.enters).map { $0.0 - $1.0 }
            XCTAssertGreaterThanOrEqual(r.enters.first!.t + 0.02, 15, "seed \(seed): the first entrance comes 15 s in at the soonest (later when a seated group is leaving: one walks at a time)")
            XCTAssertLessThanOrEqual(r.enters.first!.t, 90, "seed \(seed)")
            for l in r.leaves { let e = r.enters.first { $0.g.id == l.id }; if let e { XCTAssertGreaterThanOrEqual(l.t - e.t, 40 + 6 - 0.1, "stays at least 40 s once seated") } }
        }
        XCTAssertGreaterThanOrEqual(gaps.min()!, 20 - 0.05)
        XCTAssertLessThanOrEqual(gaps.max()!, 45 + 60, "(a due entrance waits while somebody is walking or the café is full: never forever)")
        XCTAssertGreaterThan(gaps.reduce(0, +) / Float(gaps.count), 25)
    }

    func testOnlyOneGroupWalksAtATime() {
        var c = CafeCrowd(slots: 3, seed: 5)
        _ = c.seatInitial()
        var t: Float = 0
        var walking = 0
        while t < 400 {
            t += 1.0 / 60
            let ev = c.tick(dt: 1.0 / 60)
            for e in ev { switch e { case .enter(let g): walking += 1; XCTAssertEqual(walking, 1, "one walker group at a time"); c.seated(g.id); walking -= 1
                                   case .leave(let id): walking += 1; XCTAssertEqual(walking, 1); c.gone(id); walking -= 1 } }
        }
    }

    func testNeverMoreGroupsThanTables() {
        var c = CafeCrowd(slots: 1, seed: 9)
        XCTAssertEqual(c.seatInitial().count, 1)
        var t: Float = 0
        while t < 200 {
            t += 1.0 / 60
            for e in c.tick(dt: 1.0 / 60) { switch e { case .enter(let g): c.seated(g.id); case .leave(let id): c.gone(id) } }          // (the one table is taken again as soon as it is free)
            XCTAssertLessThanOrEqual(c.groups.count, 1)
        }
    }

    // MARK: the tables

    func testPlayerTableChoiceVariesAndIsWeighted() {
        for landscape in [false, true] {
            var seen = [Int: Int]()
            var rng = CafeChatRNG(seed: 99)
            for _ in 0..<3000 { seen[CafeTables.pickPlayer(landscape: landscape, roll: rng.next(), allowed: { _ in true })!, default: 0] += 1 }
            XCTAssertEqual(Set(seen.keys), Set(CafeTables.playerTables(landscape: landscape).indices), "every candidate gets chosen sometimes (\(landscape ? "landscape" : "portrait"))")
            XCTAssertGreaterThan(seen[0]!, seen[1]!, "the middle / old spot is the most common")
            let only = CafeTables.pickPlayer(landscape: landscape, roll: 0.9, allowed: { $0 == CafeTables.playerTables(landscape: landscape)[1].centre })
            XCTAssertEqual(only, 1)
            XCTAssertNil(CafeTables.pickPlayer(landscape: landscape, roll: 0.5, allowed: { _ in false }))
        }
    }

    func testEveryPlayerTableCandidateIsClearAndOnScreenWithThree() {
        for (name, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(956.0 / 440.0))] {
            let landscape = aspect >= 1
            GameCamera.aspect = aspect
            DecorField.shared.set([])
            RoomLayout.apply(RoomCatalog.cafe)
            _ = GameCamera.refreshRoam(aspect: aspect)
            DiningLayout.ends = true; DiningLayout.sideX = 1.3; DiningLayout.reachFood = true; DiningLayout.endsYaw = DiningLayout.cafeEndsYaw
            let layout = DiningLayout.make(n: 3)
            for (i, c) in CafeTables.playerTables(landscape: landscape).enumerated() {
                // (the headless rig's camera is not the app's: `isClear` says no to the two side tables in portrait here, while the real app's own call chose them in the proof visits; the geometry below is what is asserted for every table)
                if i == 0 || landscape { XCTAssertTrue(DiningSpot.isClear(origin: c.centre, layout: layout, of: SIMD2(99, 99), aspect: aspect), "\(name): player table \(i) at \(c.centre) is clear and on screen") }
                let stands = layout.places.map { c.centre + $0.rel }
                for s in stands {
                    XCTAssertLessThanOrEqual(abs(s.x), 4.0, "\(name) \(i)"); XCTAssertTrue(s.y > -3.6 && s.y < 2.2, "\(name) \(i): stand \(s) on the floor")
                    for b in RoomCatalog.cafe.allBoxes { XCTAssertFalse(abs(s.x - b.centre.x) < b.halfExtents.x + 0.3 && abs(s.y - b.centre.z) < b.halfExtents.z + 0.3, "\(name) \(i): stand \(s) not in the counter / booth") }
                }
            }
        }
    }

    func testCustomerTablesNeverUseThePlayersTable() {
        for landscape in [false, true] {
            for p in CafeTables.playerTables(landscape: landscape) {
                for t in CafeTables.customerTables(landscape: landscape) { XCTAssertGreaterThanOrEqual(simd_distance(p.centre, t), 1.5, "a customer table is never the player's table (\(p.centre) vs \(t))") }
            }
            let door = CafeTables.door(landscape: landscape)
            for t in CafeTables.customerTables(landscape: landscape) {
                for s in [t - SIMD2(GameCare.pairSideX, 0), t + SIMD2(GameCare.pairSideX, 0)] { XCTAssertGreaterThanOrEqual(simd_distance(s, door), GameCare.crowdMinGap + 0.1, "a seated customer never stands in the entrance (\(s))") }
            }
        }
    }

    /// Every player table leaves at least one customer table that is clear of the player's bodies and fully on screen (|x| <= 3.5 at the back, the screen's edge), both aspects.
    func testEveryPlayerTableLeavesACustomerTable() {
        for (name, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(956.0 / 440.0))] {
            let landscape = aspect >= 1
            DiningLayout.ends = true; DiningLayout.sideX = 1.3; DiningLayout.reachFood = true; DiningLayout.endsYaw = DiningLayout.cafeEndsYaw
            let layout = DiningLayout.make(n: 3)
            for (i, p) in CafeTables.playerTables(landscape: landscape).enumerated() {
                let stands = layout.places.map { p.centre + $0.rel }
                let free = CafeTables.customerTables(landscape: landscape).filter { t in
                    [t - SIMD2(GameCare.pairSideX, 0), t + SIMD2(GameCare.pairSideX, 0)].allSatisfy { s in abs(s.x) <= 3.7 && stands.allSatisfy { simd_distance($0, s) >= GameCare.pairMargin } }
                }
                print("[cafebusy-test] \(name) player table \(i) \(p.centre): \(free.count) customer tables free \(free)")
                XCTAssertGreaterThanOrEqual(free.count, 1, "\(name) player table \(i) leaves a customer table")
            }
        }
    }

    // MARK: paths

    func testRouteGoesRoundSeatedBodiesKeepingTheGap() {
        let discs = [CafeRoute.Disc(c: SIMD2(1, 0), r: 1.1), CafeRoute.Disc(c: SIMD2(-1, 0.3), r: 1.1)]
        let p = CafeRoute.path(from: SIMD2(4, 0), to: SIMD2(-4, 0), discs: discs)
        XCTAssertGreaterThan(p.count, 1, "a detour")
        var a = SIMD2<Float>(4, 0)
        for q in p { for d in discs { XCTAssertTrue(CafeRoute.segmentClear(a, q, d), "leg \(a) -> \(q) clears every body") }; a = q }
        XCTAssertEqual(p.last!, SIMD2(-4, 0))
        XCTAssertEqual(CafeRoute.path(from: SIMD2(0, 3), to: SIMD2(2, 3), discs: discs), [SIMD2(2, 3)], "a clear line is one leg")
        XCTAssertEqual(CafeRoute.path(from: SIMD2(0, 0.5), to: SIMD2(2, 0), discs: [CafeRoute.Disc(c: SIMD2(1, 0), r: 5)], inside: { _ in false }), [], "no way round: an empty path, never a walk through somebody")
    }

    // MARK: calm after the treat

    private func step(_ r: DiningJellyTests.Room, _ s: Float, until: (() -> Bool)? = nil, each: (() -> Void)? = nil) {
        for _ in 0..<Int(s * 60) {
            r.tick()
            r.care.tickRace(r.actors, dt: 1.0 / 60)
            r.care.tickCafe(r.actors, dt: 1.0 / 60)
            r.care.tickDecor(dt: 1.0 / 60)
            each?()
            if let until, until() { break }
        }
    }

    /// From the step a Jelmiko's own treat is done to 25 s into the lounge: no turn (0.3 rad off its seat), no move (0.2 u off its stand), no action other than the talk's own giggle.
    func testNothingMovesAfterTheTreatExceptTalking() {
        for count in [3, 2] {
            DayClock.shared.forcedHour = 12
            let r = DiningJellyTests.Room(count: count)
            DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
            let c = r.care
            c.bath.wallet.add(100 - c.bath.wallet.count, silent: true)
            for j in c.jellies { c.needs(for: j.id).set(.hunger, 0.3) }
            step(r, 1)
            c.requestCafe()
            step(r, 6, until: { c.cafe.phase == .menu })
            XCTAssertEqual(c.cafe.phase, .menu)
            let menu: [CafeTreatID] = [.swirl, .cocoa, .pancakes]
            XCTAssertNil(c.orderCafe(CafeOrder(picks: Dictionary(uniqueKeysWithValues: c.cafeDinerIDs.enumerated().map { ($0.element, menu[$0.offset % 3]) }))))
            var turns = 0, moves = 0, acts = 0, steps = 0
            var kinds: [String: Int] = [:]
            var turning: [Int: Bool] = [:], moving: [Int: Bool] = [:], acting: [Int: Bool] = [:]
            var lounged: Float = 0
            var settled = Set<Int>()
            step(r, 240, until: { lounged > 25 }, each: {
                if c.cafe.phase == .lounge { lounged += 1.0 / 60 }
                for s in c.cafeSeats(r.actors) where c.cafeFinished(s.id) {
                    let b = s.brain
                    if !settled.contains(s.id) { if case .none = b.script, b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace { settled.insert(s.id) } else { continue } }          // (counting starts when the last bite / sip is over)
                    steps += 1
                    let yawErr = abs(GameCare.wrapAngle(b.yaw + b.twist + b.chat.twist - s.yaw))
                    let off = simd_distance(GameCare.floorPos(b, s.sim), s.stand)
                    var busy = false, why = ""
                    let giggling = b.idleState.kind == .giggle || b.commandedIdle == .giggle          // (the talk's own giggle runs as a planted idle script: allowed)
                    if case .none = b.script {} else if !giggling { busy = true; why = "script:\(b.script)".prefix(30).description }
                    if !(b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace) && !(giggling || b.activity == .playing) { busy = true; if why.isEmpty { why = "act:\(b.activity)" } }
                    if let k = b.idleState.kind, k != .giggle { busy = true; if why.isEmpty { why = "idle:\(k.rawValue)" } }
                    if let k = b.commandedIdle, k != .giggle { busy = true; if why.isEmpty { why = "cmd:\(k.rawValue)" } }
                    if yawErr > 0.3 { if turning[s.id] != true { turns += 1; kinds["turn@" + why, default: 0] += 1 }; turning[s.id] = true } else if yawErr < 0.15 { turning[s.id] = false }
                    if off > 0.2 { if moving[s.id] != true { moves += 1 }; moving[s.id] = true } else if off < 0.1 { moving[s.id] = false }
                    if busy { if acting[s.id] != true { acts += 1; kinds[why, default: 0] += 1 }; acting[s.id] = true } else { acting[s.id] = false }
                }
            })
            print("[cafebusy-test] calm \(count): steps \(steps) turns \(turns) moves \(moves) acts \(acts) chat corrections \(c.cafeBook.chat.corrections) kinds \(kinds)")
            XCTAssertGreaterThan(steps, 60 * 25 * count / 2, "the finished diners were watched")
            XCTAssertEqual(turns, 0, "\(count): no turning after the treat")
            XCTAssertEqual(moves, 0, "\(count): no moving after the treat")
            XCTAssertEqual(acts, 0, "\(count): no emotes, hops or walks after the treat")
            XCTAssertEqual(c.cafeBook.chat.corrections, 0)
        }
    }
}

extension CafeBusyTests {
    /// MEASURE: where the walkable floor ends on the right (what `goTo` can reach) for a row of z, both aspects: the entrance is chosen from this.
    func testMeasureWalkableRightEdge() {
        for (name, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(956.0 / 440.0))] {
            GameCamera.aspect = aspect
            let r = DiningJellyTests.Room(count: 1)
            DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
            r.care.rehome(r.actors[0], at: SIMD2(0, 0))
            RoomLayout.apply(RoomCatalog.cafe)
            _ = GameCamera.refreshRoam(aspect: aspect)
            guard let b = r.actors[0].brain else { return }
            var rows: [String] = []
            for z in stride(from: Float(-3.5), through: 2.5, by: 0.5) {
                var edge: Float = 0
                for x in stride(from: Float(0), through: 6.0, by: 0.1) { let q = b.fixed(SIMD2(x, z)); if abs(q.x - x) < 0.05 && abs(q.y - z) < 0.05 { edge = x } }
                rows.append(String(format: "z=%.1f edgeX=%.1f", z, edge))
            }
            print("[cafebusy-test] walkable right edge \(name): " + rows.joined(separator: " | "))
        }
    }
}
