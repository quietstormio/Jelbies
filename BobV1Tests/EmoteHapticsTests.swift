//
//  EmoteHapticsTests.swift
//  The room's emote haptics (RoomHaptics, 2026-11-02), counted at the request level (no hardware): each emote asks for its pattern exactly once per play (belly drum: a soft tap on every
//  second pat), the global rate is <= 2 a second, nothing is requested with Haptics off in Settings or while focus mode / the wash give their own, and a request past the guards is cheap.
//

import XCTest
@testable import BobV1

@MainActor
final class EmoteHapticsTests: XCTestCase {
    var savedSetting: Any?
    override func setUp() {
        super.setUp()
        savedSetting = UserDefaults.standard.object(forKey: HapticSettings.key)
        HapticSettings.enabled = true
        RoomHaptics.shared.reset()
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }
    override func tearDown() {
        RoomHaptics.requestTap = nil
        RoomHaptics.clock = { CACurrentMediaTime() }
        RoomHaptics.shared.reset()
        if let v = savedSetting { UserDefaults.standard.set(v, forKey: HapticSettings.key) } else { UserDefaults.standard.removeObject(forKey: HapticSettings.key) }
        super.tearDown()
    }

    /// Plays `kind` to its end on a fresh rig (simulated clock) and returns the requests with their times.
    func play(_ kind: IdleKind, feature: JellyFeature = .none) -> [(RoomHaptics.Pattern, Double)] {
        let r = MotionRig(game: true)
        r.brain.feature = feature
        RoomHaptics.shared.reset()
        var got: [(RoomHaptics.Pattern, Double)] = []
        RoomHaptics.clock = { Double(r.t) }
        RoomHaptics.requestTap = { got.append(($0, Double(r.t))) }
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind) did not start")
        for _ in 0..<(60 * 12) { r.tick(); if r.brain.idleState.kind == nil { break } }
        XCTAssertNil(r.brain.idleState.kind, "\(kind) did not finish")
        return got
    }

    func testEachEmoteRequestsItsPatternExactlyOnce() {
        let expect: [(IdleKind, [RoomHaptics.Pattern])] = [
            (.hiccup, [.hic]), (.sneeze, [.sneezeBuild, .sneezeBump]), (.dizzyWobble, [.wobble]), (.politeBow, [.bowTick]),
            (.bellyDrum, [.patA, .patB, .patA]), (.signatureFlourish, [.flourish]),
        ]
        for (k, pats) in expect {
            let got = play(k)
            XCTAssertEqual(got.map { $0.0 }, pats, "\(k): the haptic requests of one play")
            for (a, b) in zip(got, got.dropFirst()) { XCTAssertGreaterThanOrEqual(b.1 - a.1, RoomHaptics.minGap - 0.02, "\(k): two haptics \(b.1 - a.1) s apart") }
        }
        for f in [JellyFeature.spines, .wings, .daisy, .ears] {
            XCTAssertEqual(play(.signatureFlourish, feature: f).map { $0.0 }, [.flourish], "the flourish of \(f) asks for one pulse")
        }
    }

    func testRateLimitIsTwoPerSecondAcrossEveryone() {
        var now = 0.0
        RoomHaptics.clock = { now }
        var ok: [Double] = []
        for t in [0.0, 0.2, 0.49, 0.5, 0.9, 1.0, 1.1, 1.6] { now = t; if RoomHaptics.shared.request(.hic) { ok.append(t) } }
        XCTAssertEqual(ok, [0.0, 0.5, 1.0, 1.6])
        for t0 in stride(from: 0.0, through: 1.0, by: 0.1) { XCTAssertLessThanOrEqual(ok.filter { $0 >= t0 && $0 < t0 + 1 }.count, 2, "window at \(t0)") }
    }

    func testNothingWhenHapticsAreOffOrSomethingElseGivesItsOwn() {
        var n = 0
        RoomHaptics.requestTap = { _ in n += 1 }
        var now = 0.0; RoomHaptics.clock = { now }
        HapticSettings.enabled = false
        XCTAssertFalse(RoomHaptics.shared.request(.hic)); XCTAssertEqual(n, 0, "Haptics off in Settings")
        HapticSettings.enabled = true
        RoomHaptics.shared.externalBusy = true
        now = 5; XCTAssertFalse(RoomHaptics.shared.request(.hic)); XCTAssertEqual(n, 0, "focus mode / the wash are giving their own")
        RoomHaptics.shared.externalBusy = false
        now = 10; XCTAssertTrue(RoomHaptics.shared.request(.hic)); XCTAssertEqual(n, 1)
    }

    func testRacersAndVolleyPlayersAskForNothing() {
        let r = MotionRig(game: true)
        var n = 0
        RoomHaptics.requestTap = { _ in n += 1 }
        RoomHaptics.clock = { Double(r.t) }
        r.brain.race.active = true
        r.brain.emoteHaptic(.hic)
        XCTAssertEqual(n, 0, "a racing Jelbie")
        r.brain.race.active = false
        r.brain.emoteHaptic(.hic)
        XCTAssertEqual(n, 1)
    }

    func testPatternsAreSoft() {
        for p in RoomHaptics.Pattern.allCases { for pulse in p.pulses { XCTAssertLessThanOrEqual(pulse.i, 0.4, "\(p) is a soft tap"); XCTAssertLessThanOrEqual(pulse.s, 0.3, "\(p) is round, not crisp") } }
    }
}
