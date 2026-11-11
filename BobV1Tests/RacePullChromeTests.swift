//
//  RacePullChromeTests.swift
//  Stage B2 of the race's pull control: the pure pull maths, and what the flow hands the chrome (zone edges, serials, streak, the assists). Headless, fast.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RacePullChromeTests: XCTestCase {
    override func tearDown() {
        A11ySettings.shared.raceAssist = .off
        A11ySettings.shared.relaxedTiming = false
        super.tearDown()
    }

    // MARK: the maths

    func testDragMax() {
        XCTAssertEqual(RacePullGesture.dragMax(size: CGSize(width: 402, height: 874)), 144.72, accuracy: 0.01)
        XCTAssertEqual(RacePullGesture.dragMax(size: CGSize(width: 320, height: 568)), 115.2, accuracy: 0.01)
        XCTAssertEqual(RacePullGesture.dragMax(size: CGSize(width: 1024, height: 1366)), 230, accuracy: 0.01)
        XCTAssertEqual(RacePullGesture.dragMax(size: CGSize(width: 874, height: 402)), 144.72, accuracy: 0.01)
    }

    func testPull() {
        let dm: CGFloat = 144.72
        XCTAssertEqual(RacePullGesture.pull(dx: 0, dy: 0.8 * dm, dragMax: dm), 0.80, accuracy: 1e-4, "straight down")
        XCTAssertEqual(RacePullGesture.pull(dx: 100, dy: 100, dragMax: dm), Float(hypot(100, 100) / dm), accuracy: 1e-4, "45 degrees down: the length")
        XCTAssertEqual(RacePullGesture.pull(dx: 100, dy: 0, dragMax: dm), Float(0.3 * 100 / dm), accuracy: 1e-4, "pure sideways: 0.3 of the length")
        XCTAssertEqual(RacePullGesture.pull(dx: 0, dy: -100, dragMax: dm), 0, accuracy: 1e-6, "straight up")
        XCTAssertEqual(RacePullGesture.pull(dx: 0, dy: 1000, dragMax: dm), 1.1, accuracy: 1e-6, "clamped at 1.1")
        XCTAssertEqual(RacePullGesture.pull(dx: 0, dy: 0, dragMax: dm), 0, "zero length")
    }

    func testKindness() {
        let size = CGSize(width: 402, height: 874), inset: CGFloat = 34
        XCTAssertEqual(RacePullGesture.dragMaxFor(size: size, startY: 874 - inset - 60, bottomInset: inset), 80, accuracy: 1e-4, "a start 60 pt above the bottom inset: the 80 pt floor")
        XCTAssertEqual(RacePullGesture.dragMaxFor(size: size, startY: 300, bottomInset: inset), RacePullGesture.dragMax(size: size), accuracy: 1e-4, "upper half: the full drag")
        XCTAssertEqual(RacePullGesture.dragMaxFor(size: size, startY: 300, bottomInset: inset, scale: 1.3), RacePullGesture.dragMax(size: size) * 1.3, accuracy: 1e-3, "iPad scale")
    }

    func testZone() {
        XCTAssertEqual(RacePullGesture.zone(pull: 0.69, lo: 0.7, hi: 0.92), .weak)
        XCTAssertEqual(RacePullGesture.zone(pull: 0.7, lo: 0.7, hi: 0.92), .green)
        XCTAssertEqual(RacePullGesture.zone(pull: 0.92, lo: 0.7, hi: 0.92), .green)
        XCTAssertEqual(RacePullGesture.zone(pull: 0.93, lo: 0.7, hi: 0.92), .over)
        XCTAssertEqual(RacePullGesture.zone(pull: 0.6, lo: 0.58, hi: 0.98), .green, "a wider green")
    }

    // MARK: the flow

    private func pullRace(_ assist: RaceAssist, course: CourseTier = .puddle, seed: UInt64 = 5, wait live: Bool = true) -> RaceFlow {
        A11ySettings.shared.raceAssist = assist
        let f = RaceFlow()
        f.cue = { _ in }; f.jingle = { _ in }
        f.recentRivals = nil
        f.control = .pull
        f.begin(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.9, focus: 1), playerTint: JellyRoster.tint(0), rivalCount: 2, seed: seed, course: course)
        var n = 0
        if live { while !f.buttonsLive, n < 60 * 20 { step(f); n += 1 } }
        return f
    }
    private func step(_ f: RaceFlow) { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }

    func testDefaultControl() {
        XCTAssertEqual(RaceFlow().control, UserDefaults.standard.string(forKey: "RaceControl").flatMap(RaceControl.init(rawValue:)) ?? .taps, "a unit-test host runs the taps race unless the argument says otherwise")
        let d = UserDefaults(suiteName: "RacePullChrome.\(UUID().uuidString)")!
        XCTAssertEqual(RaceFlow.defaultControl(defaults: d, environment: [:]), .pull, "the app: pull")
        XCTAssertEqual(RaceFlow.defaultControl(defaults: d, environment: ["XCTestConfigurationFilePath": "x"]), .taps, "a test host: taps")
        d.set("taps", forKey: "RaceControl")
        XCTAssertEqual(RaceFlow.defaultControl(defaults: d, environment: [:]), .taps, "the argument wins in the app")
        d.set("pull", forKey: "RaceControl")
        XCTAssertEqual(RaceFlow.defaultControl(defaults: d, environment: ["XCTestConfigurationFilePath": "x"]), .pull, "the argument wins in a test host")
    }

    func testForgivingWidensTheGreenAndMatchesTheModel() {
        let off = pullRace(.off), wide = pullRace(.forgiving)
        XCTAssertEqual(off.ui.zoneLo, 0.70, accuracy: 1e-5); XCTAssertEqual(off.ui.zoneHi, 0.92, accuracy: 1e-5)
        XCTAssertLessThan(wide.ui.zoneLo, off.ui.zoneLo); XCTAssertGreaterThan(wide.ui.zoneHi, off.ui.zoneHi)
        XCTAssertEqual(off.ui.pullMin, 0.15, accuracy: 1e-5); XCTAssertEqual(off.ui.pullMax, 1.1, accuracy: 1e-5)
        for f in [off, wide] {
            let s = f.sim!, lo = f.ui.zoneLo, hi = f.ui.zoneHi, w = s.playerZoneWiden
            XCTAssertEqual(s.pullTuning.shot(pull: lo, streak: 0, widen: w).grade, .perfect, "the lower edge is green")
            XCTAssertEqual(s.pullTuning.shot(pull: hi, streak: 0, widen: w).grade, .perfect, "the upper edge is green")
            XCTAssertEqual(s.pullTuning.shot(pull: lo - 0.01, streak: 0, widen: w).grade, .weak, "just under the zone")
            XCTAssertEqual(s.pullTuning.shot(pull: hi + 0.01, streak: 0, widen: w).grade, .over, "just past the zone")
            XCTAssertEqual(RacePullGesture.zone(pull: lo, lo: lo, hi: hi), .green)
            XCTAssertEqual(RacePullGesture.zone(pull: hi + 0.01, lo: lo, hi: hi), .over)
        }
        // relaxed timing widens it too
        A11ySettings.shared.relaxedTiming = true
        let relaxed = pullRace(.off)
        XCTAssertEqual(relaxed.ui.zoneLo, wide.ui.zoneLo, accuracy: 1e-5)
        XCTAssertEqual(relaxed.ui.zoneHi, wide.ui.zoneHi, accuracy: 1e-5)
    }

    func testOneButtonHopIsPerfect() {
        let f = pullRace(.oneButton)
        XCTAssertFalse(f.sim!.autoHopPlayer)
        for _ in 0..<60 { step(f) }
        XCTAssertEqual(f.hopAssist(), .hopped(.perfect), "the Hop button is a release in the middle of the green")
        XCTAssertEqual(RaceFlow.assistPull, 0.74)
        let z = f.ui
        XCTAssertGreaterThanOrEqual(RaceFlow.assistPull, z.zoneLo); XCTAssertLessThanOrEqual(RaceFlow.assistPull, z.zoneHi)
    }

    func testAutoFinishesWithNoInputAndPaysHalf() {
        let f = pullRace(.auto)
        XCTAssertTrue(f.sim!.autoHopPlayer)
        var n = 0
        while !f.hasResults, n < 60 * 150 { step(f); n += 1 }
        XCTAssertTrue(f.hasResults, "the race ends with no input")
        XCTAssertTrue(f.sim!.playerFinished, "he ran by himself and crossed the line")
        XCTAssertEqual(f.earnedDropsForTest, f.assistedDrops(f.sim!.playerDrops), "pays assistedDrops")
        XCTAssertEqual(f.earnedDropsForTest, Int((Float(f.sim!.playerDrops) * RaceFlow.autoPayShare).rounded(.down)))
    }

    func testSerialsGradeAndStreakFollowThePlayer() {
        let f = pullRace(.off)
        XCTAssertEqual(f.ui.hopSerial, 0); XCTAssertNil(f.ui.hopGrade); XCTAssertEqual(f.ui.streak, 0); XCTAssertEqual(f.ui.bonkSerial, 0)
        var n = 0
        while f.ui.hopSerial < 3, n < 60 * 30 {
            if !f.sim!.pullState(0).buffered { f.release(pull: 0.80) }
            step(f); n += 1
        }
        XCTAssertEqual(f.ui.hopSerial, 3, "three hops")
        XCTAssertEqual(f.ui.hopGrade, .perfect)
        XCTAssertEqual(f.ui.streak, 3, "three green releases: streak 3")
        XCTAssertEqual(f.ui.bonkSerial, 0)
    }

    func testAWeakReleaseIntoABarBonks() {
        let f = pullRace(.off, course: .splash)
        var trips = 0
        f.eventTap = { if case .trip(let r) = $0, r == RaceSim.playerIndex { trips += 1 } }
        var n = 0
        while f.ui.bonkSerial == 0, !f.hasResults, n < 60 * 90 {
            if !f.sim!.pullState(0).buffered { f.release(pull: 0.40) }
            step(f); n += 1
        }
        XCTAssertEqual(f.ui.bonkSerial, 1, "the player's first trip into a bar")
        XCTAssertEqual(trips, 1, "the counter follows the player's .trip events")
        XCTAssertEqual(f.ui.streak, 0, "a trip breaks the streak")
    }

    func testAReleaseDuringAStumbleIsIgnored() {
        let f = pullRace(.off, course: .splash)
        var n = 0
        while !f.ui.stumbling, !f.hasResults, n < 60 * 90 {
            if !f.sim!.pullState(0).buffered { f.release(pull: 0.40) }
            step(f); n += 1
        }
        XCTAssertTrue(f.ui.stumbling, "he tripped")
        XCTAssertEqual(f.release(pull: 0.8), .ignored, "the model ignores a release while he stumbles")
    }
}
