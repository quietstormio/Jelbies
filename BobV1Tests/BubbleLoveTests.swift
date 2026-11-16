//
//  BubbleLoveTests.swift
//  "When you play bubbles the heart status love goes up" (2026-11-11). Bubble pops feed the attention meter (`BlobNeeds.gain(.attention, BubbleTuning.attentionPerPop)`): Bob alone, 20 s of a steady
//  blow with the wand (the meter rises), 20 s with no bubbles (it does not), and the gain per minute stays under what petting pays (`NeedsTuning.petRate`, 3 a minute).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BubbleLoveTests: XCTestCase {
    var wand: BubbleWand { BubbleWand.shared }
    override func setUp() { super.setUp(); wand.resetForTests(); EmoteFeetTests.reset() }
    override func tearDown() { wand.resetForTests(); EmoteFeetTests.reset(); super.tearDown() }

    func play(seconds: Int, blow: Bool) -> (start: Float, end: Float, pops: Int) {
        wand.resetForTests()
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let size = CGSize(width: 440, height: 956)
        _ = GameCamera.camera(aspect: Float(size.width / size.height))
        let care = GameCare(jellyCount: 1, persistent: false)
        let r = MotionRig(game: true, settle: 0.5)
        r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = 11
        r.sim.teleport(toXZ: SIMD2(0, 1.0)); r.run(0.3)
        AudioHub.shared._openForTest(); AudioHub.dryRun = true
        BubblePlayTests.clockBase += 1000; var now = BubblePlayTests.clockBase; AudioHub.clock = { now }
        defer { AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() } }
        wand.viewSize = size
        wand.begin(care: care)
        if blow { wand.demo = { _ in 0.7 } }
        let needs = care.needs(for: 0)
        needs.set(.attention, 0.2)
        let start = needs.level(.attention)
        let js = [BubbleJelly(id: 0, brain: r.brain, sim: r.sim)]
        for _ in 0..<(60 * seconds) { r.tick(); wand.tick(jellies: js, dt: 1.0 / 60); now += 1.0 / 60 }
        let o = (start, needs.level(.attention), wand.popsByJelly[0] ?? 0)
        wand.deactivate()
        return o
    }

    func testMeterRisesWithPops() {
        let o = play(seconds: 20, blow: true)
        print("BUBBLELOVE 20 s with pops: attention \(o.start) -> \(o.end), pops \(o.pops)")
        XCTAssertGreaterThanOrEqual(o.pops, 3, "the play popped bubbles")
        XCTAssertGreaterThan(o.end, o.start + 0.1, "the love meter rose during 20 s of bubble play with pops")
    }

    func testMeterStaysWithoutPops() {
        let o = play(seconds: 20, blow: false)
        XCTAssertEqual(o.pops, 0)
        XCTAssertLessThanOrEqual(o.end, o.start + 0.001, "the love meter did not rise with no pops")
    }

    /// Per minute: under petting (0.05 / s = 3 a minute).
    func testGainPerMinuteUnderPetting() {
        let o = play(seconds: 60, blow: true)
        let perMin = o.end - o.start
        print(String(format: "BUBBLELOVE 60 s: gained %.2f (petting %.2f), pops %d", perMin, NeedsTuning.petRate * 60, o.pops))
        XCTAssertLessThanOrEqual(perMin, NeedsTuning.petRate * 60, "bubbles do not out-pay petting")
        XCTAssertGreaterThan(perMin, 0.3, "a real gain")
    }
}
