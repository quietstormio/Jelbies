//
//  BedExitSpotTests.swift
//  Where a Jelbie stands when he gets up from the pet bed (`bedExitSpot`, BlobBrain+Sleep.swift): never within `peerGap` of another Jelbie, never in the tray's box, up within 1 s
//  of a spot freeing, and after `bedExitGiveUp` s at the latest on the spot with the most room. Headless, one MotionRig in a pet bed; the other Jelbies are positions.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BedExitSpotTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { DecorField.shared.clear(); RoomLayout.dynamicBoxes = []; room() }
    override func tearDown() { DecorField.shared.clear(); RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    private func room() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }

    /// A Jelbie going to sleep in the pet bed (uid 7); `others` are the other Jelbies' floor positions, seen only from the stretch (stage 5) on, so they cannot stop his walk to the bed.
    private final class Scene {
        let rig: MotionRig
        let foot: DecorFoot
        var others: [SIMD2<Float>] = []
        var armed = false
        init(rig: MotionRig, foot: DecorFoot) { self.rig = rig; self.foot = foot }
        var brain: BlobBrain { rig.brain }
        func tick() {
            rig.tick(); DecorField.shared.tick(dt: 1.0 / 60)
            if brain.idleState.kind == .sleep, brain.sleep.stage == 5 { armed = true }
        }
        /// Ticks until `done` (or `limit` s).
        func run(_ limit: Float, until done: () -> Bool) { let n = Int(limit * 60); for _ in 0..<n { tick(); if done() { break } } }
    }

    private func bedScene(seed: UInt64) -> Scene {
        room()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .petbed, x: 2.3, z: 0.4)])
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: SIMD2(-0.5, 1.4))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.seed = seed
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim), "he goes to bed")
        r.brain.sleep.hold = 3
        let s = Scene(rig: r, foot: DecorField.shared.foot(7)!)
        r.brain.peers = { [unowned s] in s.armed ? s.others.enumerated().map { (id: 100 + $0.offset, pos: $0.element) } : [] }
        return s
    }

    private func ring(_ f: DecorFoot, _ a: Float, extra: Float = 0) -> SIMD2<Float> {
        f.centre + f.turned(SIMD2(sinf(a), cosf(a)) * (f.kind.spec.half.y + 0.4 + extra))
    }
    /// Jelbies all round the bed (every 0.5 rad), none within `gap` rad of the front: nothing but maybe the front is free; radial offsets vary so the clearances differ.
    private func blockers(_ f: DecorFoot, openFront gap: Float = 0) -> [SIMD2<Float>] {
        (0..<12).compactMap { k in
            let a = 0.1 + 0.5 * Float(k)
            let w = atan2f(sinf(a), cosf(a))
            if abs(w) < gap { return nil }
            return ring(f, a, extra: 0.04 * Float(k % 5))
        }
    }

    /// Runs to the moment he has chosen (bedHop 3), returns the sim seconds at which the first try found nothing (nil = never waited) and at the choice.
    private func untilChosen(_ s: Scene, limit: Float = 70) -> (waitStart: Float?, chosen: Float?) {
        var waitStart: Float?, chosen: Float?
        s.run(limit, until: {
            if waitStart == nil, s.brain.sleep.exitT0 >= 0 { waitStart = s.rig.t }
            if s.brain.idleState.kind == .sleep, s.brain.sleep.bedHop == 3 { chosen = s.rig.t; return true }
            return false
        })
        return (waitStart, chosen)
    }

    // (a) other Jelbies on the front spots: at the moment he stands he is no closer than `peerFree` enforces
    func testNeverCloserToAPeerThanPeerFreeAllows() {
        for seed in UInt64(11)...12 {
            let s = bedScene(seed: seed)
            let stand = s.brain.bedStandSpots(s.foot)
            s.others = [stand[0], stand[1], stand[2], stand[3]]          // the front and both sides
            let c = untilChosen(s)
            XCTAssertNotNil(c.chosen, "seed \(seed): he chose a spot")
            let gap = s.brain.peerGap
            for o in s.others { XCTAssertGreaterThanOrEqual(simd_distance(s.brain.sleep.exitSpot, o), gap - 1e-4, "seed \(seed): the spot keeps peerGap from a peer") }
            s.run(8, until: { s.brain.idleState.kind == nil })
            XCTAssertNil(s.brain.idleState.kind, "seed \(seed): up")
            let p = s.brain.position
            for o in s.others { XCTAssertGreaterThanOrEqual(simd_distance(p, o), gap - 0.15, "seed \(seed): standing, no closer than peerFree's \(gap) (\(simd_distance(p, o)))") }
            let line = "BEDEXIT (a) seed \(seed) wait \(c.waitStart.map { String(format: "%.2f", $0) } ?? "none") chosen \(c.chosen.map { String(format: "%.2f", $0) } ?? "nil") spot \(s.brain.sleep.exitSpot)"
            MotionLog.write(line); print(line)
        }
    }

    // (b) the tray's box over the old fallback spot (the front): not chosen
    func testTheTraysBoxOverTheFallbackSpotIsNotChosen() {
        for seed in UInt64(11)...12 {
            let s = bedScene(seed: seed)
            let front = ring(s.foot, 0)
            let box = RoomLayout.FlatBox(centre: front, half: SIMD2(0.55, 0.4), height: 0.3)
            s.others = blockers(s.foot, openFront: 0.7)
            RoomLayout.dynamicBoxes = [box]
            let c = untilChosen(s)
            XCTAssertNotNil(c.chosen, "seed \(seed): he chose a spot")
            let m = s.brain.footprint * RoomLayout.lowPropRadiusScale
            XCTAssertGreaterThanOrEqual(RoomLayout.boxDistanceXZ(s.brain.sleep.exitSpot, box), m, "seed \(seed): off the tray by his base radius")
            XCTAssertGreaterThan(simd_distance(s.brain.sleep.exitSpot, front), 0.3, "seed \(seed): not the front spot")
            s.run(8, until: { s.brain.idleState.kind == nil })
            XCTAssertNil(s.brain.idleState.kind, "seed \(seed): up")
            let line = "BEDEXIT (b) seed \(seed) wait \(c.waitStart.map { String(format: "%.2f", $0) } ?? "none") chosen \(c.chosen.map { String(format: "%.2f", $0) } ?? "nil") spot \(s.brain.sleep.exitSpot) front \(front)"
            MotionLog.write(line); print(line)
        }
    }

    // (c) everything blocked, then one spot frees: he is up within 1 s of it
    func testUpWithinASecondOfASpotFreeing() {
        for seed in UInt64(11)...12 {
            let s = bedScene(seed: seed)
            s.others = blockers(s.foot)
            var freedAt: Float?
            var chosenAt: Float?
            s.run(70, until: {
                if freedAt == nil, s.brain.sleep.exitT0 >= 0, s.rig.t - s.brain.sleep.exitT0 >= 1.0 { s.others = [] ; freedAt = s.rig.t }
                if s.brain.idleState.kind == .sleep, s.brain.sleep.bedHop == 3 { chosenAt = s.rig.t; return true }
                return false
            })
            XCTAssertNotNil(freedAt, "seed \(seed): he waited in bed")
            if let a = freedAt, let b = chosenAt {
                XCTAssertLessThanOrEqual(b - a, 1.0, "seed \(seed): up within 1 s of the spot freeing (\(b - a))")
                let line = "BEDEXIT (c) seed \(seed) freed at \(String(format: "%.2f", a)) chosen at \(String(format: "%.2f", b)) delay \(String(format: "%.2f", b - a))"
                MotionLog.write(line); print(line)
            } else { XCTFail("seed \(seed): never chose") }
            s.run(8, until: { s.brain.idleState.kind == nil })
            XCTAssertNil(s.brain.idleState.kind, "seed \(seed): up")
        }
    }

    // (d) everything blocked for good: up within about 3.5 s, on the spot with the most room
    func testBlockedForGoodHeTakesTheRoomiestSpotAfterAbout3Seconds() {
        for seed in UInt64(11)...12 {
            let s = bedScene(seed: seed)
            s.others = blockers(s.foot)
            var sawAwakePoseWhileWaiting = false
            var waitStart: Float?, chosenAt: Float?
            s.run(70, until: {
                if waitStart == nil, s.brain.sleep.exitT0 >= 0 { waitStart = s.rig.t }
                if s.brain.sleep.exitT0 >= 0, s.brain.sleep.bedHop == 0, s.brain.sleep.stage == 5 { sawAwakePoseWhileWaiting = true }
                if s.brain.idleState.kind == .sleep, s.brain.sleep.bedHop == 3 { chosenAt = s.rig.t; return true }
                return false
            })
            XCTAssertTrue(sawAwakePoseWhileWaiting, "seed \(seed): he stayed in the bed (stage 5) meanwhile")
            guard let w = waitStart, let c = chosenAt else { XCTFail("seed \(seed): no wait / no choice"); continue }
            XCTAssertLessThanOrEqual(c - w, 3.5, "seed \(seed): up within 3.5 s (\(c - w))")
            XCTAssertGreaterThanOrEqual(c - w, 2.9, "seed \(seed): but only after about 3 s (\(c - w))")
            let spot = s.brain.sleep.exitSpot
            func room(_ p: SIMD2<Float>) -> Float { s.others.map { simd_distance($0, p) }.min()! }
            let walkable = s.brain.bedExitCandidates(s.foot).filter { simd_distance($0, s.brain.fixed($0)) < 0.06 }
            let best = (walkable.isEmpty ? s.brain.bedExitCandidates(s.foot) : walkable).map { room(s.brain.fixed($0)) }.max()!
            XCTAssertGreaterThanOrEqual(room(s.brain.fixed(spot)), best - 1e-3, "seed \(seed): the spot with the most room (\(room(s.brain.fixed(spot))) vs \(best))")
            s.run(8, until: { s.brain.idleState.kind == nil })
            XCTAssertNil(s.brain.idleState.kind, "seed \(seed): up")
            let line = "BEDEXIT (d) seed \(seed) wait \(String(format: "%.2f", w)) chosen \(String(format: "%.2f", c)) after \(String(format: "%.2f", c - w)) room \(String(format: "%.2f", room(s.brain.fixed(spot)))) best \(String(format: "%.2f", best))"
            MotionLog.write(line); print(line)
        }
    }
}
