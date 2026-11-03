//
//  BubbleWandTests.swift
//  The bubble wand: not in the picker until owned, the spawn cap, bubbles that pop on their own, pop on contact, Jelbies that chase some bubbles but not all
//  (and pop with a hop), tap-and-hold when the mic is not there, putting the wand away clears the bubbles, and the cost of drawing 40 bubbles.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BubbleWandTests: XCTestCase {
    var wand: BubbleWand { BubbleWand.shared }
    override func setUp() { super.setUp(); wand.resetForTests(); EmoteFeetTests.reset() }
    override func tearDown() { wand.resetForTests(); EmoteFeetTests.reset(); super.tearDown() }

    // MARK: store / picker

    func testNotInThePickerUntilOwned() {
        PlayToyRegistry.registerBuiltIns()
        let wallet = DropsWallet(persists: false)
        let book = StoreBook(wallet: wallet, persists: false, defaults: UserDefaults(suiteName: "bw.test.\(UUID())")!)
        XCTAssertNotNil(PlayToyRegistry.toy("bubbleWand"), "the wand is registered with ONE entry")
        XCTAssertFalse(PlayToyRegistry.offered(book: book).contains { $0.toyID == "bubbleWand" })
        XCTAssertEqual(book.buyToy("bubbleWand", price: BubbleTuning.price), .notEnough)
        XCTAssertFalse(PlayToyRegistry.offered(book: book).contains { $0.toyID == "bubbleWand" }, "a failed purchase owns nothing")
        wallet.add(BubbleTuning.price + 5, silent: true)
        XCTAssertEqual(book.buyToy("bubbleWand", price: BubbleTuning.price), .bought)
        XCTAssertEqual(wallet.count, 5)
        XCTAssertTrue(PlayToyRegistry.offered(book: book).contains { $0.toyID == "bubbleWand" })
        XCTAssertEqual(book.buyToy("bubbleWand", price: BubbleTuning.price), .alreadyOwned)
        XCTAssertEqual(wallet.count, 5, "never charged twice")
    }

    // MARK: the field

    func testSpawnCap() {
        var f = BubbleField()
        for _ in 0..<200 { f.spawn(strength: 0.8, at: SIMD3(0, 0.3, 4)) }
        XCTAssertEqual(f.bubbles.count, BubbleField.cap)
        XCTAssertFalse(f.spawn(strength: 1, at: .zero))
    }

    func testBubblesPopByThemselvesAndStayInTheRoom() {
        var f = BubbleField()
        for _ in 0..<30 { f.spawn(strength: 0.6, at: SIMD3(0, 0.3, 4)) }
        var gone = 0
        for _ in 0..<(60 * 9) {
            gone += f.step(dt: 1.0 / 60).count
            for b in f.bubbles { XCTAssertLessThan(b.pos.y, BubbleField.ceiling + 0.2); XCTAssertGreaterThan(b.pos.y, 0.1) }
        }
        XCTAssertEqual(gone, 30)
        XCTAssertTrue(f.bubbles.isEmpty)
    }

    // MARK: the wand

    /// Wand + n Jelbies at spots (the rig's brains, ticked like the stage).
    func rigs(_ spots: [SIMD2<Float>]) -> [MotionRig] {
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        return spots.map { s in
            let r = MotionRig(game: true, settle: 0.5)
            r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = UInt64(abs(s.x * 100)) + 5
            r.sim.teleport(toXZ: s)
            r.run(0.3)
            return r
        }
    }
    func step(_ rs: [MotionRig], seconds: Float) {
        for _ in 0..<Int(seconds * 60) {
            for r in rs { r.tick() }
            wand.tick(jellies: rs.enumerated().map { BubbleJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim) }, dt: 1.0 / 60)
        }
    }

    func testPopOnContact() {
        let rs = rigs([SIMD2(0, 0.5)])
        wand.activate(care: nil)
        BubbleTuning.contactPopChance = 1
        let c = rs[0].brain.position
        let id = wand.insertBubble(at: SIMD3(c.x, 1.0, c.y))
        XCTAssertNotNil(id)
        XCTAssertEqual(wand.field.bubbles.count, 1)
        wand.tick(jellies: [BubbleJelly(id: 0, brain: rs[0].brain, sim: rs[0].sim)], dt: 1.0 / 60)
        XCTAssertTrue(wand.field.bubbles.isEmpty, "a bubble at his body pops")
        XCTAssertEqual(wand.contactPops, 1)
        XCTAssertEqual(wand.popsByJelly[0], 1)
        // with less than a sure pop he is only nudged, once
        BubbleTuning.contactPopChance = 0
        let id2 = wand.insertBubble(at: SIMD3(c.x, 1.0, c.y))
        wand.tick(jellies: [BubbleJelly(id: 0, brain: rs[0].brain, sim: rs[0].sim)], dt: 1.0 / 60)
        XCTAssertEqual(wand.field.bubbles.count, 1)
        XCTAssertEqual(wand.field.bubble(id2 ?? -1)?.touched, true)
        XCTAssertEqual(wand.nudges, 1)
        wand.clearBubbles()
        // one far away and high stays
        _ = wand.insertBubble(at: SIMD3(c.x + 3, 2.0, c.y - 2))
        wand.tick(jellies: [BubbleJelly(id: 0, brain: rs[0].brain, sim: rs[0].sim)], dt: 1.0 / 60)
        XCTAssertEqual(wand.field.bubbles.count, 1)
    }

    func testTapAndHoldBlowsWithoutAMic() {
        let rs = rigs([SIMD2(-1.5, 0)])
        wand.activate(care: nil)
        XCTAssertTrue(wand.micUnavailable, "no engine under XCTest: the wand says hold to blow")
        step(rs, seconds: 0.5)
        XCTAssertEqual(wand.field.spawned, 0, "no blowing, no bubbles")
        wand.holding = true
        step(rs, seconds: 1.5)
        XCTAssertGreaterThan(wand.field.spawned, 5, "holding the wand streams bubbles")
        XCTAssertGreaterThan(wand.strength, 0.3)
        let n = wand.field.spawned
        wand.holding = false
        step(rs, seconds: 0.5)
        XCTAssertEqual(wand.field.spawned, n, "letting go stops the stream")
        // VoiceOver: a burst without holding
        wand.burst(seconds: 1)
        step(rs, seconds: 0.8)
        XCTAssertGreaterThan(wand.field.spawned, n)
    }

    func testJelbiesChaseSomeButNotAll() {
        let rs = rigs([SIMD2(-1.6, 0.2), SIMD2(0, 1.4), SIMD2(1.6, 0.2)])
        wand.activate(care: nil)
        wand.demo = { _ in 0.7 }
        step(rs, seconds: 30)
        let jellyPops = wand.popsByJelly.values.reduce(0, +)
        let total = wand.field.popped
        print("BUBBLES spawned \(wand.field.spawned) popped \(total) by Jelbies \(jellyPops) (contact \(wand.contactPops), hops \(wand.hopPops), nudged \(wand.nudges)) chases \(wand.chases) watches \(wand.watches) bumps \(wand.bumps) hearts \(wand.heartBursts) per jelly \(wand.popsByJelly)")
        print("BUBBLES log:\n" + wand.log.prefix(60).joined(separator: "\n"))
        XCTAssertLessThanOrEqual(wand.field.bubbles.count, BubbleField.cap)
        XCTAssertGreaterThan(wand.chases, 0, "they chase")
        XCTAssertGreaterThan(jellyPops, 0, "they pop some")
        XCTAssertGreaterThan(wand.hopPops, 0, "at least one is popped by a hop")
        XCTAssertGreaterThan(wand.watches, 0, "some are only watched")
        XCTAssertGreaterThan(total, jellyPops, "not every bubble is popped by a Jelbie: some float on until they pop alone")
    }

    func testPuttingTheWandAwayClearsEverything() {
        let rs = rigs([SIMD2(0, 0.5)])
        wand.activate(care: nil)
        wand.holding = true
        step(rs, seconds: 1.2)
        XCTAssertFalse(wand.field.bubbles.isEmpty)
        XCTAssertTrue(wand.active)
        wand.deactivate()
        XCTAssertFalse(wand.active)
        XCTAssertTrue(wand.field.bubbles.isEmpty)
        XCTAssertTrue(wand.fx.isEmpty)
        XCTAssertFalse(wand.holding)
        let n = wand.field.spawned
        step(rs, seconds: 1)
        XCTAssertEqual(wand.field.spawned, n, "a put-away wand does nothing")
    }

    // MARK: cost

    func testDrawingFortyBubblesIsCheap() {
        wand.activate(care: nil)
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        for i in 0..<BubbleField.cap { _ = wand.insertBubble(at: SIMD3(Float(i % 8) * 0.6 - 2.1, 0.5 + Float(i / 8) * 0.4, Float(i % 5) - 1), radius: 0.25) }
        XCTAssertEqual(wand.field.bubbles.count, 40)
        let v = BubbleLayerView(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        v.step()
        BubbleWand.drawCostSum = 0; BubbleWand.drawCostN = 0
        let t0 = CACurrentMediaTime()
        for _ in 0..<500 { v.step() }
        let ms = (CACurrentMediaTime() - t0) / 500 * 1000
        print("BUBBLE DRAW 40 bubbles: \(String(format: "%.4f", ms)) ms per frame (CPU, layer updates)")
        XCTAssertLessThan(ms, 0.5)
    }
}
