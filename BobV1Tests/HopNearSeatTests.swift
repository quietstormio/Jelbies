//
//  HopNearSeatTests.swift
//  The seat fallback (`hopNearSeat`, called from `decorStart`): a two-seat piece whose picked seat has no stand spot is sat on from the other seat, with a hop inside
//  `hopFar`; with both seats taken, or no seat with a spot, there is no start.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HopNearSeatTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { DecorField.shared.clear(); room() }
    override func tearDown() { DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    private func room() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }

    static let placements: [SIMD2<Float>] = [SIMD2(2.8, 0.6), SIMD2(-2.8, -1.5), SIMD2(0.4, -3.2), SIMD2(-2.9, 2.3), SIMD2(2.9, 2.6)]
    static let from = SIMD2<Float>(-0.5, 1.2)

    struct Case { var kind: DecorKind; var q: Int; var at: SIMD2<Float> }

    /// Placements (the audits' own) of the two-seat pieces: those where seat 0 has no stand spot but another seat has one, and those where no seat has one.
    private func scan(_ rig: MotionRig) -> (recover: [Case], none: [Case]) {
        var recover: [Case] = [], none: [Case] = []
        for kind in [DecorKind.loveseat, .diningset, .swing, .seesaw, .sandbox] {
            for q in 0..<4 {
                for p in Self.placements {
                    var at = p
                    let lim = DecorPlacement.xLimit(kind, z: p.y, quarter: q)
                    at.x = max(-lim, min(lim, at.x))
                    guard DecorPlacement.isValid(kind, at: at, among: [], ignoring: nil, quarter: q) else { continue }
                    DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: at.x, z: at.y, turns: q)])
                    let f = DecorField.shared.foot(7)!
                    rig.brain.px = Self.from.x; rig.brain.pz = Self.from.y; rig.brain.decorIgnore = 7
                    let has = (0..<f.kind.sitPoints.count).map { rig.brain.decorStand(.decorSit, f, from: Self.from, seat: $0) != nil }
                    if !has[0], has.contains(true) { recover.append(Case(kind: kind, q: q, at: at)) }
                    if !has.contains(true) { none.append(Case(kind: kind, q: q, at: at)) }
                }
            }
        }
        rig.brain.decorIgnore = nil
        return (recover, none)
    }

    private func newRig(_ c: Case) -> MotionRig {
        DecorField.shared.clear()          // (a seat taken by the previous case's sitter stays on a re-set piece of the same kind and uid)
        room()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: c.kind, x: c.at.x, z: c.at.y, turns: c.q)])
        let r = MotionRig(game: true); Self.keep.append(r)
        r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: Self.from)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.idleForced = true
        return r
    }

    func testThePickedSeatWithoutASpotFallsBackToTheOtherSeat() {
        let probe = MotionRig(game: true); Self.keep.append(probe)
        let s = scan(probe)
        print("HOPNEAR-SEAT placements: fallback recovers \(s.recover.count) \(s.recover.map { "\($0.kind) q\($0.q) @\($0.at)" }), no seat has a spot \(s.none.count)")
        XCTAssertGreaterThan(s.recover.count, 0, "the audits' placements include a two-seat piece whose first seat has no stand spot and another has")
        for c in s.recover.prefix(6) {
            let r = newRig(c)
            let f = DecorField.shared.foot(7)!
            do {
                let b = r.brain
                b.decorIgnore = 7
                let ds = (0..<f.kind.sitPoints.count).map { b.decorStand(.decorSit, f, from: SIMD2(b.px, b.pz), seat: $0) }
                let ns = b.hopNearSeat(f, seat: 0)
                let reach = ds.compactMap { $0 }.map { b.reachable(SIMD2(b.px, b.pz), $0) }
                print("HOPNEAR-SEATDIAG \(c.kind) q\(c.q) @\(c.at): decorStand per seat \(ds), hopNearSeat(0) \(ns), reachable \(reach), decorLocked \(b.decorLocked), pos \(b.position), available \(DecorField.shared.available(f)), freeSeat \(String(describing: DecorField.shared.freeSeat(f, preferring: b.px - f.centre.x)))")
                b.decorIgnore = nil
            }
            XCTAssertTrue(r.brain.idleStart(.decorSit, r.sim), "\(c.kind) q\(c.q) @\(c.at): the sit starts on the other seat")
            let seat = r.brain.idleState.seat
            let seatP = r.brain.hopSeatXZ(f, seat: seat)
            var prev = r.brain.position, hop: Float = -1
            r.run(40, until: { hop >= 0 || r.brain.idleState.kind == nil }) {
                DecorField.shared.tick(dt: 1.0 / 60)
                if hop < 0, r.brain.idleState.kind == .decorSit, r.brain.idleState.bagStage >= 1 { hop = simd_distance(prev, seatP) }
                prev = r.brain.position
            }
            print(String(format: "HOPNEAR-SEAT %@ q%d @(%.2f,%.2f): sits on seat %d, hop %.2f", "\(c.kind)", c.q, c.at.x, c.at.y, seat, hop))
            XCTAssertNotEqual(seat, 0, "\(c.kind) q\(c.q): the other seat")
            XCTAssertGreaterThanOrEqual(hop, 0, "\(c.kind) q\(c.q): he hopped on")
            XCTAssertLessThanOrEqual(hop, BlobBrain.hopFar + 0.05, "\(c.kind) q\(c.q): the hop is inside hopFar")
        }
    }

    func testBothSeatsTakenOrNoSeatWithASpotStartsNothing() {
        let probe = MotionRig(game: true); Self.keep.append(probe)
        let s = scan(probe)
        // both seats taken: nothing to start, even where a seat would have a spot
        if let c = s.recover.first {
            let r = newRig(c)
            DecorField.shared.take(7, seat: 0, by: 90); DecorField.shared.take(7, seat: 1, by: 91)
            XCTAssertFalse(r.brain.idleStart(.decorSit, r.sim), "\(c.kind): both seats taken, no start")
        } else { XCTFail("no placement to test with") }
        // the other seat taken: the free seat has no spot, so no start
        if let c = s.recover.first {
            DecorField.shared.clear()
            let r = newRig(c)
            DecorField.shared.take(7, seat: 1, by: 91)
            let started = r.brain.idleStart(.decorSit, r.sim)
            print("HOPNEAR-SEAT other seat taken at \(c.kind) q\(c.q): started \(started)")
            XCTAssertFalse(started, "\(c.kind): seat 1 taken and seat 0 has no spot, no start")
        }
        print("HOPNEAR-SEAT no seat has a spot at \(s.none.count) placements: \(s.none.map { "\($0.kind) q\($0.q) @\($0.at)" })")
        for c in s.none.prefix(6) {
            let r = newRig(c)
            XCTAssertFalse(r.brain.idleStart(.decorSit, r.sim), "\(c.kind) q\(c.q) @\(c.at): no seat has a stand spot, no start")
        }
    }
}
