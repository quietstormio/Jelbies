//
//  ToyPlayTests.swift
//  The toy loop (BlobBrain+ToyPlay.swift): every interactive piece has a reachable stand spot (rotated, at several places), starts, finishes and lets go; a placed toy is
//  noticed and played with; a busy single-user toy is queued for in turn without anybody standing in anybody; the pull decays and recovers.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ToyPlayTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let log = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/g-toys/"
    static func write(_ name: String, _ s: String) { try? s.write(toFile: log + name, atomically: true, encoding: .utf8) }

    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0; room() }
    override func tearDown() { DecorField.shared.clear(); ToyTuning.settle = 5; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    private func room() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }

    static let interactive: [DecorKind] = DecorKind.allCases.filter { $0.activeInteraction != nil }

    // MARK: stand spots

    func testEveryInteractivePieceHasAStandSpotRotatedAndAtSeveralPlaces() { standAudit(aspect: 440.0 / 956.0, file: "stand-audit.txt") }
    /// The same on the landscape screen (a wider floor, the same corners).
    func testEveryInteractivePieceHasAStandSpotInLandscape() { standAudit(aspect: 956.0 / 440.0, file: "stand-audit-landscape.txt") }
    private func standAudit(aspect: Float, file: String) {
        _ = GameCamera.camera(aspect: aspect)
        var lines: [String] = [], misses = 0
        let spots: [SIMD2<Float>] = [SIMD2(2.8, 0.6), SIMD2(-2.8, -1.5), SIMD2(0.4, -3.2), SIMD2(-2.9, 2.3), SIMD2(2.9, 2.6)]
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.brain.anticsEnabled = true
        for kind in Self.interactive {
            var row = "\(kind.rawValue):"
            for q in 0..<4 {
                var ok = 0, valid = 0
                for p in spots {
                    var at = p
                    let lim = DecorPlacement.xLimit(kind, z: p.y, quarter: q)
                    at.x = max(-lim, min(lim, at.x))
                    guard DecorPlacement.isValid(kind, at: at, among: [], ignoring: nil, quarter: q) else { continue }
                    valid += 1
                    DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: at.x, z: at.y, turns: q)])
                    let f = DecorField.shared.foot(7)!
                    rig.brain.px = -0.5; rig.brain.pz = 1.2
                    let mv = kind.activeInteraction!
                    rig.brain.decorIgnore = (mv == .decorSit || mv == .decorHop || mv == .decorSlide) ? 7 : nil          // (as decorStart sets it)
                    if rig.brain.decorStand(mv, f, from: SIMD2(-0.5, 1.2), seat: 0) != nil { ok += 1 } else { misses += 1; row += " MISS(q\(q) @\(at.x),\(at.y))" }
                }
                row += " q\(q)=\(ok)/\(valid)"
            }
            lines.append(row)
        }
        Self.write(file, lines.joined(separator: "\n"))
        XCTAssertEqual(misses, 0, "pieces with no stand spot:\n" + lines.filter { $0.contains("MISS") }.joined(separator: "\n"))
    }

    // MARK: every toy plays through

    func testEveryInteractivePieceStartsFinishesAndLetsGo() {
        var lines: [String] = [], fails: [String] = []
        for kind in Self.interactive {
            DecorField.shared.clear()
            let at = SIMD2<Float>(2.8, 0.6)
            DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: min(at.x, DecorPlacement.xLimit(kind, z: at.y)), z: at.y)])
            let r = MotionRig(game: true)
            Self.keep.append(r)
            r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: SIMD2(-1.0, 1.0))
            for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim)
            r.brain.idleForced = true
            let mv = kind.activeInteraction!
            guard r.brain.decorStart(mv, r.sim) else { fails.append("\(kind) does not start"); lines.append("\(kind.rawValue): NOT STARTED"); continue }
            var moved = false
            r.run(60, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
                DecorField.shared.tick(dt: 1.0 / 60)
                if let a = DecorField.shared.anim[7], a.active { moved = true }
            }
            let done = r.brain.idleState.kind == nil, free = DecorField.shared.occupant[7] == nil
            r.run(2) { DecorField.shared.tick(dt: 1.0 / 60) }
            let floorOK = abs(r.sim.floorY) < 1e-4 && r.sim.centroid().y < 1.0
            lines.append("\(kind.rawValue): finished=\(done) released=\(free) animated=\(moved) floor=\(floorOK) t=\(r.t)")
            if !(done && free && floorOK) { fails.append("\(kind) finished=\(done) released=\(free) floor=\(floorOK)") }
            if !moved { fails.append("\(kind) did not animate the piece") }
        }
        Self.write("play-audit.txt", lines.joined(separator: "\n"))
        XCTAssertTrue(fails.isEmpty, fails.joined(separator: "\n"))
    }

    // MARK: the pull

    func testPullIsHighWhenFreshDecaysToABaselineAndDipsAfterAPlay() {
        let f = DecorField.shared
        f.set([PlacedDecor(uid: 5, kind: .duck, x: 2, z: 0)])
        f.toyPostNews(5, SIMD2(2, 0))
        let fresh = f.toyPull(5)
        XCTAssertGreaterThan(fresh, 0.95)
        f.toyPlayed(5)
        XCTAssertLessThan(f.toyPull(5), 0.15, "just played: hardly any pull")
        f.toys.clock += 150
        XCTAssertGreaterThan(f.toyPull(5), 0.5, "back after a couple of minutes")
        f.toys.clock += 3000
        let old = f.toyPull(5)
        XCTAssertGreaterThan(old, 0.25); XCTAssertLessThan(old, 0.35)
    }

    // MARK: noticing, playing and turns

    private func lab(_ n: Int, _ kind: DecorKind, at p: SIMD2<Float>) -> SocialTests.Lab {
        let starts: [SIMD2<Float>] = [SIMD2(-1.8, 1.4), SIMD2(-0.2, 1.8), SIMD2(1.4, 1.2)]
        let lab = SocialTests.Lab(n: n, positions: Array(starts.prefix(n)), quiet: true, seed: 5)
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.idleMood = .happy }
        DecorField.shared.set([PlacedDecor(uid: 1, kind: .loveseat, x: -9, z: -3)].filter { _ in false })
        DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: p.x, z: p.y)])
        return lab
    }
    /// Runs the lab; returns (first start time per rig, min separation of two brains outside a social, queue seen).
    private func runLab(_ lab: SocialTests.Lab, seconds: Float, until: (() -> Bool)? = nil) -> (starts: [Float?], minGap: Float, waited: Int) {
        var starts = [Float?](repeating: nil, count: lab.rigs.count), minGap = Float.infinity, waited = 0
        for k in 0..<Int(seconds * 60) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            for (i, r) in lab.rigs.enumerated() {
                if starts[i] == nil, r.brain.idleState.decorUID == 7 { starts[i] = Float(k) / 60 }
                if r.brain.toy.waitUID == 7 { waited += 1 }
            }
            if k % 6 == 0 { for i in 0..<lab.rigs.count { for j in (i + 1)..<lab.rigs.count where lab.rigs[i].brain.social == nil {
                minGap = min(minGap, lab.brainGap(i, j))
            } } }
            if let until, until() { break }
        }
        return (starts, minGap, waited)
    }

    func testANewToyIsNoticedAndPlayedWithAtOnceByTheNearestOne() {
        let lab = lab(1, .drum, at: SIMD2(1.6, 0.4))
        let r = runLab(lab, seconds: 14)
        XCTAssertNotNil(r.starts[0], "he went to the drum")
        if let t = r.starts[0] { XCTAssertLessThan(t, 6, "within a few seconds of its arrival") }
        XCTAssertEqual(lab.rigs[0].brain.toy.noticed, 1)
    }

    func testThreeJelbiesOnASingleUserSlideTakeTurnsWithoutOverlapOrDeadlock() {
        let lab = lab(3, .slide, at: SIMD2(2.9, -0.4))
        var played = [Int](repeating: 0, count: 3), prev = [Bool](repeating: false, count: 3)
        var res: (starts: [Float?], minGap: Float, waited: Int) = ([], 0, 0)
        var gapMin = Float.infinity, waiting = 0, maxWaitStreak = 0, streak = [Int](repeating: 0, count: 3)
        for k in 0..<(60 * 100) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            for (i, r) in lab.rigs.enumerated() {
                let on = r.brain.idleState.kind == .decorSlide
                if on && !prev[i] { played[i] += 1 }
                prev[i] = on
                if r.brain.toy.waitUID == 7 { streak[i] += 1; waiting += 1 } else { streak[i] = 0 }
                maxWaitStreak = max(maxWaitStreak, streak[i])
            }
            if k % 6 == 0 { for i in 0..<3 { for j in (i + 1)..<3 { gapMin = min(gapMin, lab.brainGap(i, j)) } } }
            // never two on the slide at once
            let users = lab.rigs.filter { $0.brain.idleState.kind == .decorSlide && $0.brain.idleState.decorUID == 7 }.count
            XCTAssertLessThanOrEqual(users, 1)
        }
        res.minGap = gapMin
        Self.write("slide-turns.txt", "played \(played) waited-frames \(waiting) longest wait \(Float(maxWaitStreak) / 60)s minGap \(gapMin) queued \(lab.rigs.map { $0.brain.toy.queued }) tookTurn \(lab.rigs.map { $0.brain.toy.tookTurn }) gaveUp \(lab.rigs.map { $0.brain.toy.gaveUp })")
        XCTAssertGreaterThanOrEqual(played.filter { $0 > 0 }.count, 2, "at least two of them rode (turns)")
        XCTAssertGreaterThan(waiting, 60, "somebody queued")
        XCTAssertLessThan(Float(maxWaitStreak) / 60, ToyTuning.queueTimeout + 3, "nobody waits forever")
        XCTAssertGreaterThan(gapMin, 0.55, "nobody stands in anybody")
    }

    func testTwoJelbiesSitTogetherOnTheCushionPile() {
        let lab = lab(2, .cushionpile, at: SIMD2(2.4, 0.2))
        var both = 0, seats = Set<Int>()
        for _ in 0..<(60 * 40) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            let on = lab.rigs.map { $0.brain.idleState.kind == .decorSit && $0.brain.idleState.bagStage == 2 }
            if on[0] && on[1] { both += 1; seats = [lab.rigs[0].brain.idleState.seat, lab.rigs[1].brain.idleState.seat] }
        }
        Self.write("pile-together.txt", "both seated frames \(both) seats \(seats)")
        XCTAssertGreaterThan(both, 60, "both sit on it together")
        XCTAssertEqual(seats, [0, 1])
    }
}
