//
//  EmotesBatch2Tests.swift
//  Batch 2 of the emotes (g-emotes3, 2026-11-02): the spin hug (feet for 6 characters x bare / shoes, never inside each other, one turn round the shared centre, hearts, haptics), the solo / player-cued
//  moves (they start, finish, keep the tilt under 0.5 rad, play their haptic beats within +-15 %), the gates (stargazing only at night, the flop only when sleepy), the cues (tap, welcome, check-in answered
//  by a touch, the win strut) and the hearts rule (every warm social ends with a heart event for each of them).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class EmotesBatch2Tests: XCTestCase {
    override func setUp() { super.setUp(); GroupEmoteFeetTests.reset(); DayClock.shared.forcedHour = 12 }
    override func tearDown() { EmoteTreats.requestTap = nil; GroupEmoteFeetTests.reset(); DayClock.shared.forcedHour = nil; super.tearDown() }

    private func lab(n: Int = 2) -> SocialTests.Lab {
        let l = SocialTests.Lab(n: n, positions: Array(SocialTests.starts.prefix(n)), seed: 31)
        for r in l.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true }
        return l
    }

    // MARK: spin hug

    func testSpinHugKeepsFeetAndTurnsOnce() {
        let host = GroupEmoteFeetTests()
        for cast in GroupEmoteFeetTests.casts { for shoes in [false, true] {
            let r = host.run(.spinHug, cast: cast, shoes: shoes, n: 2)
            XCTAssertGreaterThan(r.seconds, 6, "the spin hug takes a while")
            XCTAssertGreaterThanOrEqual(r.minGap, 0.9, "two bodies came to \(r.minGap) (\(r.minGapTag))")
        } }
    }

    func testSpinHugGoesOnceRoundWithHearts() {
        let l = lab()
        var haptics: [String] = []
        EmoteTreats.requestTap = { haptics.append($0) }
        XCTAssertTrue(l.rigs[0].brain.socialStart(.spinHug, with: l.rigs[1].brain, l.rigs[0].sim))
        var f = 0, prev: Float?, turned: Float = 0, minGap = Float.infinity, spinning = false
        while f < 60 * 60 {
            l.tick(); f += 1
            let a = l.rigs[0].root, b = l.rigs[1].root
            if l.rigs[0].brain.social?.phase == 3 { spinning = true }
            if spinning, l.rigs[0].brain.social?.phase == 3 {
                let ang = atan2f(b.x - a.x, b.y - a.y)
                if let p = prev { turned += wrapAngle(ang - p) }
                prev = ang
                minGap = min(minGap, simd_distance(a, b))
            }
            if !l.anySocial && f > 10 { break }
        }
        XCTAssertFalse(l.anySocial)
        XCTAssertGreaterThan(abs(turned), 4.8, "they turn about once round (\(turned) rad)"); XCTAssertLessThan(abs(turned), 7.6)
        XCTAssertGreaterThanOrEqual(minGap, 0.9, "never inside each other (\(minGap)): the roots stay about a body-width apart")
        for i in 0..<2 {
            let hearts = l.events[i].filter { if case .boop = $0 { return true }; if case .makeUp = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(hearts, 2, "rig \(i) gets hearts at the press and at the parting")
        }
        XCTAssertEqual(haptics.first, "spinHug.press"); XCTAssertEqual(haptics.last, "spinHug.part"); XCTAssertTrue(haptics.contains("spinHug.step"))
    }

    // MARK: hearts

    /// Every warm kind that can start in the empty room ends with a heart event (boop / makeUp / an ended-done that the stage turns into one) for BOTH of them.
    func testEveryWarmSocialGivesBothAHeart() {
        var checked: [String] = []
        for kind in SocialKind.allCases where kind.isWarm && !kind.isGroup {
            let l = lab()
            guard l.rigs[0].brain.socialStart(kind, with: l.rigs[1].brain, l.rigs[0].sim) else { continue }
            var f = 0
            while f < 60 * 70 { l.tick(); f += 1; if !l.anySocial && f > 10 { break } }
            for i in 0..<2 {
                let warm = l.events[i].contains { e in
                    switch e { case .boop, .makeUp: return true; case .ended(_, _, let how): return how == .done; default: return false }
                }
                XCTAssertTrue(warm, "\(kind): rig \(i) got no heart event")
            }
            checked.append(kind.rawValue)
        }
        XCTAssertGreaterThan(checked.count, 15, "most warm kinds were checked: \(checked)")
    }

    func testSquabbleAndLookGiveNoHeart() {
        XCTAssertFalse(SocialKind.squabble.isWarm); XCTAssertFalse(SocialKind.look.isWarm); XCTAssertFalse(SocialKind.sneak.isWarm)
        XCTAssertTrue(SocialKind.spinHug.isWarm); XCTAssertTrue(SocialKind.highFive.isWarm)
    }

    // MARK: solo moves

    private func solo(_ kind: IdleKind, seconds: Float = 25, night: Float = 0, setup: ((MotionRig) -> Void)? = nil) -> (rig: MotionRig, ok: Bool, seconds: Float, maxTilt: Float, haptics: [String]) {
        let l = lab(n: 1)
        let r = l.rigs[0]
        r.brain.idleNight = night; r.brain.idleForced = true
        setup?(r)
        var haptics: [String] = []
        EmoteTreats.requestTap = { haptics.append($0) }
        XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind) starts")
        var f = 0, tilt: Float = 0, began = false
        while f < Int(seconds * 60) {
            l.tick(); f += 1
            tilt = max(tilt, r.sim.bodyPose(iterations: 4).tilt)
            if r.brain.idleState.kind != nil { began = true }
            if began, r.brain.idleState.kind == nil || r.brain.idleState.kind == .sleep, f > 10 { break }
        }
        return (r, r.brain.idleState.kind == nil || r.brain.idleState.kind == .sleep, Float(f) / 60, tilt, haptics)
    }

    func testSoloMovesRunAndStayUpright() {
        let cases: [(IdleKind, [String])] = [
            (.stargazing, ["stargazing.twinkle", "stargazing.sigh"]), (.proudStrut, ["proudStrut.hop"]), (.floorNapFlop, ["floorNapFlop.flop", "floorNapFlop.settle"]),
            (.tapTilt, ["tapTilt.tilt"]), (.welcomeWiggle, ["welcomeWiggle.wiggle"]), (.checkIn, ["checkIn.hello"]),
        ]
        for (kind, want) in cases {
            let r = solo(kind, night: kind == .stargazing ? 1 : 0)
            XCTAssertTrue(r.ok, "\(kind) finishes (\(r.seconds) s)")
            XCTAssertLessThanOrEqual(r.maxTilt, 0.5, "\(kind): tilt \(r.maxTilt) rad")
            for h in want { XCTAssertTrue(r.haptics.contains(h), "\(kind): haptic \(h) in \(r.haptics)") }
            for h in r.haptics { XCTAssertNotNil(EmoteTreats.haptics[h], "\(h) is in the table") }
        }
    }

    func testFlopLiesFlatThreeToSixSeconds() {
        let l = lab(n: 1)
        let r = l.rigs[0]; r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.floorNapFlop, r.sim))
        var lying: Float = 0, f = 0, maxPitch: Float = 0
        while f < 60 * 20 {
            l.tick(); f += 1
            if r.brain.idleState.kind == .floorNapFlop, r.brain.idleState.phase == 2 { lying += 1 / 60 }
            maxPitch = max(maxPitch, r.brain.pitch)
            if r.brain.idleState.kind == nil && f > 20 { break }
        }
        XCTAssertGreaterThanOrEqual(lying, 3.0); XCTAssertLessThanOrEqual(lying, 6.1)
        XCTAssertGreaterThan(maxPitch, 0.2, "he is down on his belly")
    }

    func testFlopAtBedtimeGoesStraightToSleep() {
        let l = lab(n: 1)
        let r = l.rigs[0]; r.brain.idleForced = true; r.brain.idleNight = 1; r.brain.idleDeepNight = 1
        XCTAssertTrue(r.brain.idleStart(.floorNapFlop, r.sim))
        var f = 0
        while f < 60 * 20, r.brain.idleState.kind != .sleep { l.tick(); f += 1 }
        XCTAssertEqual(r.brain.idleState.kind, .sleep, "after the flop he goes into bed")
    }

    func testHapticJitterIsWithinFifteenPercent() {
        let l = lab(n: 1)
        let b = l.rigs[0].brain
        var got: [Float] = []
        let rec = RecordingHapticSink(); let drv = HapticDriver(sinks: [rec])
        var now = 500.0
        HapticDriver.room = drv; HapticDriver.clock = { now }; HapticDriver.after = { _, f in f() }; HapticDriver.jitter = { 1 + Float.random(in: -0.15...0.15) }
        defer { HapticDriver.room = nil; HapticDriver.clock = { CACurrentMediaTime() }; HapticDriver.after = { d, f in DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { f() } } } }
        for _ in 0..<60 { now += 1; rec.clear(); b.treatHaptic("proudStrut.hop"); if let t = rec.events.first(where: { $0.kind == .transient }) { got.append(t.intensity) } }
        let base = EmoteTreats.haptics["proudStrut.hop"]![0].i
        XCTAssertEqual(got.count, 60)
        XCTAssertGreaterThanOrEqual(got.min()!, base * 0.85 - 1e-4); XCTAssertLessThanOrEqual(got.max()!, base * 1.15 + 1e-4)
        XCTAssertGreaterThan(got.max()! - got.min()!, base * 0.1, "it does vary")
        for (k, v) in EmoteTreats.haptics { for p in v { XCTAssertLessThanOrEqual(p.i, 0.4, "\(k) is soft") } }
    }

    // MARK: gates and cues

    func testStargazingOnlyAtNightAndFlopOnlyWhenSleepy() {
        let l = lab(n: 1)
        let b = l.rigs[0].brain
        b.idleNight = 0; b.idleDeepNight = 0
        XCTAssertFalse(b.treat2Night); XCTAssertFalse(b.treat2Sleepy)
        b.idleNight = 1
        XCTAssertTrue(b.treat2Night); XCTAssertTrue(b.treat2Sleepy)
        b.idleDeepNight = 1
        XCTAssertFalse(b.treat2Night, "in the deep night he is in bed, not at the window")
        let day = EmoteTreats.batch2.filter { e in b.idleNight = 0; b.idleDeepNight = 0; b.idleMood = .okay; return e.eligible(b) }.map(\.name)
        XCTAssertEqual(day, ["spinHug"], "by day with an okay mood only the spin hug is eligible: \(day)")
    }

    func testTapCueStartsATiltOnlyWhenFreeAndNear() {
        let l = lab(n: 2)
        let b0 = l.rigs[0].brain, b1 = l.rigs[1].brain
        let near = b0.position + SIMD2(1.5, 0.5)
        var started = false
        for _ in 0..<30 { if BlobBrain.tapCue(at: near, brains: [b0, b1]) { started = true; break }; b0.kindCool[.tapTilt] = nil; b1.kindCool[.tapTilt] = nil }
        XCTAssertTrue(started, "a tap near him starts a tilt")
        let far = SIMD2<Float>(40, 40)
        b0.commandedIdle = nil; b1.commandedIdle = nil
        XCTAssertFalse(BlobBrain.tapCue(at: far, brains: [b0, b1]), "a tap far away does nothing")
        b0.idleState.kind = .sleep
        XCTAssertFalse(b0.treat2Free, "a sleeper does not react")
    }

    func testCheckInIgnoresTouchAndEndsByItself() {
        let l = lab(n: 1)
        let r = l.rigs[0]; r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.checkIn, r.sim))
        var f = 0
        while f < 60 * 12 {
            l.tick(); f += 1
            if f == 150 { PlayerPresence.touch() }
            if r.brain.idleState.kind == nil && f > 20 { break }
        }
        XCTAssertEqual(r.brain.idleState.steps & (1 << 3), 0, "no touch response bit is ever set")
        XCTAssertNil(r.brain.idleState.kind, "he is done")
    }

    /// The double-tap highlight is untouched with a check-in running and a tap-tilt eligible; a tap on a Jelbie never starts a tilt.
    func testDoubleTapHighlightUnaffectedAndTapOnJelbieNeverTilts() {
        let care = GameCare(jellyCount: 2, persistent: false, defaults: UserDefaults(suiteName: "Emotes2.dbl")!)
        Self.keepCare.append(care)
        let l = lab(n: 2)
        let b0 = l.rigs[0].brain, b1 = l.rigs[1].brain
        b0.idleForced = true
        XCTAssertTrue(b0.idleStart(.checkIn, l.rigs[0].sim))
        XCTAssertNil(b1.kindCool[.tapTilt], "tap-tilt is eligible for the other one")
        care.tapJelly(1)
        for _ in 0..<150 { care.select.tick(dt: 1.0 / 60) }
        XCTAssertEqual(care.select.highlighted, 1, "the Jelbie is highlighted")
        // a tap that lands on a Jelbie's body (within 0.9 of his floor spot) never starts a tilt
        for _ in 0..<40 {
            XCTAssertFalse(BlobBrain.tapCue(at: b1.position + SIMD2(0.3, 0.2), brains: [b1]))
            XCTAssertNil(b1.commandedIdle)
        }
        XCTAssertEqual(care.select.highlighted, 1, "still highlighted: nothing consumed the tap")
    }
    nonisolated(unsafe) static var keepCare: [GameCare] = []

    func testWinCueMakesHimStrutWhenFree() {
        let l = lab(n: 1)
        let r = l.rigs[0]; r.brain.idleForced = true
        r.brain.proudStrutCue()
        XCTAssertTrue(r.brain.treat2.strutWanted)
        XCTAssertTrue(r.brain.treat2MaybeStart(r.sim), "the strut starts at the next free moment")
        XCTAssertEqual(r.brain.idleState.kind, .proudStrut)
        XCTAssertFalse(r.brain.treat2.strutWanted)
    }

    func testSelfScheduleSwitchHandsTheTreatsOver() {
        let l = lab(n: 1)
        let r = l.rigs[0]; r.brain.idleForced = true; r.brain.idleNight = 1; r.brain.watching = false
        let prevSelf = EmoteTreats.selfSchedule; EmoteTreats.selfSchedule = false; defer { EmoteTreats.selfSchedule = prevSelf }
        for _ in 0..<50 { r.brain.variety.now += 400; XCTAssertFalse(r.brain.treat2MaybeStart(r.sim)) }
    }
}
