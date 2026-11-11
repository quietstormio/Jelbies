//
//  HopNearWaitTests.swift
//  At the end of the rest he stays seated (up to `hopExitWait`, 3 s) while no near spot is free to hop down to; with a near spot free he gets up at the end of the rest as ever.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HopNearWaitTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { DecorField.shared.clear(); room() }
    override func tearDown() { DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    private func room() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }

    /// A loveseat sit; when he is settled in the seat (phase 2) every near spot is occupied (or not). Returns the rest's hold and how long phase 2 lasted.
    private func run(blocked: Bool) -> (hold: Float, rest: Float, nearSpots: Int) {
        room()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .loveseat, x: 2.8, z: 0.6)])
        let r = MotionRig(game: true); Self.keep.append(r)
        r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: SIMD2(-1.0, 1.0))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.decorSit, r.sim), "the sit starts")
        var hold: Float = 0, rest: Float = 0, armed = false, nearSpots = 0
        for _ in 0..<(60 * 60) {
            r.tick(); DecorField.shared.tick(dt: 1.0 / 60)
            let s = r.brain.idleState
            if s.kind == .decorSit, s.bagStage == 2, s.phase == 2 {
                if !armed {
                    armed = true; hold = s.hold
                    if blocked, let f = DecorField.shared.foot(7) {
                        let o = r.brain.hopNearOrder(f, seat: s.seat, tolerance: 0.05)
                        let near = o.spots.filter { $0.hop <= o.near }.map(\.spot)
                        nearSpots = near.count
                        r.brain.peers = { near.map { (id: Int.max / 2, pos: $0) } }
                        r.brain.peerCacheStep = -1
                    }
                }
                rest = max(rest, s.phaseT)
            } else if armed { break }
        }
        r.brain.peers = { [] }; r.brain.peerCacheStep = -1
        print(String(format: "HOPNEAR-WAIT %@ hold %.2f phase2 lasted %.2f (near spots held: %d)", blocked ? "blocked" : "free", hold, rest, nearSpots))
        return (hold, rest, nearSpots)
    }

    func testHeWaitsSeatedWhileNoNearSpotIsFree() {
        let b = run(blocked: true)
        XCTAssertGreaterThan(b.nearSpots, 0, "there are near spots to block")
        XCTAssertGreaterThan(b.hold, 0)
        XCTAssertGreaterThanOrEqual(b.rest, b.hold + 1, "still seated at hold + 1 s")
        XCTAssertLessThanOrEqual(b.rest, b.hold + 3.5, "getting up by hold + 3.5 s")
    }

    func testWithANearSpotFreeHeGetsUpAtTheEndOfTheRestAsBefore() {
        let f = run(blocked: false)
        XCTAssertGreaterThan(f.hold, 0)
        XCTAssertLessThanOrEqual(f.rest, f.hold + 0.1, "no added delay (rest \(f.rest), hold \(f.hold))")
    }
}
