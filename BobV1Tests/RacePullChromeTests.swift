//
//  RacePullChromeTests.swift
//  Stage B2 of the race's pull control: the pure pull maths, and what the flow hands the chrome (zone edges, serials, streak, the assists). Headless, fast.
//

import XCTest
import SwiftUI
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

    /// The resting thumb: the whole demo (top of the label to the bottom of the hand) is inside the safe area, clear of the title / hint pills and outside the Jelbie box
    /// (portrait: y from 0.40 h to 0.67 h at any x; landscape: x from 0.30 w to 0.70 w at any y), on the four device sizes.
    func testTheThumbDemoRestsOffTheJelbies() {
        let k: CGFloat = 1          // (the phone's ghost scale; the iPad's is demoScale(size:safe:pad:), tested below)
        let cases: [(String, CGSize, EdgeInsets)] = [
            ("phone portrait", CGSize(width: 402, height: 874), EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)),
            ("phone landscape", CGSize(width: 874, height: 402), EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)),
            ("iPad portrait", CGSize(width: 834, height: 1194), EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)),
            ("iPad landscape", CGSize(width: 1194, height: 834), EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)),
        ]
        for (name, size, safe) in cases {
            let a = RacePullGesture.restAnchor(size: size, safe: safe, k: k)
            let f = RacePullGesture.demoFrame(size: size, safe: safe, k: k)
            let land = size.width > size.height
            print("REST \(name) anchor (\(a.x), \(a.y)) demo y \(f.minY) ... \(f.maxY) x \(f.minX) ... \(f.maxX) of \(size.width) x \(size.height)")
            XCTAssertEqual(a.x, size.width * (land ? 0.8 : 0.5), accuracy: 0.01, "\(name): x")
            XCTAssertGreaterThanOrEqual(a.y, size.height * (land ? 0.36 : 0.70) - 0.01, "\(name): never higher than the floor of the rule")
            XCTAssertGreaterThanOrEqual(f.minY, safe.top, "\(name): inside the safe area (top)")
            XCTAssertLessThanOrEqual(f.maxY, size.height - safe.bottom - 12 + 0.01, "\(name): the hand ends 12 pt above the bottom safe area")
            XCTAssertGreaterThanOrEqual(f.minX, safe.leading, "\(name): inside the safe area (left)")
            XCTAssertLessThanOrEqual(f.maxX, size.width - safe.trailing, "\(name): inside the safe area (right)")
            XCTAssertGreaterThanOrEqual(f.minY, RacePullGesture.topPillsBottom(safeTop: safe.top) + 4, "\(name): the label clears the title and hint pills")
            let box = land ? CGRect(x: 0.30 * size.width, y: 0, width: 0.40 * size.width, height: size.height)
                           : CGRect(x: 0, y: 0.40 * size.height, width: size.width, height: 0.27 * size.height)
            XCTAssertFalse(f.intersects(box), "\(name): the demo \(f) is outside the Jelmiko box \(box)")
            // the demo's length is a pull the player could make from there (the room rule)
            let len = RacePullGesture.demoLength(size: size, anchor: a, safe: safe, k: k)
            XCTAssertLessThanOrEqual(a.y + len + 8, size.height - safe.bottom + 0.01, "\(name): room under the anchor")
            XCTAssertEqual(Float(len / RacePullGesture.dragMaxFor(size: size, startY: a.y, bottomInset: safe.bottom, scale: k)), RacePullGesture.demoPull, accuracy: 1e-4, "\(name): the demo shows a green pull")
        }
        // the capture gauge uses the same anchor at the real scale: it stays inside the safe area at its largest step too
        for (name, size, safe) in cases {
            let k13: CGFloat = size.width >= 800 && size.height >= 800 ? 1.3 : 1
            let a = RacePullGesture.restAnchor(size: size, safe: safe, k: k13)
            XCTAssertLessThanOrEqual(a.y, size.height - safe.bottom, "\(name): the gauge anchor is on screen")
        }
    }

    /// The phone's layout did not move with the iPad pad: the two anchors of the b3 hand-over.
    func testPhoneAnchorsArePinned() {
        let p = RacePullGesture.restAnchor(size: CGSize(width: 402, height: 874), safe: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), k: 1)
        XCTAssertEqual(p.x, 201, accuracy: 0.05); XCTAssertEqual(p.y, 662.2, accuracy: 0.05)
        let l = RacePullGesture.restAnchor(size: CGSize(width: 874, height: 402), safe: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62), k: 1)
        XCTAssertEqual(l.x, 699.2, accuracy: 0.05); XCTAssertEqual(l.y, 203.2, accuracy: 0.05)
        XCTAssertEqual(RacePullGesture.demoScale(size: CGSize(width: 402, height: 874), safe: EdgeInsets(), pad: false), 1)
    }

    /// The iPad: the ghost at 1.3 on every iPad window, beside the track in landscape, and the capture gauge's three steps stay on screen.
    func testIPadDemoScaleAnchorAndCaptureGauge() {
        let safe = EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        let portraits: [CGSize] = [CGSize(width: 744, height: 1133), CGSize(width: 820, height: 1180), CGSize(width: 834, height: 1194),
                                   CGSize(width: 834, height: 1210), CGSize(width: 1024, height: 1366), CGSize(width: 1032, height: 1376)]
        for portrait in portraits {
            for size in [portrait, CGSize(width: portrait.height, height: portrait.width)] {
                let land = size.width > size.height
                let name = "\(Int(size.width)) x \(Int(size.height))"
                let k = RacePullGesture.demoScale(size: size, safe: safe, pad: true)
                let a = RacePullGesture.restAnchor(size: size, safe: safe, k: k, pad: true)
                let f = RacePullGesture.demoFrame(size: size, safe: safe, k: k, pad: true)
                print("PADDEMO \(name): scale \(k) anchor (\(a.x), \(a.y)) frame y \(f.minY) ... \(f.maxY) x \(f.minX) ... \(f.maxX) fits(1.3) \(RacePullGesture.demoFits(size: size, safe: safe, k: 1.3, pad: true))")
                XCTAssertEqual(k, 1.3, "\(name): the ghost's scale")
                XCTAssertTrue(RacePullGesture.demoFits(size: size, safe: safe, k: k, pad: true), "\(name): demoFits \(f)")
                if land { XCTAssertEqual(a.x, 0.88 * size.width, accuracy: 0.01, "\(name): beside the track") }
                else { XCTAssertEqual(a.x, 0.5 * size.width, accuracy: 0.01, "\(name)") }
                // the capture gauge (scale 1.3, from the pad anchor): the finger dot's lowest point is inside the safe area at every step
                let ag = RacePullGesture.restAnchor(size: size, safe: safe, k: 1.3, pad: true)
                for p: Float in [0.45, 0.80, 1.05] {
                    let len = CGFloat(p) * RacePullGesture.dragMaxFor(size: size, startY: ag.y, bottomInset: safe.bottom, scale: 1.3)
                    let lowest = ag.y + len + 16 * 1.3
                    print("PADGAUGE \(name): step \(p) finger y \(ag.y + len) lowest \(lowest) of safe bottom \(size.height - safe.bottom)")
                    XCTAssertLessThanOrEqual(lowest, size.height - safe.bottom + 0.01, "\(name): step \(p) inside the safe area")
                }
            }
        }
        // the numbers of the brief for 834 x 1194 / 1194 x 834
        let pp = RacePullGesture.restAnchor(size: CGSize(width: 834, height: 1194), safe: safe, k: 1.3, pad: true)
        XCTAssertEqual(pp.y, 827.25, accuracy: 0.01); XCTAssertEqual(pp.y - RacePullGesture.labelAbove(1.3), 736.25, accuracy: 0.01)
        let ll = RacePullGesture.restAnchor(size: CGSize(width: 1194, height: 834), safe: safe, k: 1.3, pad: true)
        XCTAssertEqual(ll.x, 1050.72, accuracy: 0.01); XCTAssertEqual(ll.y, 467.25, accuracy: 0.01)
    }

    /// A narrow iPad window (Split View): a scale comes back and the whole demo is inside the safe area.
    func testNarrowIPadWindow() {
        let size = CGSize(width: 507, height: 1194), safe = EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        let k = RacePullGesture.demoScale(size: size, safe: safe, pad: true)
        let f = RacePullGesture.demoFrame(size: size, safe: safe, k: k, pad: true)
        print("PADDEMO narrow 507 x 1194: scale \(k) frame \(f) fits \(RacePullGesture.demoFits(size: size, safe: safe, k: k, pad: true))")
        XCTAssertTrue([1.3, 1.2, 1.1, 1.0].contains(k))
        XCTAssertGreaterThanOrEqual(f.minX, 0); XCTAssertLessThanOrEqual(f.maxX, size.width)
        XCTAssertGreaterThanOrEqual(f.minY, safe.top); XCTAssertLessThanOrEqual(f.maxY, size.height - safe.bottom)
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
        for b in CourseTier.allCases where b.index < course.index { f.progress.records[b] = CourseProgress.Record(races: 1, wins: 1, topTwo: 1) }          // (the courses below are won: this one is open)
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

    /// `RaceControl` is a developer argument: read only when the dev-arg gate is open (the App Store archive ignores it).
    func testRaceControlKeyNeedsTheDevGate() {
        let name = "RacePullChrome.gate.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        d.set("taps", forKey: "RaceControl")
        XCTAssertEqual(RaceFlow.defaultControl(defaults: d, environment: [:], devArgs: false), .pull, "gate closed: the key is not read")
        XCTAssertEqual(RaceFlow.defaultControl(defaults: d, environment: [:], devArgs: true), .taps, "gate open: the key wins")
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

    func testHintsNeverTeachTapsAndFollowTheAssist() {
        var ui = RaceUI(); ui.phase = .countdown; ui.pull = true
        XCTAssertEqual(RacePullTopText.hint(ui, assist: .off, autoJump: false, barHints: 0), "Pull down anywhere. Let go in the green!")
        XCTAssertEqual(RacePullTopText.hint(ui, assist: .oneButton, autoJump: false, barHints: 0), "Press Hop to hop along!")
        XCTAssertNil(RacePullTopText.hint(ui, assist: .auto, autoJump: false, barHints: 0))
        ui.phase = .running; ui.stalled = true
        XCTAssertEqual(RacePullTopText.hint(ui, assist: .off, autoJump: false, barHints: 0), "Pull down and let go!")
        ui.stalled = false; ui.hurdleAhead = true
        XCTAssertEqual(RacePullTopText.hint(ui, assist: .off, autoJump: false, barHints: 1), "Green clears the bar!")
        XCTAssertNil(RacePullTopText.hint(ui, assist: .off, autoJump: false, barHints: 4), "the first three bars only")
        XCTAssertNil(RacePullTopText.hint(ui, assist: .off, autoJump: true, barHints: 1), "not with Jump for me")
        ui.inTurn = true; ui.hurdleAhead = false
        XCTAssertNil(RacePullTopText.hint(ui, assist: .off, autoJump: false, barHints: 0), "no bend hint")
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
