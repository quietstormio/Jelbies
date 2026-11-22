//
//  WalkBoardTests.swift
//  move-board-r1: the walk board is publish-only. Opt-in: TEST_RUNNER_WALKBOARD_PROOF=1 (TEST_RUNNER_WALKBOARD_SECONDS, default 120; TEST_RUNNER_WALKBOARD_SEEDS, default 3).
//  testPredictionError: three roaming bodies at home; at every publish of a walking intent the board's prediction at +0.5 / +1 / +2 s is compared with where the body really was.
//  testPublishCost: microseconds per publish.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WalkBoardTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { BlobBrain.pickBudgetSeconds = .infinity }
    override func tearDown() {
        BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds
        DecorField.shared.clear(); HopscotchLine.shared.prune(keeping: [])
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    private func homeLab(seed: UInt64) -> SocialTests.Lab {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        _ = GameCamera.refreshRoam(aspect: 440 / 956)
        RoomLayout.dynamicBoxes = []
        let lab = SocialTests.Lab(positions: SocialTests.starts, quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            r.skinner.autoBlink = false
            let b = r.brain
            b.sleepEnabled = false; b.anticsEnabled = true; b.watching = false; b.homeRoom = true
            b.idleMood = .happy; b.idleNight = 0; b.idleDeepNight = 0; b.idleMorning = 0
            b.socialBook.cooldown = 6 + Float(i) * 3; b.idleState.cooldown = 8 + Float(i) * 2; b.restTimer = 0.5 + Float(i)
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
        }
        Self.keep.append(lab)
        return lab
    }

    private struct Pending { var due: Int, h: Int, pred: SIMD2<Float>, guess: SIMD2<Float>, target: SIMD2<Float> }

    func testPredictionError() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["WALKBOARD_PROOF"] != nil else { throw XCTSkip("set TEST_RUNNER_WALKBOARD_PROOF=1") }
        XCTAssertTrue(WalkBoard.publishOn, "run with the board on")
        let seconds = Float(env["WALKBOARD_SECONDS"].flatMap { Float($0) } ?? 120)
        let seeds: [UInt64] = (0..<(env["WALKBOARD_SEEDS"].flatMap { Int($0) } ?? 3)).map { 41 + 7 * UInt64($0) }
        let hs: [Float] = [0.5, 1.0, 2.0]
        var errBoard = [[Float]](repeating: [], count: 3), errGuess = [[Float]](repeating: [], count: 3)
        var cleanBoard = [[Float]](repeating: [], count: 3), cleanGuess = [[Float]](repeating: [], count: 3)
        var publishes = 0, missing = 0, lastMismatch = 0, walkSeen = 0, claimBad = 0, farBad = 0, farChecked = 0, idleBad = 0, claimChecked = 0
        for s in seeds {
            let lab = homeLab(seed: s)
            var lastStamp = [Float](repeating: -1, count: lab.rigs.count)
            var pend = [[Pending]](repeating: [], count: lab.rigs.count)
            let ticks = Int(seconds * 60)
            for k in 0..<ticks {
                lab.tick(watching: false)
                let now = lab.board.now
                for i in 0..<lab.rigs.count {
                    let b = lab.rigs[i].brain
                    guard let it = lab.board.intent(i) else { missing += 1; continue }
                    let truth = lab.snapshot[i].pos
                    // due predictions
                    var keep: [Pending] = []
                    for p in pend[i] {
                        if k >= p.due {
                            let eB = simd_distance(p.pred, truth), eG = simd_distance(p.guess, truth)
                            errBoard[p.h].append(eB); errGuess[p.h].append(eG)
                            if let cur = lab.board.intent(i), cur.state == .walking, let l = cur.points.last, simd_distance(l, p.target) < 0.01 { cleanBoard[p.h].append(eB); cleanGuess[p.h].append(eG) }
                        } else { keep.append(p) }
                    }
                    pend[i] = keep
                    if it.state == .standing || it.state == .fixed, it.stamp == now || true { if lab.board.idleness(at: truth, now: now) > 0.2 { idleBad += 1 } }
                    guard it.state == .walking, it.stamp == now, it.stamp != lastStamp[i] else { continue }
                    lastStamp[i] = it.stamp; publishes += 1
                    if case .walk(let target, _) = b.script {
                        walkSeen += 1
                        if it.points.last != target { lastMismatch += 1 }
                        var other = -1; for j in 0..<lab.rigs.count where j != i { other = j; break }
                        claimChecked += 1
                        if !lab.board.claimed(near: target, radius: 0.1, except: other) { claimBad += 1 }
                        // a point 3 u away that no other body claims within 0.5 u
                        for a in 0..<8 {
                            let ang = Float(a) * .pi / 4, c = target + SIMD2(cosf(ang), sinf(ang)) * 3
                            if lab.board.all.allSatisfy({ ($0.slot.map { simd_distance($0, c) } ?? 9) > 0.6 }) { farChecked += 1; if lab.board.claimed(near: c, radius: 0.5, except: -1) { farBad += 1 }; break }
                        }
                    }
                    let dir = SIMD2<Float>(sinf(it.yaw), cosf(it.yaw))
                    for (hi, h) in hs.enumerated() {
                        guard let pr = lab.board.position(of: i, after: h, now: now) else { continue }
                        pend[i].append(Pending(due: k + Int(h * 60), h: hi, pred: pr, guess: it.pos + dir * 0.8 * h, target: it.points.last ?? it.pos))
                    }
                }
            }
            for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        }
        func pct(_ a: [Float], _ q: Float) -> Float { a.isEmpty ? .nan : a.sorted()[min(a.count - 1, Int(Float(a.count) * q))] }
        MotionLog.write("WALKBOARD seeds \(seeds.count) x \(seconds) s: \(publishes) walking publishes, bodies without an intent \(missing), last-point != target \(lastMismatch), claimed-at-target misses \(claimBad)/\(claimChecked), claimed-3u-away hits \(farBad)/\(farChecked), idleness>0.2 under a body \(idleBad)")
        for (hi, h) in hs.enumerated() {
            MotionLog.write(String(format: "WALKBOARD +%.1f s | all n=%d | board median %.3f p90 %.3f | old guess median %.3f p90 %.3f | same-target n=%d | board median %.3f p90 %.3f | old guess median %.3f p90 %.3f",
                                   h, errBoard[hi].count, pct(errBoard[hi], 0.5), pct(errBoard[hi], 0.9), pct(errGuess[hi], 0.5), pct(errGuess[hi], 0.9),
                                   cleanBoard[hi].count, pct(cleanBoard[hi], 0.5), pct(cleanBoard[hi], 0.9), pct(cleanGuess[hi], 0.5), pct(cleanGuess[hi], 0.9)))
        }
        XCTAssertEqual(missing, 0, "every body on the stage has an intent")
        XCTAssertEqual(lastMismatch, 0, "a walker's last point is its walk target")
        XCTAssertEqual(claimBad, 0, "claimed is true at a walker's target")
        XCTAssertEqual(farBad, 0, "claimed is false 3 u away")
        XCTAssertEqual(idleBad, 0, "idleness of a cell a body stands in is ~0")
        XCTAssertGreaterThan(walkSeen, 20)
    }

    func testPublishCost() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["WALKBOARD_PROOF"] != nil else { throw XCTSkip("set TEST_RUNNER_WALKBOARD_PROOF=1") }
        let lab = homeLab(seed: 41)
        for _ in 0..<600 { lab.tick(watching: false) }
        let r = lab.rigs[0], b = r.brain
        b.abortScript(r.sim, r.skinner)
        let n = 200_000
        let pos = b.position
        // standing publish
        var t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<n { b.publishToBoard(pos: pos) }
        let standing = (CFAbsoluteTimeGetCurrent() - t0) / Double(n) * 1e6
        // walking publish (route of two waypoints + target)
        b.route = [pos + SIMD2(0.5, 0), pos + SIMD2(0.5, 0.5)]
        b.script = .walk(target: pos + SIMD2(1, 1), then: .none)
        t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<n { b.publishToBoard(pos: pos) }
        let walking = (CFAbsoluteTimeGetCurrent() - t0) / Double(n) * 1e6
        t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<n { lab.board.tickBody(b, pos: pos) }
        let tickBody = (CFAbsoluteTimeGetCurrent() - t0) / Double(n) * 1e6
        MotionLog.write(String(format: "WALKBOARD cost: walking publish %.3f us, standing publish %.3f us, tickBody (walking brain: note only) %.3f us", walking, standing, tickBody))
        b.route = []; b.abortScript(r.sim, r.skinner)
    }
}
