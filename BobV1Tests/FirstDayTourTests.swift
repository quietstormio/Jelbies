//
//  FirstDayTourTests.swift
//  The first-day tour (Start/FirstDayTour.swift): the step list and its order, the sentences (the old screen's two captions word for word, the coach marks short),
//  the state machine (arrive, next, skip, finish), it runs once per new game, a replay can be watched again, Reduce Motion drops the run-in, and the game is held
//  (GameCare.introHold) exactly while the tour is armed or up.
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
    override func tearDown() { GameCare.introHold = false; super.tearDown() }

    func testStepOrderRunInThenCaptionsThenSevenCoachMarks() {
        let run = FirstDayTour.steps(run: true)
        XCTAssertEqual(run.first, .arrive)
        XCTAssertEqual(Array(run.dropFirst().prefix(2)), [.welcome, .jellyCoins])
        XCTAssertEqual(run.dropFirst(3).map { $0 }, [.coach(.care), .coach(.jelmiko), .coach(.coins), .coach(.bag), .coach(.goOut), .coach(.mic), .coach(.settings)])
        XCTAssertEqual(FirstDayTour.steps(run: false), Array(run.dropFirst()), "no run-in step without a run-in")
        XCTAssertTrue((5...7).contains(FirstDayTour.coachTargets.count))
    }

    func testTheOldScreensFactsAreKeptWordForWord() {
        XCTAssertEqual(FirstDayTour.welcomeLine("Lemon"), "Welcome home, Lemon!")
        XCTAssertEqual(FirstDayTour.coinsLine, FirstDayHomeView.lines.1, "the JellyCoins caption is the old screen's, unchanged")
        XCTAssertTrue(FirstDayTour.coinsLine.contains("JellyCoins") && FirstDayTour.coinsLine.contains("Spring"))
    }

    func testCoachSentencesAreShortFriendlyAndSayJelmiko() {
        for t in FirstDayTarget.allCases {
            for tap in [false, true] {
                let s = FirstDayTour.sentence(t, tapToTalk: tap)
                XCTAssertLessThanOrEqual(s.split(separator: " ").count, 12, s)
                XCTAssertFalse(s.contains("Jelbie"), s)
            }
        }
        XCTAssertTrue(FirstDayTour.sentence(.jelmiko).contains("Jelmiko"))
        XCTAssertTrue(FirstDayTour.sentence(.mic).contains("Jelmiko"))
    }

    func testWalkThroughAndTheRunInIsNotTappable() {
        let d = suite("walk"), t = FirstDayTour()
        XCTAssertTrue(t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: d))
        XCTAssertTrue(t.holdsGame); XCTAssertTrue(GameCare.introHold, "the game is held from the moment it is armed")
        XCTAssertNil(t.step, "nothing on screen until the room is up")
        t.roomReady()
        XCTAssertEqual(t.step, .arrive)
        t.next()
        XCTAssertEqual(t.step, .arrive, "a tap during the run-in does nothing")
        t.arrived()
        XCTAssertEqual(t.step, .welcome)
        var seen: [FirstDayStep] = [.arrive, .welcome]
        while t.active { t.next(); if let s = t.step { seen.append(s) } }
        XCTAssertEqual(seen, FirstDayTour.steps(run: true))
        XCTAssertFalse(t.holdsGame); XCTAssertFalse(GameCare.introHold, "the game is let go at the end")
        XCTAssertTrue(d.bool(forKey: FirstDayTour.doneKey))
    }

    func testCoachNumbersCountTheMarksOnly() {
        let t = FirstDayTour()
        t.arm(name: "Lemon", replay: false, reduceMotion: true, defaults: suite("nums"))
        t.roomReady()
        XCTAssertNil(t.coachNumber); t.next(); XCTAssertNil(t.coachNumber)
        t.next(); XCTAssertEqual(t.coachNumber, 1)
        for _ in 0..<6 { t.next() }
        XCTAssertEqual(t.coachNumber, 7); XCTAssertTrue(t.isLast)
        XCTAssertEqual(t.coachCount, 7)
    }

    func testSkipEndsItFromAnyStepAndItNeverRunsAgain() {
        for stop in 0..<FirstDayTour.steps(run: true).count {
            let d = suite("skip\(stop)"), t = FirstDayTour()
            t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: d)
            t.roomReady()
            for _ in 0..<stop { if t.step == .arrive { t.arrived() } else { t.next() } }
            t.skip()
            XCTAssertFalse(t.active); XCTAssertNil(t.step); XCTAssertFalse(GameCare.introHold)
            XCTAssertFalse(t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: d), "a new game's tour runs once (skipped at step \(stop))")
        }
    }

    func testSkippedBeforeTheRoomWasUpIsStillDoneAndReleasesTheGame() {
        let d = suite("early"), t = FirstDayTour()
        t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: d)
        t.skip()
        XCTAssertFalse(t.holdsGame); XCTAssertFalse(GameCare.introHold)
        t.roomReady()
        XCTAssertNil(t.step, "a skipped tour does not come up when the room appears")
    }

    func testReplayAlwaysPlaysHasNoRunInAndLeavesTheFlagAlone() {
        let d = suite("replay"), t = FirstDayTour()
        d.set(true, forKey: FirstDayTour.doneKey)
        XCTAssertTrue(t.arm(name: "Lemon", replay: true, reduceMotion: false, defaults: d), "Watch the opening can show it again")
        XCTAssertNil(t.takeArrival(), "nobody runs in on a replay (the Jelmiko is already home)")
        t.roomReady()
        XCTAssertEqual(t.step, .welcome)
        while t.active { t.next() }
        XCTAssertTrue(d.bool(forKey: FirstDayTour.doneKey))
        let d2 = suite("replay2")
        t.arm(name: "Lemon", replay: true, reduceMotion: false, defaults: d2); t.roomReady(); t.skip()
        XCTAssertFalse(d2.bool(forKey: FirstDayTour.doneKey), "a replay never marks a new game's tour as done")
        XCTAssertTrue(t.arm(name: "Lemon", replay: true, reduceMotion: false, defaults: d2), "and can be watched again and again")
    }

    func testArrivalIsTakenOnceRunNormallyPlacedUnderReduceMotion() {
        let t = FirstDayTour()
        t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: suite("arr1"))
        XCTAssertEqual(t.takeArrival(), .run); XCTAssertNil(t.takeArrival())
        t.arm(name: "Lemon", replay: false, reduceMotion: true, defaults: suite("arr2"))
        XCTAssertEqual(t.takeArrival(), .place, "Reduce Motion: no run-in, he is just there")
        t.roomReady()
        XCTAssertEqual(t.step, .welcome, "Reduce Motion starts at the welcome caption")
    }

    func testResetNeverLeavesTheGameHeld() {
        let t = FirstDayTour()
        t.arm(name: "Lemon", replay: false, reduceMotion: false, defaults: suite("reset"))
        XCTAssertTrue(GameCare.introHold)
        t.reset()
        XCTAssertFalse(GameCare.introHold); XCTAssertFalse(t.holdsGame); XCTAssertNil(t.step)
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
