//
//  RestMoreTests.swift
//  rest-more-r1: the occasional sit / lie in place (BobV1/Melon/RestMore.swift). Headless 3-body room, hour pinned to 14.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RestMoreTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var savedOn = true
    override func setUp() {
        savedOn = RestMore.on
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        DayClock.shared.forcedHour = 14
    }
    override func tearDown() {
        RestMore.on = savedOn; DayClock.shared.forcedHour = nil
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    struct Soak { var restFrames = [Int](repeating: 0, count: 3), frames = 0, maxAtOnce = 0, twoAtOnce = 0, starts = 0, socials = 0, solo = 0
                  var holds: [Float] = [] }

    /// 3 bodies, the home life as the stage runs it (antics, watching, a sleep table that stays off in the daytime), `seconds` of game time.
    private func soak(seed: UInt64, seconds: Int, home: Bool = true) -> Soak {
        let lab = SocialTests.Lab(quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            let b = r.brain
            b.idleMood = .okay; b.anticsEnabled = true; b.watching = true; b.sleepEnabled = true; b.homeRoom = home
            b.socialBook.cooldown = 8; b.idleState.cooldown = 3; b.restTimer = 0.5 + Float(i)
        }
        var s = Soak(), wasResting = [Bool](repeating: false, count: 3), start = [Float](repeating: 0, count: 3)
        var prevKind = [IdleKind?](repeating: nil, count: 3)
        for _ in 0..<(60 * seconds) {
            lab.tick(watching: false)
            s.frames += 1
            var n = 0
            for (i, r) in lab.rigs.enumerated() {
                let on = r.brain.restSlotOn
                if on { s.restFrames[i] += 1; n += 1 }
                if on && !wasResting[i] { s.starts += 1; start[i] = lab.rigs[0].t }
                if !on && wasResting[i] { s.holds.append(lab.rigs[0].t - start[i]) }
                wasResting[i] = on
                let k = r.brain.social == nil && r.brain.idleState.reaction == nil && r.brain.idleState.resume == nil ? r.brain.idleState.kind : nil
                if let k, k != prevKind[i], !r.brain.idleState.restSlot, Self.soloEmotes.contains(k) { s.solo += 1 }
                prevKind[i] = k
            }
            s.maxAtOnce = max(s.maxAtOnce, n); if n >= 2 { s.twoAtOnce += 1 }
        }
        s.socials = lab.events.reduce(0) { $0 + $1.filter { if case .began = $0 { return true }; return false }.count } / 2
        return s
    }
    static let soloEmotes: Set<IdleKind> = [.jacks, .bounce, .tail, .stretch, .shake, .chirp, .hiccup, .sneeze, .dizzyWobble, .politeBow, .bellyDrum, .signatureFlourish, .tailThump, .tailHug, .window, .peek, .skipHop, .hopscotch, .legSpin, .trot, .joy]

    /// The switch off (or a room that is not home) is exactly today: no slot rest, and the same picks (no random draw, no hook).
    func testSwitchOffAndAwayFromHomeAreToday() {
        RestMore.on = false
        let a = soak(seed: 21, seconds: 200, home: false)
        let a2 = soak(seed: 21, seconds: 120)
        RestMore.on = true
        let b = soak(seed: 21, seconds: 200, home: false)
        XCTAssertEqual(a.starts, 0); XCTAssertEqual(b.starts, 0); XCTAssertEqual(a2.starts, 0, "switch off at home: no slot rest")
        XCTAssertEqual(a.socials, b.socials, "same seeded social count"); XCTAssertEqual(a.solo, b.solo, "same seeded solo count")
    }

    /// A real share, light: about 8-12 % of the time per body, never all three, rests of 6...15 s (+ get-up), emotes / moments >= 90 % of off.
    func testRestShareIsLightAndEverythingElseStays() {
        var on = Soak(), off = Soak(), offRest = 0.0, onRest = 0.0
        var shares: [Double] = []
        for seed in [1, 2, 3] as [UInt64] {
            RestMore.on = false; let o = soak(seed: seed, seconds: 400)
            RestMore.on = true; let n = soak(seed: seed, seconds: 400)
            on.starts += n.starts; on.socials += n.socials; on.solo += n.solo; on.maxAtOnce = max(on.maxAtOnce, n.maxAtOnce); on.twoAtOnce += n.twoAtOnce; on.holds += n.holds; on.frames += n.frames
            off.socials += o.socials; off.solo += o.solo
            for i in 0..<3 { onRest += Double(n.restFrames[i]); shares.append(Double(n.restFrames[i]) / Double(n.frames)) }
            offRest += Double(o.restFrames.reduce(0, +))
        }
        let share = onRest / Double(on.frames * 3)
        MotionLog.write(String(format: "RESTMORE soak 3x400 s: slot rest share %.3f per body (per body %@), starts %d, holds mean %.1f s, max at once %d (two at once %d frames), socials on %d / off %d, solo emotes on %d / off %d",
                               share, shares.map { String(format: "%.3f", $0) }.joined(separator: " "), on.starts, on.holds.reduce(0, +) / Float(max(on.holds.count, 1)), on.maxAtOnce, on.twoAtOnce, on.socials, off.socials, on.solo, off.solo))
        XCTAssertEqual(offRest, 0)
        XCTAssertGreaterThan(share, 0.03, "a real share (the table's own sits / lies come on top)"); XCTAssertLessThan(share, 0.16, "a light share")
        XCTAssertEqual(on.maxAtOnce, 1, "never two (so never all three) at once")
        XCTAssertGreaterThan(on.holds.reduce(0, +) / Float(max(on.holds.count, 1)), 6, "a rest lasts (a few are cut short by a moment's invite)")
        XCTAssertLessThan(on.holds.max() ?? 99, 22, "a rest ends")
        XCTAssertGreaterThanOrEqual(Double(on.socials), 0.9 * Double(off.socials), "pair / group moments keep 90 %")
        XCTAssertGreaterThanOrEqual(Double(on.solo), 0.9 * Double(off.solo), "solo emotes keep 90 %")
    }

    private func restingRig(_ lab: SocialTests.Lab, _ i: Int) {
        let r = lab.rigs[i]
        r.brain.anticsEnabled = true; r.brain.homeRoom = true; r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sit, r.sim))
        r.brain.idleState.restSlot = true; r.brain.idleState.hold = 12
        for _ in 0..<150 { lab.tick(watching: false) }
        XCTAssertTrue(r.brain.restSlotOn, "settled in a rest")
    }

    /// A rester gets up for a call and for a meal within 0.3 s, like the table's own sit.
    func testResterGetsUpForCallAndMeal() {
        for mode in ["come", "feed"] {
            let lab = SocialTests.Lab(quiet: true, seed: 5)
            restingRig(lab, 0)
            let r = lab.rigs[0]
            let t0 = r.t
            if mode == "come" { r.brain.request(.come(to: SIMD2(0, 1.4))) } else { r.brain.requestNow(.eat(at: SIMD2(0.8, -0.2))) }
            var out: Float?
            for _ in 0..<40 { lab.tick(watching: false); if r.brain.idleState.kind == nil && out == nil { out = r.t - t0 } }
            XCTAssertNotNil(out, mode); XCTAssertLessThanOrEqual(out ?? 9, 0.35, "\(mode): up within 0.35 s")
            XCTAssertFalse(r.brain.idleState.restSlot)
        }
    }

    /// A pair move asks the rester: he gets up first and the move starts with him.
    func testResterJoinsAPairMoment() {
        SocialTuning.pickChance = 1
        let lab = SocialTests.Lab(quiet: false, seed: 9)
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.homeRoom = true; r.brain.idleForced = true; r.brain.sleepEnabled = false }
        for i in 1...2 { lab.rigs[i].brain.idleState.restArmed = true; lab.rigs[i].brain.idleState.restUrge = 1e9 }          // (only rig 0 rests)
        restingRig(lab, 0)
        lab.rigs[1].brain.socialBook.cooldown = 0; lab.rigs[2].brain.socialBook.cooldown = 0
        var began: Float?, upBefore = false, rested = 0
        let t0 = lab.rigs[0].t
        for _ in 0..<(60 * 20) {
            lab.tick(watching: false)
            let b = lab.rigs[0].brain
            if b.restSlotOn { rested += 1 }
            if b.social != nil, began == nil { began = lab.rigs[0].t - t0; upBefore = b.idleState.kind != .sit && b.idleState.kind != .lieDown && rested > 0 }
        }
        MotionLog.write("RESTMORE pair join: began after \(began ?? -1) s, stood up first \(upBefore)")
        XCTAssertNotNil(began, "the rester takes part in a moment within 20 s"); XCTAssertTrue(upBefore)
    }
}
