//
//  BubbleFeetTests.swift
//  Feet stay attached in the bubble wand's moves (docs/HANDOFF.md "Feet stay attached"): the look-up stance (the turn-and-watch), the walk under a bubble and the
//  hop that pops it, and the real wand driving a Jelbie through a blown stream for 24 s. Each runs for all 6 characters, bare and with shoes, and asserts in every frame
//  what EmoteFeetTests does: no leash / tether frames (the runtime guard in OnePieceInvariantTests.run), the neck ring >= 70 % of standing and the join >= 1 cm inside
//  the body whenever both pieces are off the floor, the collar <= 2 cm; plus: no tilt over 0.5 rad. The wand adds no new IdleKind: its moves are the existing look,
//  walk, bounce and skipHop (so EmoteFeetTests' auto-coverage already holds them).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BubbleFeetTests: XCTestCase {
    override func setUp() { super.setUp(); EmoteFeetTests.reset(); BubbleWand.shared.resetForTests() }
    override func tearDown() { BubbleWand.shared.resetForTests(); EmoteFeetTests.reset(); super.tearDown() }

    static let out = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/bubbles/"
    typealias SC = LegsDrawnAuditTests.Scenario

    static func scenario(_ name: String) -> SC {
        var n = 0
        let wand = BubbleWand.shared
        func join(_ r: MotionRig) -> [BubbleJelly] { [BubbleJelly(id: 0, brain: r.brain, sim: r.sim)] }
        switch name {
        case "look up":          // the turn-and-watch toward a bubble, again and again
            return SC(name: "bubble: look up", game: true, seconds: 9, setup: { r, _ in n = 0; r.brain.autonomy = true; r.brain.anticsEnabled = true; return true }, each: { r in
                n += 1
                if n % 150 == 20, r.brain.bubbleFree { _ = r.brain.bubbleWatch(r.brain.position + SIMD2(0.9 * (n % 300 == 20 ? 1 : -1), -1.5), hold: 1.6, excited: n % 300 == 20) }
            })
        case "hop pop":          // walk under a bubble, hop, pop it (forced chase of a bubble put in front of him)
            return SC(name: "bubble: walk under and hop", game: true, seconds: 14, setup: { r, _ in
                n = 0; wand.resetForTests(); r.brain.autonomy = true; r.brain.anticsEnabled = true; wand.activate(care: nil); return true
            }, each: { r in
                n += 1
                if n % 360 == 30 { let c = r.brain.position; _ = wand.insertBubble(at: SIMD3(c.x + 1.3, 1.3, c.y - 0.9), radius: 0.25) }
                wand.tick(jellies: join(r), dt: r.sim.stepDt)
                if n % 360 == 31, let b = wand.field.bubbles.first { _ = b }
            })
        case "stream":           // the real wand: a steady blow, the Jelbie watches / chases / pops as he likes
            return SC(name: "bubble: stream", game: true, seconds: 24, setup: { r, _ in
                n = 0; wand.resetForTests(); r.brain.autonomy = true; r.brain.anticsEnabled = true; wand.activate(care: nil); wand.demo = { _ in 0.8 }; return true
            }, each: { r in n += 1; wand.tick(jellies: join(r), dt: r.sim.stepDt) })
        default: fatalError(name)
        }
    }

    @discardableResult
    func bubbles(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        var report = String(format: "BUBBLE %@\nchar shoes | frames | leash frames | airborne frames | min ring ratio | worst join (cm; need >= 1) | max collar (cm; need <= 2) | max tilt (rad; need <= 0.5) | pops\n", name)
        for c in 0..<OnePieceInvariantTests.characters.count {
            for shoes in [false, true] {
                var air = 0, badFrame = -1, badInfo = "", tiltMax: Float = 0, leashFrame = -1
                var worst: (ratio: Float, join: Float, collar: Float) = (.infinity, .infinity, 0)
                let a = OnePieceInvariantTests.run(Self.scenario(name), char: c, shoes: shoes, pacing: .hz60, seed: 3) { frame, r, f in
                    tiltMax = max(tiltMax, f.tilt)
                    if leashFrame < 0, f.beans, f.leash > 0.002 || f.weldPull > 0.002 { leashFrame = frame }
                    guard let s = EmoteFeetTests.sample(r, frame: frame) else { return }
                    air += 1
                    if (s.ratio < EmoteFeetTests.minRatio || s.join < OnePieceInvariantTests.minNeck || s.collar > EmoteFeetTests.maxCollar) && badFrame < 0 { badFrame = frame; badInfo = s.info }
                    worst = (min(worst.ratio, s.ratio), min(worst.join, s.join), max(worst.collar, s.collar))
                }
                let who = "bubble \(name), \(OnePieceInvariantTests.characters[c].0) \(shoes ? "with shoes" : "bare")"
                guard a.started else { XCTFail("\(who): did not start", file: file, line: line); continue }
                let pops = BubbleWand.shared.popsByJelly.values.reduce(0, +)
                report += String(format: "%@ %@ | %d | %d | %d | %.2f | %.1f | %.1f | %.3f | %d\n", OnePieceInvariantTests.characters[c].0, shoes ? "shoes" : "bare", a.frames, a.leashed, air, worst.ratio, worst.join * 100, worst.collar * 100, tiltMax, pops)
                XCTAssertEqual(a.leashed, 0, "\(who): the leash / tether moved a foot piece in \(a.leashed) frames, first at frame \(leashFrame), max pull \(String(format: "%.1f", a.leashMax * 100)) cm", file: file, line: line)
                XCTAssertEqual(a.detached, 0, "\(who): a foot came off the body in \(a.detached) frames (worst leg sdf \(a.worstLeg))", file: file, line: line)
                XCTAssertEqual(a.neckBad, 0, "\(who): the neck join is open in \(a.neckBad) frames", file: file, line: line)
                XCTAssertLessThanOrEqual(tiltMax, 0.5, "\(who): the body tipped \(tiltMax) rad (limit 0.5)", file: file, line: line)
                if air > 0 {
                    XCTAssertGreaterThanOrEqual(worst.ratio, EmoteFeetTests.minRatio, "\(who): the neck ring shrank to \(String(format: "%.0f", worst.ratio * 100)) % of standing (first bad frame \(badFrame): \(badInfo))", file: file, line: line)
                    XCTAssertGreaterThanOrEqual(worst.join, OnePieceInvariantTests.minNeck, "\(who): the join is open: \(String(format: "%.1f", -worst.join * 100)) cm outside the body (first bad frame \(badFrame): \(badInfo))", file: file, line: line)
                    XCTAssertLessThanOrEqual(worst.collar, EmoteFeetTests.maxCollar, "\(who): the collar moved the skin \(String(format: "%.1f", worst.collar * 100)) cm (first bad frame \(badFrame): \(badInfo))", file: file, line: line)
                }
            }
        }
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? report.write(toFile: Self.out + "feet_bubble_\(name.replacingOccurrences(of: " ", with: "_")).txt", atomically: true, encoding: .utf8)
        return true
    }

    func testLookUp() { bubbles("look up") }
    func testWalkUnderAndHopPop() { bubbles("hop pop") }
    func testStream() { bubbles("stream") }
}
