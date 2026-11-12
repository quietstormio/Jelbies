//
//  BubbleLoveTests.swift
//  "When you play bubbles the heart status love goes up" (2026-11-11). Bubble pops feed the existing attention meter (`BlobNeeds.gain(.attention, ...)`, the path the park love and the cafe use);
//  petting pays 0.05 / s (`NeedsTuning.petRate`), a purr 0.15 / s. Bubbles: `attentionPerPop` per pop out of a bucket refilled at `loveCapPerSecond`, a heart over him every 3 or 4 pops.
//  Run: 20 s of play with pops (the meter rises), 20 s of bubble mode with no bubbles (it does not), 60 s with pops (the gain per minute stays under petting's 3, hearts about one per 3 to 4 pops).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BubbleLoveTests: XCTestCase {
    var wand: BubbleWand { BubbleWand.shared }
    override func setUp() { super.setUp(); wand.resetForTests(); EmoteFeetTests.reset(); BubbleTuning.restoreHead() }
    override func tearDown() { BubbleTuning.seedRandom(nil); BubbleTuning.restoreHead(); wand.resetForTests(); EmoteFeetTests.reset(); super.tearDown() }

    struct Out { var start: Float; var end: Float; var gained: Float; var pops: Int; var hearts: Int }

    /// Bob alone in the room, `seconds` of bubble mode; `blow` = bubbles come out.
    func play(seconds: Int, blow: Bool, seed: UInt64 = 1) -> Out {
        wand.resetForTests(); BubbleTuning.seedRandom(seed); wand.reseedField(seed)
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let size = CGSize(width: 440, height: 956)
        _ = GameCamera.camera(aspect: Float(size.width / size.height))
        let care = GameCare(jellyCount: 1, persistent: false)
        let r = MotionRig(game: true, settle: 0.5)
        r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = 11
        r.sim.teleport(toXZ: SIMD2(0, 1.0)); r.run(0.3)
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        BubblePlayTests.clockBase += 1000; var now = BubblePlayTests.clockBase; AudioHub.clock = { now }
        defer { AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() } }
        wand.viewSize = size
        wand.begin(care: care)          // (the Optional overload: the plain one is the picker's entry and starts Play mode)
        if blow { wand.demo = { _ in 0.7 } }
        let needs = care.needs(for: 0)
        needs.set(.attention, 0.2)
        let start = needs.level(.attention)
        let js = [BubbleJelly(id: 0, brain: r.brain, sim: r.sim)]
        for _ in 0..<(60 * seconds) {
            r.tick()
            wand.tick(jellies: js, dt: 1.0 / 60)
            now += 1.0 / 60
        }
        let o = Out(start: start, end: needs.level(.attention), gained: wand.loveGained[0] ?? 0, pops: wand.popsByJelly[0] ?? 0, hearts: wand.heartBursts)
        wand.deactivate()
        return o
    }

    func testMeterRisesWithPops() {
        let o = play(seconds: 20, blow: true)
        print("BUBBLELOVE 20 s with pops: attention \(o.start) -> \(o.end), gained \(o.gained), pops \(o.pops), hearts \(o.hearts)")
        XCTAssertGreaterThan(o.pops, 5, "the play popped bubbles")
        XCTAssertGreaterThan(o.end, o.start + 0.1, "the love meter rose during 20 s of bubble play with pops")
    }

    func testMeterStaysWithoutPops() {
        let o = play(seconds: 20, blow: false)
        print("BUBBLELOVE 20 s no bubbles: attention \(o.start) -> \(o.end), pops \(o.pops)")
        XCTAssertEqual(o.pops, 0)
        XCTAssertEqual(o.gained, 0)
        XCTAssertLessThanOrEqual(o.end, o.start + 0.001, "the love meter did not rise with no pops")
    }

    /// Per minute: under petting (0.05 / s = 3 per minute), and a heart about every 3 to 4 pops (not a stream).
    func testGainPerMinuteInLineWithPetting() {
        var gain: Float = 0, pops = 0, hearts = 0
        for seed in 1...3 { let o = play(seconds: 60, blow: true, seed: UInt64(seed)); gain += o.gained; pops += o.pops; hearts += o.hearts }
        let perMin = gain / 3
        let petting = NeedsTuning.petRate * 60
        print(String(format: "BUBBLELOVE per minute: gained %.2f (cap %.2f, petting %.2f, purr %.2f) | pops/min %.1f | hearts/min %.1f | pops per heart %.1f", perMin, BubbleTuning.loveCapPerSecond * 60 + BubbleTuning.loveBucket, petting, NeedsTuning.purrRate * 60, Float(pops) / 3, Float(hearts) / 3, Float(pops) / Float(max(hearts, 1))))
        XCTAssertLessThanOrEqual(perMin, petting, "bubbles do not out-pay petting")
        XCTAssertGreaterThan(perMin, 0.3 * petting, "but it is a real gain")
        XCTAssertGreaterThanOrEqual(Float(pops) / Float(max(hearts, 1)), 3, "a heart at most every 3 pops")
        XCTAssertLessThanOrEqual(Float(pops) / Float(max(hearts, 1)), 5, "and at least every 5")
    }
}
