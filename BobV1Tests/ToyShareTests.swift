//
//  ToyShareTests.swift
//  Toys that are out (placed in the room): the slide has a stand spot wherever it can be placed, and a short simulated session (3 Jelbies, a few toys out) counts
//  the toy sessions, the slide rides and the share of time spent on toys. Logs go to the scratchpad.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ToyShareTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let log = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/g-toys/"
    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() { DecorField.shared.clear(); ToyTuning.settle = 5; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    func testSlideHasAStandSpotWhereverItIsPlaced() {
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.brain.anticsEnabled = true
        var valid = 0, misses: [String] = []
        for q in 0..<4 { for xi in -3...3 { for zi in -3...3 {
            let at = SIMD2<Float>(Float(xi) * 1.2, Float(zi) * 1.2)
            guard DecorPlacement.isValid(.slide, at: at, among: [], ignoring: nil, quarter: q) else { continue }
            valid += 1
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .slide, x: at.x, z: at.y, turns: q)])
            let f = DecorField.shared.foot(7)!
            rig.brain.px = -0.5; rig.brain.pz = 1.2
            rig.brain.decorIgnore = 7
            if rig.brain.decorStand(.decorSlide, f, from: SIMD2(-0.5, 1.2)) == nil { misses.append("q\(q)@\(at.x),\(at.y)") }
        } } }
        try? "valid \(valid) misses \(misses.count): \(misses.joined(separator: " "))".write(toFile: Self.log + "slide-stand.txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(misses.isEmpty, "slide placements with no stand spot: \(misses.prefix(20))")
    }

    struct Tot { var toy = 0, frames = 0, sessions = 0, rides = 0, backToBack = 0, perKind: [DecorKind: Int] = [:] }

    func session(seconds: Float, seed: UInt64, park: Bool = false) -> Tot {
        if park { RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0) }
        let starts: [SIMD2<Float>] = [SIMD2(-1.8, 1.4), SIMD2(-0.2, 1.8), SIMD2(1.4, 1.2)]
        let lab = SocialTests.Lab(n: 3, positions: starts, quiet: false, seed: seed)
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.idleMood = .happy }
        if park { for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius } }
        DecorField.shared.set(park ? ParkToys.placed : [PlacedDecor(uid: 1, kind: .slide, x: 2.6, z: 0.6, turns: nil), PlacedDecor(uid: 2, kind: .ball, x: -2.4, z: -0.2, turns: nil),
                               PlacedDecor(uid: 3, kind: .drum, x: -2.6, z: 2.2, turns: nil), PlacedDecor(uid: 4, kind: .bouncymat, x: 0.2, z: -1.6, turns: nil)])
        DecorField.shared.toys = ToyBook()
        var t = Tot(), prev = [Int](repeating: -1, count: 3), last = [DecorKind?](repeating: nil, count: 3), prevRide = [Bool](repeating: false, count: 3)
        for _ in 0..<Int(seconds * 60) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            for (i, r) in lab.rigs.enumerated() {
                let b = r.brain
                let uid = (b.idleState.kind.map { BlobBrain.decorKinds.contains($0) } ?? false) ? b.idleState.decorUID : -1
                t.frames += 1
                if uid >= 0 || b.toy.waitUID >= 0 { t.toy += 1 }
                if uid >= 0, prev[i] < 0, let f = DecorField.shared.foot(uid) {
                    t.sessions += 1; t.perKind[f.kind, default: 0] += 1
                    if last[i] == f.kind { t.backToBack += 1 }
                    last[i] = f.kind
                }
                prev[i] = uid
                let ride = b.idleState.kind == .decorSlide && b.idleState.slideStage == 5
                if ride && !prevRide[i] { t.rides += 1 }
                prevRide[i] = ride
            }
        }
        return t
    }

    func testToysOutGetPlayedWith() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOYSHARE_SIM"] != nil, "slow: set TOYSHARE_SIM=1")
        share(park: false)
    }
    func testParkToysGetPlayedWith() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOYSHARE_SIM"] != nil && ProcessInfo.processInfo.environment["TOYSHARE_PARK"] != nil, "slow: set TOYSHARE_SIM=1 and TOYSHARE_PARK=1")
        share(park: true)
    }

    func share(park: Bool) {
        let secs = Float(ProcessInfo.processInfo.environment["TOYSHARE_SECONDS"] ?? "") ?? 60
        var all = Tot()
        for seed in [3] as [UInt64] {
            let t = session(seconds: secs, seed: seed, park: park)
            all.toy += t.toy; all.frames += t.frames; all.sessions += t.sessions; all.rides += t.rides; all.backToBack += t.backToBack
            for (k, v) in t.perKind { all.perKind[k, default: 0] += v }
            DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        }
        if park { GameCamera.endPark(count: 3) }
        let line = String(format: (park ? "PARK " : "HOME ") + "1 seed x %.0fs x 3 Jelbies: toy share %.1f%%, sessions %d, slide rides %d, back-to-back same toy %d, per kind %@\n", secs, 100 * Double(all.toy) / Double(max(1, all.frames)), all.sessions, all.rides, all.backToBack, all.perKind.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ","))
        try? line.write(toFile: Self.log + (park ? "toy-share-park.txt" : "toy-share-home.txt"), atomically: true, encoding: .utf8)
        print("TOYSHARE " + line)
    }
}
