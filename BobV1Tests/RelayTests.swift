//
//  RelayTests.swift
//  The Jelly Circuit relay: legs split by arc length, the handoff order, the prizes, the rival teams finishing, Park friends filling the legs, the
//  blocker, and (with real bodies) that nobody overlaps at a handoff and the trip ends clean.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RelayTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func leg(_ n: String, _ w: Float, _ start: Float, ai: Bool = false) -> RelayLeg { RelayLeg(name: n, stats: RacerStats(waddle: w, focus: 1), ai: ai, startDist: start) }

    private func plan(course: RaceCourse = .puddle, waddles: [[Float]] = [[0.9, 0.9, 0.9], [0.5, 0.5, 0.5], [0.3, 0.3, 0.3]], friendLegs: Set<Int> = []) -> RelayPlan {
        let st = RelayTuning.legs(length: course.length).starts
        let teams = waddles.enumerated().map { t, ws in ws.enumerated().map { j, w in leg("T\(t)L\(j)", w, st[j], ai: t == 0 && friendLegs.contains(j)) } }
        return RelayPlan(teams: teams, teamNames: ["A", "B", "C"], ownedIDs: [0, 1, 2], friendIDs: [], rivalVisitorIDs: [], course: course)
    }

    /// Runs the headless relay to its results; returns the handoff events in order.
    private func run(_ p: RelayPlan, seed: UInt64 = 4, playerRate: Float = 7) -> (sim: RaceSim, handoffs: [(t: Int, leg: Int, at: Float)]) {
        var sim = p.makeSim(seed: seed)
        var hand: [(Int, Int, Float)] = []
        var tapT: Float = 0, foot = 0
        let dt: Float = 1.0 / 60
        for _ in 0..<(120 * 60) where sim.phase != .results {
            tapT += dt
            while tapT >= 1 / playerRate { tapT -= 1 / playerRate; sim.playerTap(foot: foot); foot = 1 - foot }
            sim.tick(dt: dt)
            for e in sim.takeEvents() { if case .handoff(let t, let l) = e { hand.append((t, l, sim.clock)) } }
        }
        return (sim, hand.map { (t: $0.0, leg: $0.1, at: $0.2) })
    }

    func testLegsSplitTheCourseIntoThreeEqualRunsWithABoxBetween() {
        for c in [RaceCourse.puddle, .ripple, .splash, .wave, .tsunami] {
            let g = RelayTuning.legs(length: c.length)
            let runs = zip(g.starts, g.ends).map { $1 - $0 }
            XCTAssertEqual(runs[0], runs[1], accuracy: 1e-4); XCTAssertEqual(runs[1], runs[2], accuracy: 1e-4)
            XCTAssertEqual(g.ends[2], c.length, accuracy: 1e-4, "the last leg ends at the finish")
            XCTAssertEqual(g.starts[1] - g.ends[0], RelayTuning.boxGap, accuracy: 1e-4, "a waiting spot one box past the line")
            XCTAssertEqual(g.starts[0], 0)
        }
    }

    func testHandoffsComeInLegOrderForEveryTeamAndEveryTeamFinishes() {
        let r = run(plan())
        XCTAssertEqual(r.sim.phase, .results)
        for t in 0..<3 {
            let mine = r.handoffs.filter { $0.t == t }
            XCTAssertEqual(mine.map(\.leg), [1, 2], "team \(t): runner 2 then runner 3")
            XCTAssertLessThan(mine[0].at, mine[1].at)
            XCTAssertNotNil(r.sim.racers[t].finishTime, "team \(t) finished (the rival teams too)")
            XCTAssertEqual(r.sim.racers[t].legIndex, 2)
            XCTAssertEqual(r.sim.racers[t].name, "T\(t)L2", "the last runner's stats are the team's now")
        }
    }

    func testTheFasterTeamWinsAndPrizesFollowThePlace() {
        let r = run(plan())
        XCTAssertEqual(r.sim.playerPlace, 1, "the quick player team wins")
        XCTAssertEqual(RelayTuning.prizes, [30, 18, 10])
        XCTAssertEqual(RelayTuning.prize(place: 1), 30); XCTAssertEqual(RelayTuning.prize(place: 2), 18); XCTAssertEqual(RelayTuning.prize(place: 3), 10)
        let slow = run(plan(waddles: [[0.1, 0.1, 0.1], [0.6, 0.6, 0.6], [0.4, 0.4, 0.4]]), playerRate: 3)
        XCTAssertEqual(slow.sim.playerPlace, 3)
    }

    func testAParkFriendLegIsRunByTheAIAndIgnoresTheFingers() {
        var sim = plan(friendLegs: [1, 2]).makeSim(seed: 3)
        let dt: Float = 1.0 / 60
        var foot = 0, tapT: Float = 0
        var sawFriend = false
        for _ in 0..<(60 * 60) where sim.phase != .results {
            tapT += dt
            while tapT >= 1 / 7 { tapT -= 1 / 7; sim.playerTap(foot: foot); foot = 1 - foot }
            sim.tick(dt: dt)
            if sim.racers[0].relayAI {
                sawFriend = true
                XCTAssertEqual(sim.playerTap(foot: 0), .ignored, "the buttons rest while a friend runs")
            }
            _ = sim.takeEvents()
        }
        XCTAssertTrue(sawFriend)
        XCTAssertNotNil(sim.racers[0].finishTime, "the friends finished the team's race on their own")
        XCTAssertEqual(sim.racers[0].legIndex, 2)
    }

    func testRelayWorksOnEveryCourse() {
        for c in [RaceCourse.ripple, .splash, .wave] {
            let r = run(plan(course: c, waddles: [[0.8, 0.8, 0.8], [0.7, 0.7, 0.7], [0.7, 0.7, 0.7]]))
            XCTAssertEqual(r.sim.phase, .results, "\(c.tier)")
            XCTAssertEqual(r.handoffs.count, 6, "\(c.tier): 2 handoffs per team")
        }
    }

    // MARK: with bodies

    /// A room of `count` Jelbies plus Park-visitor bodies made the way the stage makes them.
    @MainActor
    final class Field {
        let room: RaceTripTests.Room
        var extras: [JellyActor] = []
        var t: Float = 0
        init(count: Int) {
            room = RaceTripTests.Room(count: count)
            let care = room.care
            care.race.cue = { _ in }
            care.parkBook.spawn = { [unowned self] specs, spots in
                let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
                let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
                self.extras = specs.enumerated().map { k, v in
                    let a = JellyActor(id: count + k, name: v.name, simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[k])
                    a.care = care
                    a.sim.substeps = ParkTuning.visitorSubsteps
                    let b = BlobBrain.forGame()
                    b.demo = nil; b.runMoveDemo = nil; b.autonomy = true
                    b.steerID = a.id
                    care.wireWorld(b, isBob: false)
                    b.attach(renderMesh: rm, synchronous: true)
                    a.brain = b
                    a.reset(drop: 0, shift: true)
                    return a
                }
                return self.extras
            }
            care.parkBook.clear = { [unowned self] in self.extras = [] }
        }
        func step() {
            let dt = room.actors[0].sim.stepDt
            for a in extras { a.brain?.tick(sim: a.sim, skinner: a.skinner, dt: dt, touched: false); a.skinner.jelly.tick(brain: a.brain!, sim: a.sim, dt: dt) }
            room.step()
            for a in extras where a.updateSleep(forceAwake: false) { a.sim.step() }
            t += dt
        }
        func run(_ s: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(s * 60) { step(); if let u = until, u() { break } } }
    }

    /// Smallest distance between any particle of one body and any of another (a stand-in for the skin gap).
    private func particleGap(_ a: SoftBody, _ b: SoftBody) -> Float {
        var best = Float.infinity
        var i = 0
        while i < a.n {
            let p = SIMD3(a.x[3 * i], a.x[3 * i + 1], a.x[3 * i + 2])
            var j = 0
            while j < b.n { best = min(best, simd_distance(p, SIMD3(b.x[3 * j], b.x[3 * j + 1], b.x[3 * j + 2]))); j += 3 }
            i += 3
        }
        return best
    }

    func testBlockerNeedsThreeRunnersAndFriendsMustBePals() {
        let f = Field(count: 1)
        Self.keep.append(f)
        let care = f.room.care
        XCTAssertEqual(care.relayBlocker(order: [0], friends: []), "Relay needs 3 runners. Go to the Park and make friends!")
        XCTAssertNotNil(care.relayBlocker(order: [0], friends: [3, 4]), "strangers do not count")
        for v in [3, 4] { care.parkBook.add(points: ParkTuning.palAt + 1, visitor: v, character: care.jelly(0)!.character) }
        XCTAssertNil(care.relayBlocker(order: [0], friends: [3, 4]))
        XCTAssertNotNil(care.relayBlocker(order: [0], friends: [3, 3]), "the same friend twice is one runner")
    }

    func testTheWholeRelayWithOneJelbieAndTwoParkFriends() {
        let f = Field(count: 1)
        Self.keep.append(f)
        let care = f.room.care
        let chars = care.jelly(0)!.character
        for v in [3, 4] { care.parkBook.add(points: ParkTuning.palAt + 1, visitor: v, character: chars) }
        care.race.autoRate = 6; care.race.autoReturnAfter = 0.5
        let coins = care.bath.wallet.count
        let waddle = care.jelly(0)!.stats.waddle
        care.startRelay(order: [0], friends: [3, 4], course: .puddle, seed: 9)
        XCTAssertTrue(care.race.active); XCTAssertTrue(care.race.isRelay)
        f.run(4) { care.race.trackVisible && !f.extras.isEmpty }
        XCTAssertEqual(f.extras.count, 8, "two friends and six rivals")
        let rb = care.raceBook.relay
        XCTAssertEqual(rb.teams.count, 3)
        XCTAssertTrue(rb.teams[0][0] === f.room.actors[0], "Bob runs leg 1")
        XCTAssertTrue(rb.teams[0][1] === f.extras[0] && rb.teams[0][2] === f.extras[1], "the friends fill legs 2 and 3, in order")
        let looks = Set(f.extras.prefix(2).map { $0.name })
        XCTAssertEqual(looks, Set([3, 4].compactMap { care.parkBook.visitor($0)?.name }), "the friends are the real ones")
        // waiting runners really wait: still and asleep soon
        f.run(6) { care.race.sim?.phase == .running }
        let waiter = rb.teams[1][1]
        let spot0 = waiter.floor
        f.run(1)
        XCTAssertLessThan(simd_distance(waiter.floor, spot0), 0.05, "he waits in his box")
        f.run(60, until: { care.race.hasResults })
        XCTAssertTrue(care.race.hasResults, "the relay finished")
        for t in 0..<3 { XCTAssertEqual(care.race.sim!.racers[t].legIndex, 2, "team \(t) ran all three legs") }
        XCTAssertGreaterThan(care.bath.wallet.count - coins, 0, "the team's prize is paid")
        XCTAssertGreaterThan(care.jelly(0)!.stats.waddle, waddle, "the owned runner trained")
        f.run(12, until: { !care.race.active })
        XCTAssertFalse(care.race.active)
        XCTAssertTrue(f.extras.isEmpty, "the visitor bodies are let go")
        XCTAssertFalse(f.room.actors[0].brain!.race.active)
        XCTAssertEqual(f.room.actors[0].sim.arenaRadius, GameCamera.arenaRadius, accuracy: 1e-3)
    }

    func testNobodyOverlapsAtTheHandoffs() {
        let f = Field(count: 3)
        Self.keep.append(f)
        let care = f.room.care
        care.race.autoRate = 6; care.race.autoReturnAfter = 99
        care.startRelay(order: [0, 1, 2], friends: [], course: .puddle, seed: 5)
        f.run(5) { care.race.trackVisible }
        XCTAssertEqual(f.extras.count, 6, "only the two rival teams are visitors")
        let rb = care.raceBook.relay
        XCTAssertTrue(rb.teams[0][0] === f.room.actors[0] && rb.teams[0][1] === f.room.actors[1] && rb.teams[0][2] === f.room.actors[2])
        f.run(1)
        var minGap = Float.infinity
        var handoffs = 0
        var last = [0, 0, 0]
        let g = f
        let c2 = care
        let rb2 = rb
        last = rb2.active
        for _ in 0..<(70 * 60) where !c2.race.hasResults {
            g.step()
            guard rb2.teams.count == 3 else { continue }
            if rb2.active != last { handoffs += zip(rb2.active, last).map { $0 - $1 }.reduce(0, +); last = rb2.active }
            // each team's pair around a handoff (outgoing, incoming) and every body against its lane neighbours
            for t in 0..<3 {
                let leg = rb2.active[t]
                if leg >= 1 { minGap = min(minGap, particleGap(rb2.teams[t][leg - 1].sim, rb2.teams[t][leg].sim)) }
                if leg < 2 { minGap = min(minGap, particleGap(rb2.teams[t][leg].sim, rb2.teams[t][leg + 1].sim)) }
            }
        }
        XCTAssertEqual(handoffs, 6, "three teams, two handoffs each")
        XCTAssertGreaterThan(minGap, 0.04, "the incoming and outgoing runners never touch (smallest particle gap \(minGap))")
    }
}
