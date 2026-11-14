//
//  BubblePlayTests.swift
//  The bubble wand's play (2026-11-09: "more bubble popping emotes ... hop more and pop particular bubbles"): the apex table stays honest (each move's real crown peak), and a 3-Jelbie
//  run with a steady stream, BEFORE (BubbleTuning.classic) vs AFTER: hop-pops per minute, chases that end in a pop, claim -> pop time, share of the chase spent walking, uses per move,
//  jump / bubblePop sounds that PLAYED past every guard (AudioHub.dropTap, on the sim clock), nobody sharing a bubble, nobody outside the play area.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BubblePlayTests: XCTestCase {
    var wand: BubbleWand { BubbleWand.shared }
    override func setUp() { super.setUp(); wand.resetForTests(); EmoteFeetTests.reset(); BubbleTuning.classic = false; BubbleTuning.forceMove = nil }
    override func tearDown() { BubbleTuning.classic = false; BubbleTuning.forceMove = nil; wand.resetForTests(); EmoteFeetTests.reset(); super.tearDown() }

    // MARK: the apex table

    /// Starts `move` on a standing Jelbie (no bubble) and measures the crown's peak above its standing height.
    func measureApex(_ move: BubblePopMove) -> (rise: Float, dist: Float)? {
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        let r = MotionRig(game: true, settle: 0.5)
        r.brain.autonomy = true; r.brain.anticsEnabled = true
        if move == .flap { r.brain.feature = .wings }
        r.sim.teleport(toXZ: SIMD2(0, 0.5)); r.run(0.6)
        let crown0 = r.sim.centroid().y + BobShape.H * 0.5
        let from = r.brain.position
        let ok: Bool
        switch move {
        case .header: ok = r.brain.bubbleHeaderHop(r.sim)
        case .leap: ok = r.brain.bubbleLeap(r.sim, distance: 0.6)
        case .bounce: ok = r.brain.bubbleBounce(r.sim)
        case .flap: ok = r.brain.bubbleFlap(r.sim)
        case .skip: ok = r.brain.bubbleSkip(r.sim)
        }
        guard ok else { return nil }
        var peak = crown0
        for i in 0..<300 {
            r.tick()
            peak = max(peak, r.sim.centroid().y + BobShape.H * 0.5)
            if i > 10, !r.brain.bubbleHopBusy, r.brain.idleState.kind == nil, r.brain.scriptIsNone { break }
        }
        _ = crown0
        return (peak - crown0, simd_distance(from, r.brain.position))
    }

    func testApexTable() {
        var lines = "BUBBLE APEX move | measured crown rise | table | travelled\n"
        for m in BubblePopMove.allCases {
            guard let a = measureApex(m) else { XCTFail("\(m) did not start"); continue }
            let t = BubbleTuning.apex[m] ?? 0
            lines += String(format: "%@ | %.3f | %.3f | %.2f\n", m.rawValue, a.rise, t, a.dist)
            XCTAssertEqual(a.rise, t, accuracy: 0.04, "the apex table is off for \(m): measured \(a.rise), table \(t)")
        }
        print(lines)
    }

    // MARK: before / after

    struct Run {
        var seconds: Float = 0, hopPops = 0, pops = 0, chases = 0, chasePops = 0, jumps = 0, bubblePops = 0, dup = 0, outside = 0, contact = 0, popped = 0
        var claimToPop: [Float] = [], walkShare: [Float] = []
        var moves: [BubblePopMove: Int] = [:]
        var extra = 0
    }

    nonisolated(unsafe) static var clockBase = 90_000.0
    func play(classic: Bool, seed: Int, size: CGSize, winged: Bool = true, trace: Float = 0, seconds: Int = 60, force: BubblePopMove? = nil) -> Run {
        BubbleTuning.classic = classic
        wand.resetForTests(); BubbleTuning.classic = classic; BubbleTuning.forceMove = force
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: Float(size.width / size.height))
        let spots: [SIMD2<Float>] = [SIMD2(-1.6, 0.2), SIMD2(0, 1.4), SIMD2(1.6, 0.2)]
        let rs: [MotionRig] = spots.enumerated().map { i, s in
            let r = MotionRig(game: true, settle: 0.5)
            r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = UInt64(seed * 31 + i * 7 + 5)
            if winged && i == 2 { r.brain.feature = .wings }
            r.sim.teleport(toXZ: s); r.run(0.3)
            return r
        }
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        Self.clockBase += 1000; var now = Self.clockBase; AudioHub.clock = { now }
        var played: [String: Int] = [:]
        var reasons: [String: Int] = [:]
        AudioHub.dropTap = { what, why in if why == nil { played[what, default: 0] += 1 }; if what == "play:bubblewand_pop" { reasons[why ?? "PLAYED", default: 0] += 1 } }
        defer { AudioHub.dropTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() } }
        wand.viewSize = size
        wand.activate(care: nil)
        wand.demo = { _ in 0.7 }          // (a steady stream: what holding the wand gives)
        var steps = 0, run = Run()
        let js = rs.enumerated().map { BubbleJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim) }
        for _ in 0..<(60 * seconds) {
            for r in rs { r.tick() }
            wand.tick(jellies: js, dt: 1.0 / 60)
            now += 1.0 / 60; steps += 1
            if trace > 0, steps % 30 == 0, Float(steps) / 60 < trace { print("TRACE t=\(Float(steps) / 60) " + wand.debugLine(js)) }
            let t = wand.activeTargets
            if Set(t).count != t.count { run.dup += 1 }
            if steps > 60 * 4 { for r in rs where !(r.brain.bubbleLeash?.contains(r.brain.position, margin: 1.2) ?? true) { run.outside += 1 } }
        }
        run.seconds = Float(steps) / 60
        run.hopPops = wand.hopPops; run.pops = wand.popsByJelly.values.reduce(0, +); run.chases = wand.chaseRecords.count
        run.chasePops = wand.chaseRecords.filter(\.popped).count
        run.claimToPop = wand.claimToPop; run.walkShare = wand.chaseRecords.filter { $0.seconds > 0.5 }.map { $0.walking / $0.seconds }
        run.moves = wand.movePops; run.extra = wand.extraPops; run.contact = wand.contactPops; run.popped = wand.field.popped
        if trace > 0 { print("TRACE played \(played.sorted { $0.key < $1.key })\nTRACE log \(wand.log.joined(separator: " ; "))") }
        print("DIAG \(classic ? "classic" : "new") \(wand.diag.sorted { $0.key < $1.key })")
        print("POPSND \(classic ? "classic" : "new") seed \(seed) spawned \(wand.field.spawned) popped \(wand.field.popped) by jelbies \(run.pops) bubblewand_pop reasons \(reasons)")
        run.jumps = played["play:jump"] ?? 0; run.bubblePops = played["play:bubblewand_pop"] ?? 0
        wand.deactivate()
        return run
    }

    /// Each move, forced, in the real stream: it pops at least once in 40 s (so no move is dead code).
    func testEachMovePops() {
        for m in BubblePopMove.allCases {
            let r = play(classic: false, seed: 11, size: CGSize(width: 440, height: 956), seconds: 40, force: m)
            print("FORCED \(m.rawValue): pops by move \(r.moves.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }) chases \(r.chases) ended in a pop \(r.chasePops)")
            XCTAssertGreaterThanOrEqual(r.moves[m] ?? 0, 1, "forced move \(m) never popped a bubble in 40 s")
        }
    }
    func median(_ a: [Float]) -> Float { a.isEmpty ? 0 : a.sorted()[a.count / 2] }

    func testBeforeAfter() {
        let sizes: [(String, CGSize)] = [("portrait", CGSize(width: 440, height: 956)), ("landscape", CGSize(width: 956, height: 440))]
        var before: [Run] = [], after: [Run] = []
        for k in 0..<8 {          // (4 portrait, 4 landscape)
            let size = sizes[k < 4 ? 0 : 1].1
            before.append(play(classic: true, seed: k, size: size))
            after.append(play(classic: false, seed: k, size: size))
        }
        func sum(_ r: [Run], _ f: (Run) -> Int) -> Int { r.reduce(0) { $0 + f($1) } }
        func minutes(_ r: [Run]) -> Float { r.reduce(0) { $0 + $1.seconds } / 60 }
        func row(_ name: String, _ r: [Run]) -> String {
            let hp = Float(sum(r) { $0.hopPops }) / minutes(r)
            let chases = sum(r) { $0.chases }, cp = sum(r) { $0.chasePops }
            let c2p = median(r.flatMap(\.claimToPop)), walk = median(r.flatMap(\.walkShare))
            return String(format: "%@ | runs %d (%.0f sim-s) | hop-pops/min %.2f | chases %d, ended in a pop %d (%.0f %%) | median claim->pop %.2f s | walking share of chase %.0f %% | jump plays/min %.1f | bubblePop plays/min %.1f | contact pops %d | dup %d | outside frames %d",
                          name, r.count, r.reduce(0) { $0 + $1.seconds }, hp, chases, cp, 100 * Float(cp) / Float(max(chases, 1)), c2p, 100 * walk,
                          Float(sum(r) { $0.jumps }) / minutes(r), Float(sum(r) { $0.bubblePops }) / minutes(r), sum(r) { $0.contact }, sum(r) { $0.dup }, sum(r) { $0.outside })
        }
        var moves: [BubblePopMove: Int] = [:]
        for r in after { for (m, n) in r.moves { moves[m, default: 0] += n } }
        print("BUBBLEPLAY BEFORE: " + row("classic", before))
        print("BUBBLEPLAY AFTER:  " + row("new", after))
        print("BUBBLEPLAY AFTER pops per move \(moves.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }) extra bounce pops \(sum(after) { $0.extra })")
        for r in before + after { XCTAssertGreaterThan(r.seconds, 59.9, "the sim did not run its 60 s") }
        let hpB = Float(sum(before) { $0.hopPops }) / minutes(before), hpA = Float(sum(after) { $0.hopPops }) / minutes(after)
        XCTAssertGreaterThanOrEqual(hpA, 2 * hpB, "hop-pops per minute must at least double: \(hpB) -> \(hpA)")
        let chases = sum(after) { $0.chases }, cp = sum(after) { $0.chasePops }
        XCTAssertGreaterThanOrEqual(Float(cp) / Float(max(chases, 1)), 0.6, "chases that end in a pop: \(cp)/\(chases)")
        XCTAssertEqual(sum(after) { $0.dup }, 0, "two Jelmiko on the same bubble")
        XCTAssertEqual(sum(after) { $0.outside }, 0, "a Jelmiko left the play area")
        XCTAssertGreaterThan(sum(after) { $0.popped } - sum(after) { $0.pops }, 0, "some bubbles still pop without a Jelmiko")
        for m in BubblePopMove.allCases { XCTAssertGreaterThanOrEqual(moves[m] ?? 0, 1, "move \(m) was never used to pop") }
    }
}
