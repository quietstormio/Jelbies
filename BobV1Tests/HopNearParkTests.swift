//
//  HopNearParkTests.swift
//  The hop-on pieces a player meets today live in the park (the seesaw at its fixed place, `ParkToys.placed`). For every seat of every such piece: the stand spot, the picked seat and the exit
//  spot, with the other Jelbie far away (`free`) and standing on the stand spot / the exit spot (`peer`). Prints one PARKSEAT line per seat and case.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HopNearParkTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0 }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    /// (as `HopscotchTests.parkLab` does it)
    private func parkLab(n: Int, seed: UInt64 = 5) -> SocialTests.Lab {
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let starts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4)]
        let lab = SocialTests.Lab(n: n, positions: Array(starts.prefix(n)), quiet: true, seed: seed)
        for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.anticsEnabled = true; r.brain.idleMood = .happy }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()
        return lab
    }

    private func two(_ v: SIMD2<Float>) -> String { String(format: "%.2f,%.2f", v.x, v.y) }
    private func twoOpt(_ v: SIMD2<Float>?) -> String { v.map(two) ?? "none" }

    func testParkSeatsAtTheirRealPlace() {
        let lab = parkLab(n: 2)
        Self.keep.append(lab)
        let b = lab.rigs[0].brain
        let origPeers = b.peers
        let far = SIMD2<Float>(3.5, 3.5)
        let reachMax = BlobBrain.hopReach + 0.01
        let rulesOn = HopNearAid.off == 0
        var pieces = 0
        for f in DecorField.shared.feet where f.kind.hopSit {
            pieces += 1
            for s in 0..<f.kind.sitPoints.count {
                let seatP = b.hopSeatXZ(f, seat: s)
                func ask(_ peerAt: SIMD2<Float>) -> (stand: SIMD2<Float>?, pick: Int, exit: SIMD2<Float>) {
                    b.peers = { [(id: Int.max / 2, pos: peerAt)] }; b.peerCacheStep = -1
                    let saveIgnore = b.decorIgnore, saveSeat = b.idleState.seat
                    b.decorIgnore = f.uid
                    let stand = b.decorStand(.decorSit, f, from: SIMD2(b.px, b.pz), seat: s)
                    let pick = b.hopNearSeat(f, seat: s)
                    b.idleState.seat = s
                    let exit = b.hopExitSpot(f)
                    b.decorIgnore = saveIgnore; b.idleState.seat = saveSeat
                    b.peers = origPeers; b.peerCacheStep = -1
                    return (stand, pick, exit)
                }
                func line(_ c: String, _ r: (stand: SIMD2<Float>?, pick: Int, exit: SIMD2<Float>)) {
                    let hop = r.stand.map { String(format: "%.2f", simd_distance($0, seatP)) } ?? "-"
                    print("PARKSEAT \(f.kind.rawValue) seat\(s) case=\(c) seat=\(two(seatP)) pick=\(r.pick) stand=\(twoOpt(r.stand)) hop=\(hop) exit=\(two(r.exit)) exitHop=\(String(format: "%.2f", simd_distance(r.exit, seatP)))")
                }
                let free = ask(far)
                line("free", free)
                if rulesOn {
                    XCTAssertNotNil(free.stand, "\(f.kind) seat \(s): a stand spot with nobody near")
                    XCTAssertLessThanOrEqual(simd_distance(free.exit, seatP), reachMax, "\(f.kind) seat \(s): the exit hop")
                }
                if let st = free.stand, rulesOn { XCTAssertLessThanOrEqual(simd_distance(st, seatP), reachMax, "\(f.kind) seat \(s): the hop on") }
                // peer on the free case's stand spot (stand and pick asked again), then on its exit spot (exit asked again)
                let onStand = ask(free.stand ?? far)
                let onExit = ask(free.exit)
                var peerLine = onStand
                peerLine.exit = onExit.exit
                line("peer", peerLine)
                if let st = onStand.stand, rulesOn { XCTAssertLessThanOrEqual(simd_distance(st, seatP), reachMax, "\(f.kind) seat \(s) peer: the hop on") }
            }
        }
        b.peers = origPeers; b.peerCacheStep = -1
        print("PARKSEAT hop-sit pieces in the park: \(pieces)")
        XCTAssertGreaterThan(pieces, 0, "the park has a hop-sit piece")
    }
}
