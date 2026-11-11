//
//  HopNearTests.swift
//  The hop onto and off a seat uses a NEAR stand spot, never the far side of a two-seat piece (a leap across the room). These tests use local constants
//  (near 1.2, far 2.0), not the BlobBrain symbols, so they compile on the base too: run there they are the "before" measurement.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HopNearTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    static let near: Float = 1.2, far: Float = 2.0, ownClear: Float = 0.37
    static let at = SIMD2<Float>(0, -0.8)

    override func setUp() { DecorField.shared.clear(); room() }
    override func tearDown() { DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    private func room() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }

    /// Every piece a Jelbie hops onto from the floor (the beanbag has its own exit).
    static var kinds: [DecorKind] { DecorKind.allCases.filter { $0.hopSit && $0 != .beanbag } }

    func seatXZ(_ f: DecorFoot, _ seat: Int) -> SIMD2<Float> {
        let sp = f.kind.sitPoints[min(seat, f.kind.sitPoints.count - 1)]
        return f.centre + f.turned(SIMD2(sp.x, sp.z))
    }
    func group(_ f: DecorFoot, index i: Int) -> String {
        if i < 5 { return "front" }
        if f.kind.rockRide { return i < 8 ? "behind" : (i < 11 ? "side+x" : "side-x") }
        return i < 8 ? "side+x" : (i < 11 ? "side-x" : "behind")
    }

    // MARK: the list's shape

    func testTheStandListStillStartsWithTheFrontRow() {
        let r = MotionRig(game: true); Self.keep.append(r)
        for kind in Self.kinds {
            DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: Self.at.x, z: Self.at.y)])
            let f = DecorField.shared.foot(7)!
            for seat in 0..<kind.sitPoints.count {
                let spots = r.brain.hopStandSpots(f, seat: seat)
                XCTAssertEqual(spots.count, 14, "\(kind) seat \(seat): 14 spots")
                guard spots.count >= 5 else { continue }
                let zs = spots.prefix(5).map { f.local($0 - f.centre).y }
                XCTAssertLessThan((zs.max() ?? 0) - (zs.min() ?? 0), 1e-3, "\(kind) seat \(seat): the first five share one piece-local z (the front row): \(zs)")
            }
        }
    }

    // MARK: the pick per piece and seat

    func testHopOnPicksPerPieceAndSeat() {
        let r = MotionRig(game: true); Self.keep.append(r)
        let b = r.brain
        for kind in Self.kinds {
            DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: Self.at.x, z: Self.at.y)])
            let f = DecorField.shared.foot(7)!
            for seat in 0..<kind.sitPoints.count {
                let spots = b.hopStandSpots(f, seat: seat)
                let seatP = seatXZ(f, seat)
                for blocked in [false, true] {
                    b.decorIgnore = 7
                    b.peers = blocked ? { [(id: Int.max / 2, pos: spots[0])] } : { [] }
                    b.peerCacheStep = -1
                    // today's rule, spelled out: the first spot the floor allows with nobody on it
                    var todayHop: Float = -1
                    for p in spots { let q = b.fixed(p); if simd_distance(p, q) < 0.06, b.peerFree(q) { todayHop = simd_distance(p, seatP); break } }
                    // the floor-legal candidates (outside the piece by ownClear, within far of the seat, floor accepts them)
                    let legal = spots.filter { f.distance($0) >= Self.ownClear && simd_distance($0, seatP) <= Self.far && simd_distance($0, b.fixed($0)) < 0.06 }
                    let shortest = legal.map { simd_distance($0, seatP) }.min() ?? 0
                    let limit = max(Self.near, shortest + 0.05)
                    let pick = b.hopStand(f, seat: seat)
                    let hop = pick.map { simd_distance($0, seatP) } ?? -1
                    let idx = pick.flatMap { p in spots.firstIndex { simd_distance($0, p) < 1e-4 } }
                    let grp = idx.map { group(f, index: $0) } ?? "none"
                    print(String(format: "HOPNEAR-TABLE %@ seat %d %@ pick %@ hop %.2f | today-rule pick would be hop %.2f", "\(kind)", seat, blocked ? "blocked" : "free", grp, hop, todayHop))
                    guard let p = pick else { if blocked { XCTFail("\(kind) seat \(seat) blocked: no pick") }; continue }
                    if blocked {
                        XCTAssertLessThanOrEqual(hop, Self.far + 1e-3, "\(kind) seat \(seat) blocked: hop \(hop)")
                        XCTAssertGreaterThanOrEqual(f.distance(p), Self.ownClear, "\(kind) seat \(seat) blocked: outside the footprint (\(f.distance(p)))")
                        let lx = f.local(p - f.centre).x, sx = kind.sitPoints[seat].x, hx = f.spec.half.x
                        if sx < 0 { XCTAssertLessThan(lx, hx, "\(kind) seat \(seat) blocked: not past the far end (local x \(lx))") }
                        if sx > 0 { XCTAssertGreaterThan(lx, -hx, "\(kind) seat \(seat) blocked: not past the far end (local x \(lx))") }
                    } else {
                        XCTAssertLessThanOrEqual(hop, limit + 1e-3, "\(kind) seat \(seat) free: hop \(hop) within max(\(Self.near), shortest \(shortest) + 0.05)")
                    }
                }
            }
        }
        b.peers = { [] }; b.peerCacheStep = -1; b.decorIgnore = nil
    }

    // MARK: real sits

    /// A is sent to sit (seat 0, from the left); B stands on the first front spot the whole time. Measures the real hop on and off.
    func testARealSitNeverHopsAcrossThePiece() {
        let cases: [(DecorKind, String)] = [(.loveseat, "loveseat"), (.diningset, "diningset"), (.swing, "swing"), (.seesaw, "seesaw"), (.sandbox, "sandbox"), (.armchair, "armchair")]
        for (kind, name) in cases {
            DecorField.shared.clear()
            DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: Self.at.x, z: Self.at.y)])
            let f = DecorField.shared.foot(7)!
            let lab = SocialTests.Lab(n: 2, positions: [SIMD2(Self.at.x - 1.6, Self.at.y + 2.0), SIMD2(Self.at.x + 1.6, Self.at.y + 2.0)], quiet: true, seed: 7)
            Self.keep.append(lab)
            let a = lab.rigs[0], bb = lab.rigs[1]
            let spot = a.brain.hopStandSpots(f, seat: 0)[0]
            bb.sim.teleport(toXZ: spot)
            for _ in 0..<120 { bb.sim.step() }
            bb.brain.currentPose(bb.sim)
            bb.brain.px = spot.x; bb.brain.pz = spot.y
            for _ in 0..<10 { lab.tick(watching: false) }
            a.brain.idleForced = true
            // (B on the first front spot with the lab's 1.4 m peer gap can leave no free stand spot: the piece is skipped, as it always was; that is no failure here)
            guard a.brain.idleStart(.decorSit, a.sim) else { print("HOPNEAR-RUN \(name) NO-START (no free stand spot with B parked: the piece is skipped)"); continue }
            let seat = a.brain.idleState.seat
            let seatP = seatXZ(f, seat)
            var prev = a.brain.position, hopOn: Float = -1, hopOff: Float = -1, satTicks = 0, sawStage1 = false, finished = false, ended = false
            for _ in 0..<(60 * 70) {
                lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
                for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
                let st = a.brain.idleState.bagStage
                if a.brain.idleState.kind == .decorSit {
                    if st >= 1, !sawStage1 { sawStage1 = true; hopOn = simd_distance(prev, seatP) }
                    if st == 2 { satTicks += 1 }
                } else if a.brain.idleState.kind == nil, !ended {
                    ended = true; finished = true
                    if sawStage1 { hopOff = simd_distance(a.brain.position, seatP) }
                }
                prev = a.brain.position
                if ended { break }
            }
            let bMoved = simd_distance(bb.brain.position, spot)
            if !sawStage1 {
                print("HOPNEAR-RUN \(name) REFUSED (the seat was given up before any hop; finished \(finished)) B moved \(bMoved)")
                continue
            }
            print(String(format: "HOPNEAR-RUN %@ on %.2f off %.2f sat %.1f (seat %d, B moved %.2f)", name, hopOn, hopOff, Float(satTicks) / 60, seat, bMoved))
            XCTAssertLessThanOrEqual(hopOn, 2.3, "\(name): the hop on")
            XCTAssertLessThanOrEqual(hopOff, 2.0 + 0.05, "\(name): the hop off")
        }
        DecorField.shared.clear()
    }
}
