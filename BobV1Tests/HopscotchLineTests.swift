//
//  HopscotchLineTests.swift
//  The hopscotch queue never stalls (park-hopline-r1): four in a line all finish, a blocked start is given up after a few tries, and the queue spots sit on open floor, 1.7 apart.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HopscotchLineTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    let uid = ParkToys.hopscotchUID
    let dt: Float = 1.0 / 60
    /// (= `HopscotchTuning.startTries` once it exists: the brief's value)
    let startTries = 3

    override func setUp() {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        HopscotchTuning.joinChance = 0.35
        HopscotchLine.shared.prune(keeping: [])
    }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5; HopscotchTuning.joinChance = 0.35
        HopscotchLine.shared.prune(keeping: [])
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    func parkLab(positions: [SIMD2<Float>], seed: UInt64) -> SocialTests.Lab {
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let lab = SocialTests.Lab(n: positions.count, positions: positions, quiet: true, seed: seed)
        for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.anticsEnabled = true; r.brain.idleMood = .happy }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()
        return lab
    }

    // 1
    func testFourInALineAllFinish() {
        HopscotchTuning.joinChance = 1
        for seed in UInt64(1)...3 {
            DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); HopscotchLine.shared.prune(keeping: [])
            let lab = parkLab(positions: [SIMD2(-2.1, -1.35), SIMD2(0.694, -1.541), SIMD2(-0.748, -0.395), SIMD2(-0.547, -1.721)], seed: seed)
            let line = HopscotchLine.shared
            for r in lab.rigs { r.brain.autonomy = true; r.brain.idleForced = true }
            // the leader starts it; the others come in the way the game does: the line posts its news, each free Jelbie rolls once (joinChance 1) and walks to his queue spot
            // (a direct `decorStart` for all four is refused for good: the others stand within the park's 1.4 of every queue spot)
            let started = [lab.rigs[0].brain.decorStart(.decorHopscotch, lab.rigs[0].sim, only: nil, uid: uid)]
            var trace = [String](repeating: "", count: 4), maxPlayers = 0
            var seqs = [[Int]](repeating: [], count: 4), entries = [Int](repeating: 0, count: 4), prevStage = [Int](repeating: -9, count: 4)
            var minGap = Float.infinity, finishedAt: Float = -1
            for i in 0..<(60 * 90) {
                lab.tick(watching: false); DecorField.shared.tick(dt: dt)
                maxPlayers = max(maxPlayers, line.players(uid).count)
                for a in 0..<4 {
                    let s = line.square(uid, a)
                    if s >= 0, s < 8, seqs[a].last != s { seqs[a].append(s) }
                    let b = lab.rigs[a].brain
                    let stage = b.idleState.kind == .decorHopscotch ? b.idleState.slideStage : -9
                    if stage == 4, prevStage[a] != 4 { entries[a] += 1 }
                    if stage != prevStage[a] { trace[a] += " \(stage)@\(Int(Float(i) / 60))r\(b.idleState.decorRetry)" }
                    if s == HopscotchLine.done { b.autonomy = false; b.idleForced = false }          // (done: he stays off the court, no second lap)
                    prevStage[a] = stage
                    for c in (a + 1)..<4 where c < 4 { minGap = min(minGap, simd_distance(lab.snapshot[a].pos, lab.snapshot[c].pos)) }
                }
                if i > 600, !line.active, lab.rigs.allSatisfy({ $0.brain.idleState.kind == nil }) { finishedAt = Float(i) / 60; break }
            }
            print("[hopline] seed \(seed): started \(started) finished at \(finishedAt) s, min centre gap \(minGap), stage-4 entries \(entries), seqs \(seqs.map { $0.count }), most in the line \(maxPlayers)\n  traces (stage@sim-s r<retries>): \(trace)")
            XCTAssertTrue(started.allSatisfy { $0 }, "seed \(seed): the leader started")
            XCTAssertEqual(maxPlayers, 4, "seed \(seed): all four joined the line")
            XCTAssertGreaterThan(finishedAt, 0, "seed \(seed): the line is done within 90 sim-s; line \(line.players(uid).map { "\($0.id):slot \($0.slot) sq \($0.sq)" }) kinds \(lab.rigs.map { $0.brain.idleState.kind.map { "\($0)" } ?? "-" }) stages \(lab.rigs.map { $0.brain.idleState.slideStage })")
            for a in 0..<4 { XCTAssertEqual(seqs[a], Array(0..<8), "seed \(seed): Jelbie \(a) landed on squares 1...8 in order: \(seqs[a])") }
            XCTAssertFalse(line.active, "seed \(seed): the line is empty at the end")
            XCTAssertGreaterThan(minGap, 0.75, "seed \(seed): bodies never overlap (closest centres \(minGap))")
            for a in 0..<4 { XCTAssertLessThanOrEqual(entries[a], startTries + 1, "seed \(seed): Jelbie \(a) stepped up \(entries[a]) times") }
        }
    }

    // 2
    func testBlockedStartGivesUp() {
        HopscotchTuning.joinChance = 1
        let lab = parkLab(positions: [SIMD2(-2.1, -1.35), SIMD2(0.3, -1.4), SIMD2(2.0, 0.5)], seed: 2)
        let line = HopscotchLine.shared
        for r in lab.rigs { r.brain.autonomy = true; r.brain.idleForced = true }
        let court = DecorField.shared.foot(uid)!
        let start = court.centre + court.turned(HopscotchCourt.queueSpot(slot: 0))
        // rig 0 leads, rig 1 queues; rig 2 is no player: it is parked on the start as soon as the leader is off it (he has landed on square 1)
        XCTAssertTrue(lab.rigs[0].brain.decorStart(.decorHopscotch, lab.rigs[0].sim, only: nil, uid: uid))
        XCTAssertTrue(lab.rigs[1].brain.decorStart(.decorHopscotch, lab.rigs[1].sim, only: nil, uid: uid))
        let joiner = lab.rigs[1].brain
        var blocked = false, blockedAt: Float = 0, endedAt: Float = -1, entries = 0, prevStage = -9, maxSq = -1
        var minToStart = Float.infinity, trace = ""
        for i in 0..<(60 * 90) {
            lab.tick(watching: false); DecorField.shared.tick(dt: dt)
            if !blocked, line.square(uid, 0) >= 0 { blocked = true; blockedAt = Float(i) / 60 }
            if blocked {
                let b = lab.rigs[2]
                b.brain.autonomy = false; b.brain.px = start.x; b.brain.pz = start.y; b.sim.teleport(toXZ: start); b.brain.currentPose(b.sim)          // (held there every tick, floor spot and body: nothing moves him off)
                minToStart = min(minToStart, simd_distance(joiner.position, start)); maxSq = max(maxSq, line.square(uid, 1))
            }
            let stage = joiner.idleState.kind == .decorHopscotch ? joiner.idleState.slideStage : -9
            if stage == 4, prevStage != 4 { entries += 1 }
            if stage != prevStage, blocked { trace += " \(stage)@\(Int(Float(i) / 60 - blockedAt))" }
            prevStage = stage
            if blocked, joiner.idleState.kind == nil, !line.contains(uid, 1) { endedAt = Float(i) / 60 - blockedAt; break }
            if blocked, Float(i) / 60 - blockedAt > 40 { break }
        }
        print("[hopline] blocked start: joiner's hopscotch ended \(endedAt) s after the block, stage-4 entries \(entries), joiner closest to the start \(minToStart), his highest square \(maxSq), stages:\(trace)")
        XCTAssertLessThan(maxSq, 0, "the joiner must not hop while the start is blocked (a scenario where he gets on anyway proves nothing)")
        XCTAssertGreaterThan(endedAt, 0, "the joiner gave the game up; stage \(joiner.idleState.slideStage) kind \(String(describing: joiner.idleState.kind)) pos \(joiner.position) line \(line.players(uid).map { "\($0.id):slot \($0.slot) sq \($0.sq)" })")
        XCTAssertLessThanOrEqual(endedAt, 25)
        XCTAssertLessThanOrEqual(entries, startTries + 1, "stage-4 entries \(entries)")
    }

    // 3
    func testQueueSpotsAreOnOpenFloor() {
        let lab = parkLab(positions: [SIMD2(0, 3)], seed: 1)
        let brain = lab.rigs[0].brain
        let court = DecorField.shared.foot(uid)!
        let solids = DecorField.shared.feet.filter { $0.kind != .hopscotch && $0.spec.solid }
        let slideCorners: [(String, SIMD2<Float>)] = [("slideLB", SIMD2(1.45, -1.4)), ("slideLF", SIMD2(1.45, 3.4)), ("ladder", SIMD2(2.9, -1.17))]
        let seesaw = SIMD2<Float>(-2.28, -1.49)
        let own: [SIMD2<Float>] = [SIMD2(-3.7, 1.9), SIMD2(1.7, -2.8), SIMD2(2.95, -2.65)]
        for (label, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(956.0 / 440.0))] {
            GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: aspect)
            let entries = ParkLayout.spots(count: 5)
            var pts: [SIMD2<Float>] = []
            for slot in 0...3 {
                let p = court.centre + court.turned(HopscotchCourt.queueSpot(slot: slot)); pts.append(p)
                let q = brain.fixed(p)
                let c = GameCamera.constrain(SIMD3(p.x, 0, p.y))
                let moved = simd_distance(p, q), cMoved = simd_distance(p, SIMD2(c.x, c.z))
                var near = (kind: "-", d: Float.infinity)
                for f in solids { let d = f.distance(p); if d < near.d { near = ("\(f.kind)", d) } }
                let toSlide = slideCorners.map { String(format: "%@ %.2f", $0.0, simd_distance(p, $0.1)) }.joined(separator: " ")
                let toOwn = own.map { String(format: "%.2f", simd_distance(p, $0)) }.joined(separator: "/")
                let toEntry = entries.map { String(format: "%.2f", simd_distance(p, $0)) }.joined(separator: "/")
                print(String(format: "[qspot] %@ slot %d world (%.2f, %.2f) fixedMoved %.3f constrainMoved %.3f nearestSolid %@ %.2f | %@ | seesaw %.2f | own %@ | entry %@", label, slot, p.x, p.y, moved, cMoved, near.kind, near.d, toSlide, simd_distance(p, seesaw), toOwn, toEntry))
                // the seesaw and the slide present together (launch-next 4e4855c6): clearance of the body's edge from each footprint
                let seeF = DecorField.shared.feet.first { $0.kind == .seesaw }, slideF = DecorField.shared.feet.first { $0.kind == .slide }
                let dSee = seeF.map { $0.distance(p) } ?? .infinity, dSlide = slideF.map { $0.distance(p) } ?? .infinity
                let need = brain.footprint + 0.3
                print(String(format: "[qspot] %@ slot %d clearance: seesaw %.2f, slide %.2f (body radius %.2f + 0.3 = %.2f needed)%@", label, slot, dSee, dSlide, brain.footprint, need, slot == 0 ? " (the start: known, accepted)" : ""))
                if slot >= 1 {
                    XCTAssertGreaterThanOrEqual(dSee, need, "\(label) slot \(slot) is only \(dSee) from the seesaw")
                    XCTAssertGreaterThanOrEqual(dSlide, need, "\(label) slot \(slot) is only \(dSlide) from the slide")
                }
                XCTAssertLessThan(moved, 0.05, "\(label) slot \(slot): the room moves the spot by \(moved)")
                XCTAssertLessThan(cMoved, 0.05, "\(label) slot \(slot): constrain moves the spot by \(cMoved)")
                for (n, corner) in slideCorners { XCTAssertGreaterThanOrEqual(simd_distance(p, corner), 1.0, "\(label) slot \(slot) is \(simd_distance(p, corner)) from \(n)") }
            }
            print(String(format: "[qspot] %@ START is %.2f from the seesaw's stand spot (known, accepted)", label, simd_distance(pts[0], seesaw)))
            for a in 0..<pts.count { for b in (a + 1)..<pts.count { XCTAssertGreaterThanOrEqual(simd_distance(pts[a], pts[b]), 1.6, "\(label): slots \(a), \(b) are \(simd_distance(pts[a], pts[b])) apart") } }
        }
    }
}
