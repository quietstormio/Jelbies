//
//  FirstDayTourTests.swift
//  The first-day handshake (Start/FirstDayTour.swift) that starts the tutorial (Tutorial/Tutorial.swift): it runs once per new game, Skip ends it from ANY step and it never runs again,
//  a replay can be watched again and writes nothing, Reduce Motion drops the run-in, the run-in cannot be tapped away, and the game is held (GameCare.introHold) exactly while it is armed or up.
//  (The old 9-step tour's captions and seven coach marks are gone on purpose: the tutorial's own content is pinned in TutorialTests.swift.)
//

import XCTest
@testable import BobV1

@MainActor
final class FirstDayTourTests: XCTestCase {
    private func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "FirstDayTourTests.\(name)")!
        d.removePersistentDomain(forName: "FirstDayTourTests.\(name)")
        return d
    }
    override func setUp() { super.setUp(); Tutorial.shared.reset() }
    override func tearDown() { Tutorial.shared.reset(); Tutorial.shared.defaults = .standard; Tutorial.shared.now = { Date() }; GameCare.introHold = false; super.tearDown() }

    func testWalkThroughAndTheRunInIsNotTappable() {
        let d = suite("walk"), t = FirstDayTour(), tut = Tutorial.shared
        XCTAssertTrue(t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: d))
        XCTAssertTrue(t.holdsGame); XCTAssertTrue(GameCare.introHold, "the game is held from the moment it is armed")
        XCTAssertNil(tut.step, "nothing on screen until the room is up")
        t.roomReady()
        XCTAssertEqual(tut.step?.id, "arrive")
        tut.buttonTapped(); tut.tick(world: TutorialWorld())
        XCTAssertEqual(tut.step?.id, "arrive", "a tap or a tick during the run-in does nothing")
        t.arrived()
        XCTAssertEqual(tut.step?.id, "intro")
        XCTAssertTrue(tut.holdsGame); XCTAssertTrue(GameCare.introHold)
        TutorialDriver.finish(tut)
        XCTAssertFalse(t.holdsGame); XCTAssertFalse(GameCare.introHold, "the game is let go at the end")
        XCTAssertTrue(d.bool(forKey: FirstDayTour.doneKey)); XCTAssertEqual(d.string(forKey: Tutorial.stateKey), "done")
    }

    func testSkipEndsItFromAnyStepAndItNeverRunsAgain() {
        for stop in 0..<Tutorial.homeSteps.count {
            let d = suite("skip\(stop)"), t = FirstDayTour(), tut = Tutorial.shared
            t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: d)
            t.roomReady()
            for _ in 0..<stop { TutorialDriver.advance(tut) }
            XCTAssertTrue(tut.active, "still up at step \(stop)")
            tut.skip()
            XCTAssertFalse(tut.active); XCTAssertNil(tut.step); XCTAssertFalse(GameCare.introHold)
            XCTAssertEqual(d.string(forKey: Tutorial.stateKey), "skipped")
            XCTAssertFalse(t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: d), "a new game's tutorial runs once (skipped at step \(stop))")
            Tutorial.shared.reset()
        }
    }

    func testSkippedBeforeTheRoomWasUpIsStillDoneAndReleasesTheGame() {
        let d = suite("early"), t = FirstDayTour()
        t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: d)
        t.skip()
        XCTAssertFalse(t.holdsGame); XCTAssertFalse(GameCare.introHold)
        Tutorial.shared.defaults = d
        t.roomReady()
        XCTAssertNil(Tutorial.shared.step, "a skipped tutorial does not come up when the room appears")
    }

    func testReplayAlwaysPlaysHasNoRunInAndLeavesTheFlagAlone() {
        let d = suite("replay"), t = FirstDayTour(), tut = Tutorial.shared
        d.set(true, forKey: FirstDayTour.doneKey)
        XCTAssertTrue(t.arm(name: "Lemon", replay: true, reduceMotion: false, defaults: d), "Watch the opening can show it again")
        XCTAssertNil(t.takeArrival(), "nobody runs in on a replay (the Jelmiko is already home)")
        t.roomReady()
        XCTAssertEqual(tut.step?.id, "intro")
        TutorialDriver.finish(tut)
        XCTAssertTrue(d.bool(forKey: FirstDayTour.doneKey)); XCTAssertNil(d.string(forKey: Tutorial.stateKey), "a replay writes no progress")
        let d2 = suite("replay2")
        t.arm(name: "Lemon", replay: true, reduceMotion: false, defaults: d2); t.roomReady(); tut.skip()
        XCTAssertFalse(d2.bool(forKey: FirstDayTour.doneKey), "a replay never marks a new game's tutorial as done")
        XCTAssertTrue(t.arm(name: "Lemon", replay: true, reduceMotion: false, defaults: d2), "and can be watched again and again")
    }

    func testArrivalIsTakenOnceRunNormallyPlacedUnderReduceMotion() {
        let t = FirstDayTour()
        t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: suite("arr1"))
        XCTAssertEqual(t.takeArrival(), .run); XCTAssertNil(t.takeArrival())
        t.arm(name: "Lemon", replay: false, reduceMotion: true, defaults: suite("arr2"))
        XCTAssertEqual(t.takeArrival(), .place, "Reduce Motion: no run-in, he is just there")
        t.roomReady()
        XCTAssertEqual(Tutorial.shared.step?.id, "intro", "Reduce Motion starts at the intro card")
    }

    func testResetNeverLeavesTheGameHeld() {
        let t = FirstDayTour()
        t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: suite("reset"))
        XCTAssertTrue(GameCare.introHold)
        t.reset()
        XCTAssertFalse(GameCare.introHold); XCTAssertFalse(t.holdsGame); XCTAssertNil(Tutorial.shared.step)
    }

    func testStyleSwitchDefaultsToTheRoom() {
        XCTAssertEqual(FirstDayStyle.defaultStyle, .room)
        let d = UserDefaults.standard
        defer { d.removeObject(forKey: "FirstDayStyle") }
        d.set("card", forKey: "FirstDayStyle"); XCTAssertEqual(FirstDayStyle.current, .card)
        d.set("room", forKey: "FirstDayStyle"); XCTAssertEqual(FirstDayStyle.current, .room)
        d.removeObject(forKey: "FirstDayStyle"); XCTAssertEqual(FirstDayStyle.current, FirstDayStyle.defaultStyle)
    }

    func testTheFirstCoinsHookStillAppliesForTheFirstJelmikoOnly() {
        let d = suite("coins")
        XCTAssertNil(StartFlow.applyPendingFirstCoins(10_000, first: false, defaults: d))
        XCTAssertEqual(StartFlow.applyPendingFirstCoins(10_000, first: true, defaults: d), 10_000)
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 10_000)
    }
}
