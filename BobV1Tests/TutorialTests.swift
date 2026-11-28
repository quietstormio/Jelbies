//
//  TutorialTests.swift
//  The tutorial engine (Tutorial/): the steps and their order, the owner's lines, the text rules (about 12 words or fewer, "Jelmiko", "JellyCoins"), that every step waits for the REAL action, Skip at every step,
//  progress that survives a kill, the first-hungry reminder, which touches the window takes, where the card stands (never over the ring, never taller than the room), and the concentric rules
//  the card, the ring and the touch hole follow.
//

import XCTest
import SwiftUI
@testable import BobV1

/// Plays a tutorial the way a player would: does the real wait of the current step, then lets the engine tick.
@MainActor
enum TutorialDriver {
    static var clock = Date(timeIntervalSince1970: 1_000_000)
    static func world(for step: TutorialStep) -> TutorialWorld {
        var w = TutorialWorld()
        if let t = step.target { w.targets.insert(t) }
        switch step.wait {
        case .menuOpen: w.menuOpen = true
        case .menuClosed: w.menuOpen = false
        case .townOpen: w.townOpen = true
        case .focusOpen: w.focusActive = true
        case .focusClosed: w.focusActive = false
        case .hearts: w.hearts = true
        case .trayOut: w.trayOut = true
        case .target(let t): w.targets.insert(t)
        case .anyTarget(let ts): w.targets.insert(ts[0])
        case .button, .arrival: break
        }
        return w
    }
    static func advance(_ t: Tutorial) {
        t.now = { clock }
        guard let s = t.step else { return }
        switch s.wait {
        case .button: t.buttonTapped()
        case .arrival: t.arrivalDone()
        case .menuClosed:          // "close it" counts only after the player was seen with it open
            clock = clock.addingTimeInterval(1); var open = world(for: s); open.menuOpen = true; t.tick(world: open)
            clock = clock.addingTimeInterval(1); t.tick(world: world(for: s))
        default: clock = clock.addingTimeInterval(1); t.tick(world: world(for: s))
        }
    }
    static func finish(_ t: Tutorial) { var n = 0; while t.active, n < 60 { advance(t); n += 1 } }
    static func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "TutorialTests.\(name)")!
        d.removePersistentDomain(forName: "TutorialTests.\(name)")
        return d
    }
    static func make(_ name: String, run: Bool = false, replay: Bool = false) -> (Tutorial, UserDefaults) {
        let d = suite(name), t = Tutorial()
        t.defaults = d; t.now = { clock }
        t.begin(name: "Lemon", replay: replay, run: run)
        return (t, d)
    }
}

@MainActor
final class TutorialTests: XCTestCase {
    override func tearDown() { GameCare.introHold = false; super.tearDown() }

    // MARK: content

    func testStepOrderIntroThenCuddleCareGoOut() {
        XCTAssertEqual(Tutorial.homeSteps.map(\.id), ["arrive", "intro", "cuddle.tap", "cuddle.come", "cuddle.rub", "cuddle.release", "care.heart", "care.menu", "out.go", "out.town"])
        XCTAssertEqual(Tutorial.homeSteps.map(\.chapter), [0, 0, 1, 1, 1, 1, 2, 2, 3, 3])
        XCTAssertEqual(Tutorial.chapterCount, 3)
        XCTAssertEqual(Tutorial.homeSteps.filter { $0.wait == .button }.map(\.id), ["intro", "out.town"], "only caption cards wait for a button; every other step waits for the real action")
    }

    func testTheOwnersLinesAreThere() {
        let intro = Tutorial.homeSteps[1]
        XCTAssertEqual(intro.head("Lemon"), "This is your Jelmiko, Lemon.")
        XCTAssertEqual(intro.text, "To take care of them, you can:")
        XCTAssertEqual(Tutorial.introRows.map(\.text), ["Feed them.", "Give water.", "Cuddle them.", "Play with toys.", "Let them sleep.", "Earn JellyCoins."])
        let out = Tutorial.homeSteps.last!
        XCTAssertEqual([out.title, out.text].compactMap { $0 }.joined(separator: " "), "Shop, races, the park and more. Each one shows you how the first time.")
    }

    func testEveryLineIsShortKindAndSaysJelmikoAndJellyCoins() {
        for l in Tutorial.allLines {
            XCTAssertLessThanOrEqual(l.split(separator: " ").count, 12, l)
            for bad in ["Jelmikos", "Jelbie", "Jellycoin", "jelly coin", "Drops", "coins "] { XCTAssertFalse(l.contains(bad), "\(bad) in \(l)") }
        }
        XCTAssertTrue(Tutorial.allLines.contains { $0.contains("JellyCoins") })
        XCTAssertTrue(Tutorial.allLines.contains { $0.contains("Jelmiko") })
    }

    // MARK: waiting for the real action

    func testEveryStepWaitsForItsActionAndNothingElse() {
        for s in Tutorial.homeSteps where s.wait != .button && s.wait != .arrival {
            let (t, _) = TutorialDriver.make("wait.\(s.id)")
            t.jump(toID: s.id)
            XCTAssertEqual(t.step?.id, s.id)
            // the world as it is when the player has done nothing yet: the control is there, the action is not
            var idle = TutorialWorld(); if let tg = s.target { idle.targets.insert(tg) }
            if s.wait == .menuClosed { idle.menuOpen = false }          // nothing seen open yet: closed means nothing
            if s.wait == .focusClosed { idle.focusActive = true }
            TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(2)
            t.now = { TutorialDriver.clock }
            t.tick(world: idle)
            XCTAssertEqual(t.step?.id, s.id, "\(s.id) must not move before the player acts")
            if s.wait == .menuClosed { var o = idle; o.menuOpen = true; t.tick(world: o); XCTAssertEqual(t.step?.id, s.id) }
            t.tick(world: TutorialDriver.world(for: s))
            XCTAssertNotEqual(t.step?.id, s.id, "\(s.id) moves once the player acted")
            t.reset()
        }
    }

    func testAStepNeverFlashesPastBeforeItsDwell() {
        let (t, _) = TutorialDriver.make("dwell")
        t.jump(toID: "out.go")
        var w = TutorialWorld(); w.targets = ["goout"]; w.townOpen = true
        t.tick(world: w)
        XCTAssertEqual(t.step?.id, "out.go", "already satisfied, but the card shows first")
        TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(Tutorial.minDwell + 0.1); t.now = { TutorialDriver.clock }
        t.tick(world: w)
        XCTAssertEqual(t.step?.id, "out.town")
        t.reset()
    }

    func testTheCareStepsFollowTheMenuWhateverItsStateWas() {
        let (t, _) = TutorialDriver.make("heart")
        t.jump(toID: "care.heart")          // selecting a Jelmiko opens the menu: it can already be open when the chapter starts
        func tick(_ open: Bool) { TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(1); t.now = { TutorialDriver.clock }; var w = TutorialWorld(); w.targets = ["care"]; w.menuOpen = open; t.tick(world: w) }
        tick(true); XCTAssertEqual(t.step?.id, "care.menu", "already open: on to 'close it'")
        tick(true); XCTAssertEqual(t.step?.id, "care.menu", "still open: not closed yet")
        tick(false); XCTAssertEqual(t.step?.id, "out.go")
        t.reset()
        let (u, _) = TutorialDriver.make("heart2")
        u.jump(toID: "care.heart")
        func tick2(_ open: Bool) { TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(1); u.now = { TutorialDriver.clock }; var w = TutorialWorld(); w.targets = ["care"]; w.menuOpen = open; u.tick(world: w) }
        tick2(false); XCTAssertEqual(u.step?.id, "care.heart", "closed: waits for the heart")
        tick2(true); XCTAssertEqual(u.step?.id, "care.menu")
        u.reset()
    }

    func testAStepWaitsOutOfSightWhileAnotherScreenHasTheGame() {
        let (t, _) = TutorialDriver.make("pause")
        t.jump(toID: "care.heart")
        var w = TutorialWorld(); w.targets = ["care"]
        t.tick(world: w); XCTAssertFalse(t.paused); XCTAssertNotNil(t.shownStep)
        w.busy = true; t.tick(world: w); XCTAssertTrue(t.paused); XCTAssertNil(t.shownStep, "nothing drawn, nothing blocks a touch")
        w.busy = false; w.sheetOpen = true; t.tick(world: w); XCTAssertNil(t.shownStep, "Settings has the game")
        w.sheetOpen = false; w.townOpen = true; t.tick(world: w); XCTAssertNil(t.shownStep, "a home-room step does not show over the Go out screens")
        t.jump(toID: "out.town"); t.tick(world: w); XCTAssertNotNil(t.shownStep, "but the Go out card does")
        t.reset()
    }

    func testAControlThatNeverShowsMovesOnOrGoesBack() {
        let (t, _) = TutorialDriver.make("missing")
        t.jump(toID: "cuddle.come")                    // the Come here row is gone (he was let go): back to "Tap Jelmiko"
        TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(1); t.now = { TutorialDriver.clock }
        t.tick(world: TutorialWorld())
        XCTAssertEqual(t.step?.id, "cuddle.come", "a moment's wait first")
        TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(Tutorial.missingWait + 0.5); t.now = { TutorialDriver.clock }
        t.tick(world: TutorialWorld())
        XCTAssertEqual(t.step?.id, "cuddle.tap")
        t.jump(toID: "out.go")
        TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(1); t.now = { TutorialDriver.clock }
        t.tick(world: TutorialWorld())
        TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(Tutorial.missingWait + 0.5); t.now = { TutorialDriver.clock }
        t.tick(world: TutorialWorld())
        XCTAssertEqual(t.step?.id, "out.town", "a Go out button that is not there is not waited for forever")
        t.reset()
    }

    // MARK: skip, finish, resume

    func testSkipAtEveryStepEndsItAndSetsTheFlags() {
        for i in 0..<Tutorial.homeSteps.count {
            let (t, d) = TutorialDriver.make("skip\(i)", run: true)
            for _ in 0..<i { TutorialDriver.advance(t) }
            XCTAssertTrue(t.active, "step \(i)")
            t.skip()
            XCTAssertFalse(t.active); XCTAssertNil(t.step); XCTAssertFalse(t.holdsGame)
            XCTAssertEqual(d.string(forKey: Tutorial.stateKey), "skipped"); XCTAssertTrue(d.bool(forKey: FirstDayTour.doneKey))
        }
    }

    func testFinishingMarksItDoneAndReleasesTheGame() {
        let (t, d) = TutorialDriver.make("finish", run: true)
        XCTAssertTrue(GameCare.introHold); XCTAssertTrue(t.freezesNeeds)
        TutorialDriver.finish(t)
        XCTAssertEqual(d.string(forKey: Tutorial.stateKey), "done"); XCTAssertFalse(GameCare.introHold)
    }

    func testProgressSurvivesAKillAndResumesAtTheChapterStart() {
        for (reach, expectedID) in [("intro", "intro"), ("cuddle.tap", "cuddle.tap"), ("cuddle.release", "cuddle.tap"), ("care.menu", "care.heart"), ("out.town", "out.go")] {
            let d = TutorialDriver.suite("kill.\(reach)")
            let a = Tutorial(); a.defaults = d; a.now = { TutorialDriver.clock }
            a.begin(name: "Lemon", replay: false, run: true)
            while a.step?.id != reach { TutorialDriver.advance(a) }
            a.reset()          // the app is killed: nothing is told, only what was written stays (reset does not write)
            let b = Tutorial(); b.defaults = d
            XCTAssertTrue(b.inProgress, reach)
            XCTAssertTrue(b.resumeIfNeeded(name: "Lemon"), reach)
            XCTAssertEqual(b.step?.id, expectedID, "killed at \(reach)")
            b.reset()
        }
    }

    func testNothingResumesAfterDoneOrSkipOrOnAReplay() {
        let (t, d) = TutorialDriver.make("noresume"); TutorialDriver.finish(t)
        XCTAssertFalse(Tutorial().with(d).resumeIfNeeded(name: "Lemon"))
        let (r, d2) = TutorialDriver.make("replaynoresume", replay: true); r.reset()
        XCTAssertFalse(Tutorial().with(d2).resumeIfNeeded(name: "Lemon"), "a replay writes no progress to resume")
    }

    func testReplayFromSettingsStartsAtTheIntroAndWritesNothing() {
        let d = TutorialDriver.suite("settings"); d.set("done", forKey: Tutorial.stateKey); d.set(true, forKey: FirstDayTour.doneKey)
        let t = Tutorial(); t.defaults = d; t.now = { TutorialDriver.clock }
        t.replayFromSettings(name: "Lemon")
        XCTAssertEqual(t.step?.id, "intro")
        t.skip()
        XCTAssertEqual(d.string(forKey: Tutorial.stateKey), "done", "skipping a replay does not turn a finished tutorial into a skipped one")
    }

    // MARK: the first-hungry reminder

    private func hungryWorld() -> TutorialWorld { var w = TutorialWorld(); w.hungry = true; return w }

    func testHungryReminderComesOnceAfterAFinishedTutorialOnly() {
        let d = TutorialDriver.suite("hungry"), t = Tutorial(); t.defaults = d; t.now = { TutorialDriver.clock }
        t.maybeStartHungry(world: hungryWorld()); XCTAssertFalse(t.active, "not before the tutorial is done")
        d.set("skipped", forKey: Tutorial.stateKey)
        t.maybeStartHungry(world: hungryWorld()); XCTAssertFalse(t.active, "a skipped tutorial is not shown again")
        d.set("done", forKey: Tutorial.stateKey)
        var busy = hungryWorld(); busy.busy = true
        t.maybeStartHungry(world: busy); XCTAssertFalse(t.active, "never over a race or a show")
        t.maybeStartHungry(world: TutorialWorld()); XCTAssertFalse(t.active, "not hungry")
        t.maybeStartHungry(world: hungryWorld())
        XCTAssertTrue(t.active); XCTAssertTrue(t.isHint); XCTAssertEqual(t.step?.id, "hungry.heart")
        XCTAssertFalse(t.freezesNeeds, "the reminder never freezes the needs")
        XCTAssertTrue(t.holdsGame, "but tips wait while it is up")
        t.skip()
        XCTAssertTrue(d.bool(forKey: Tutorial.hungryKey))
        t.maybeStartHungry(world: hungryWorld()); XCTAssertFalse(t.active, "once")
    }

    func testHungryReminderWithFoodGoesHeartFeedFood() {
        let d = TutorialDriver.suite("hungryfood"), t = Tutorial(); t.defaults = d; t.now = { TutorialDriver.clock }
        d.set("done", forKey: Tutorial.stateKey)
        t.maybeStartHungry(world: hungryWorld())
        func act(_ w: TutorialWorld) { TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(1); t.now = { TutorialDriver.clock }; t.tick(world: w) }
        var w = hungryWorld(); w.targets = ["care"]
        w.menuOpen = true
        act(w); XCTAssertEqual(t.step?.id, "hungry.feed")
        w.targets = ["feed", "food"]
        act(w); XCTAssertEqual(t.step?.id, "hungry.food")
        XCTAssertEqual(t.step?.title, "Tap a food.")
        w.trayOut = true
        act(w); XCTAssertFalse(t.active); XCTAssertTrue(d.bool(forKey: Tutorial.hungryKey))
    }

    func testHungryReminderWithAnEmptyBagPointsAtGoOut() {
        let d = TutorialDriver.suite("hungrynofood"), t = Tutorial(); t.defaults = d; t.now = { TutorialDriver.clock }
        d.set("done", forKey: Tutorial.stateKey)
        t.maybeStartHungry(world: hungryWorld())
        func act(_ w: TutorialWorld) { TutorialDriver.clock = TutorialDriver.clock.addingTimeInterval(1); t.now = { TutorialDriver.clock }; t.tick(world: w) }
        var w = hungryWorld(); w.targets = ["care"]
        w.menuOpen = true
        act(w); XCTAssertEqual(t.step?.id, "hungry.feed")
        w.targets = ["feed", "feed-empty"]
        act(w); XCTAssertEqual(t.step?.id, "hungry.nofood")
        XCTAssertEqual(t.step?.target, "goout")
        w.targets = ["goout"]; w.townOpen = true
        act(w); XCTAssertFalse(t.active)
    }

    // MARK: tips wait

    func testTipCardsAreHeldWhileAStepIsUp() {
        let t = FirstDayTour.shared
        Tutorial.shared.reset()
        XCTAssertFalse(t.holdsGame)
        Tutorial.shared.begin(name: "Lemon", replay: true, run: false)
        XCTAssertTrue(t.holdsGame, "TipContext.tour reads this: tips wait")
        var ctx = TipContext(); ctx.tour = t.holdsGame
        XCTAssertTrue(ctx.blocked)
        Tutorial.shared.reset()
        XCTAssertFalse(t.holdsGame)
    }

    func testShowTipsAgainLeavesTheTutorialAlone() {
        let d = TutorialDriver.suite("tips"); d.set("done", forKey: Tutorial.stateKey); d.set(true, forKey: FirstDayTour.doneKey)
        let b = TipBook(defaults: d); b.resetFlags()
        XCTAssertEqual(d.string(forKey: Tutorial.stateKey), "done"); XCTAssertTrue(d.bool(forKey: FirstDayTour.doneKey))
    }

    // MARK: touches

    private let spot = CoachSpot(rect: CGRect(x: 300, y: 700, width: 72, height: 72), shape: .capsule)
    private func spotStep() -> TutorialStep { Tutorial.homeSteps.first { $0.id == "care.heart" }! }

    func testIdleTutorialTakesNoTouchAnywhere() {
        for p in [CGPoint(x: 5, y: 5), CGPoint(x: 336, y: 736), CGPoint(x: 200, y: 400)] {
            XCTAssertFalse(TutorialPolicy.swallows(nil, spot: nil, cardFrame: .zero, at: p))
            XCTAssertFalse(TutorialPolicy.swallows(nil, spot: spot, cardFrame: CGRect(x: 0, y: 0, width: 400, height: 900), at: p))
        }
    }

    func testTouchesPassOnlyThroughTheSpotlightHole() {
        let card = CGRect(x: 20, y: 500, width: 340, height: 140)
        let s = spotStep()
        XCTAssertFalse(TutorialPolicy.swallows(s, spot: spot, cardFrame: card, at: CGPoint(x: 336, y: 736)), "the middle of the control goes through")
        XCTAssertFalse(TutorialPolicy.swallows(s, spot: spot, cardFrame: card, at: CGPoint(x: 336, y: 700 - Coach.ringGap + 2)), "inside the ring's gap goes through")
        XCTAssertTrue(TutorialPolicy.swallows(s, spot: spot, cardFrame: card, at: CGPoint(x: 336, y: 700 - Coach.ringGap - 4)), "outside the ring is blocked")
        XCTAssertTrue(TutorialPolicy.swallows(s, spot: spot, cardFrame: card, at: CGPoint(x: 100, y: 100)))
        XCTAssertTrue(TutorialPolicy.swallows(s, spot: spot, cardFrame: card, at: CGPoint(x: 100, y: 560)), "the card takes its own touches")
        // the ring is round: the square corner of the control's box is outside it
        XCTAssertTrue(TutorialPolicy.swallows(s, spot: spot, cardFrame: card, at: CGPoint(x: 300 - Coach.ringGap + 1, y: 700 - Coach.ringGap + 1)), "a circle's hole has round corners")
    }

    func testButtonCardsTakeEveryTouchAndActionCardsOnlyTheirOwn() {
        let intro = Tutorial.homeSteps.first { $0.id == "intro" }!, rub = Tutorial.homeSteps.first { $0.id == "cuddle.rub" }!
        let card = CGRect(x: 20, y: 500, width: 340, height: 140)
        XCTAssertTrue(TutorialPolicy.swallows(intro, spot: spot, cardFrame: card, at: CGPoint(x: 336, y: 736)), "the intro's ring does not let a tap through")
        XCTAssertFalse(TutorialPolicy.swallows(rub, spot: nil, cardFrame: card, at: CGPoint(x: 200, y: 300)), "rubbing needs the whole screen")
        XCTAssertTrue(TutorialPolicy.swallows(rub, spot: nil, cardFrame: card, at: CGPoint(x: 100, y: 560)))
        XCTAssertFalse(TutorialPolicy.swallows(spotStep(), spot: nil, cardFrame: card, at: CGPoint(x: 200, y: 300)), "a control that is not there blocks nothing")
    }

    // MARK: concentric

    func testEveryCardLineIsATitleWithAtMostOneBodyLine() {
        for s in Tutorial.homeSteps + Tutorial.hungrySteps + [Tutorial.hungryFood, Tutorial.hungryNoFood] where s.kind != .arrival {
            XCTAssertNotNil(s.title, "\(s.id) has a title: one header type on every card")
        }
        XCTAssertEqual(Coach.disc, 40)
    }

    func testConcentricRules() {
        XCTAssertEqual(Coach.innerRadius(), Coach.cardRadius - Coach.inset)
        XCTAssertEqual(Coach.innerRadius(outer: 10, inset: 16), 0, "never below square")
        let circle = CoachSpot(rect: CGRect(x: 0, y: 0, width: 72, height: 72), shape: .capsule)
        XCTAssertEqual(circle.controlRadius, 36); XCTAssertEqual(circle.holeRadius, 36 + Coach.ringGap)
        XCTAssertEqual(circle.hole.width / 2, circle.holeRadius, "a circle's ring is a circle round the same centre")
        XCTAssertEqual(circle.hole.midX, circle.rect.midX)
        let box = CoachSpot(rect: CGRect(x: 0, y: 0, width: 90, height: 60), shape: .rounded(16))
        XCTAssertEqual(box.holeRadius, 16 + Coach.ringGap)
        let pill = CoachSpot(rect: CGRect(x: 0, y: 0, width: 160, height: 44), shape: .capsule)
        XCTAssertEqual(pill.holeRadius, 22 + Coach.ringGap)
        XCTAssertEqual(CoachShape.rounded(100).radius(for: CGRect(x: 0, y: 0, width: 40, height: 40)), 20, "a radius is never more than half the side")
        XCTAssertGreaterThanOrEqual(Coach.minTap, 44)
    }

    // MARK: placement

    private let sizes: [(String, CGSize, UIEdgeInsets)] = [
        ("portrait", CGSize(width: 393, height: 852), UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)),
        ("landscape", CGSize(width: 852, height: 393), UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)),
        ("small", CGSize(width: 320, height: 568), UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)),
        ("ipad", CGSize(width: 1024, height: 1366), UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)),
    ]

    func testTheCardStaysOnScreenAndClearOfTheRingAtEveryHeight() {
        for (name, size, safe) in sizes {
            for natural in [120.0, 220, 380, 900] {
                for spotRect in [CGRect(x: size.width - 90, y: size.height - 140, width: 72, height: 72), CGRect(x: 20, y: safe.top + 20, width: 100, height: 44), CGRect(x: size.width / 2 - 60, y: size.height / 2 - 60, width: 120, height: 120)] {
                    let sp = CoachSpot(rect: spotRect, shape: .capsule)
                    let r = TutorialPlacement.place(size: size, safe: safe, spot: sp, place: .top, natural: CGFloat(natural), wide: false, avoid: nil)
                    let bounds = CGRect(origin: .zero, size: size)
                    XCTAssertTrue(bounds.insetBy(dx: safe.left, dy: safe.top).contains(CGPoint(x: r.frame.minX, y: r.frame.minY)) || r.frame.minY >= safe.top, "\(name) \(natural) origin")
                    XCTAssertLessThanOrEqual(r.frame.maxY, size.height - safe.bottom + 0.5, "\(name) natural \(natural): bottom")
                    XCTAssertGreaterThanOrEqual(r.frame.minY, safe.top - 0.5, "\(name) natural \(natural): top")
                    XCTAssertGreaterThanOrEqual(r.frame.minX, safe.left - 0.5); XCTAssertLessThanOrEqual(r.frame.maxX, size.width - safe.right + 0.5)
                    XCTAssertFalse(r.frame.intersects(sp.hole), "\(name) natural \(natural): the card is over the ring \(r.frame) \(sp.hole)")
                    XCTAssertLessThanOrEqual(r.frame.height, max(natural, 0) + 0.5)
                    if natural > size.height - safe.top - safe.bottom { XCTAssertLessThan(r.frame.height, CGFloat(natural), "\(name): too tall a card scrolls instead of growing off screen") }
                }
            }
        }
    }

    func testTheCardKeepsOffTheJelmiko() {
        let size = CGSize(width: 393, height: 852), safe = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let sp = CoachSpot(rect: CGRect(x: 321, y: 740, width: 56, height: 56), shape: .capsule)
        let him = CGPoint(x: 200, y: 560)
        let r = TutorialPlacement.place(size: size, safe: safe, spot: sp, place: .top, natural: 130, wide: false, avoid: him)
        XCTAssertFalse(r.frame.insetBy(dx: -40, dy: -50).contains(him), "\(r.frame)")
    }

    func testCardsWithNoRingStandLowOrHigh() {
        let size = CGSize(width: 393, height: 852), safe = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let low = TutorialPlacement.place(size: size, safe: safe, spot: nil, place: .low, natural: 150, wide: false, avoid: nil)
        XCTAssertGreaterThan(low.frame.minY, size.height * 0.6)
        let top = TutorialPlacement.place(size: size, safe: safe, spot: nil, place: .top, natural: 150, wide: false, avoid: nil)
        XCTAssertLessThan(top.frame.minY, size.height * 0.25)
        let l = TutorialPlacement.place(size: CGSize(width: 852, height: 393), safe: UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59), spot: nil, place: .low, natural: 150, wide: false, avoid: nil)
        XCTAssertGreaterThan(l.frame.midX, 852 / 2, "landscape: on the right edge, clear of the Jelmiko in the middle")
    }

    func testPinnedAndBesideCards() {
        let size = CGSize(width: 393, height: 852), safe = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let row = CoachSpot(rect: CGRect(x: 230, y: 700, width: 150, height: 44), shape: .capsule)
        let p = TutorialPlacement.place(size: size, safe: safe, spot: row, place: .top, natural: 130, wide: false, avoid: nil, pinned: true)
        XCTAssertLessThan(p.frame.maxY, 400, "a pinned card stands at the top, clear of the menu's rows")
        XCTAssertNil(p.pointer)
        let rail = CoachSpot(rect: CGRect(x: 24, y: 690, width: 56, height: 56), shape: .capsule)
        let b = TutorialPlacement.place(size: size, safe: safe, spot: rail, place: .top, natural: 130, wide: false, avoid: nil, beside: true)
        XCTAssertGreaterThan(b.frame.minX, rail.hole.maxX, "beside the rail button, not over it")
        XCTAssertFalse(b.frame.intersects(rail.hole))
        XCTAssertLessThanOrEqual(b.frame.maxY, size.height - safe.bottom - 100 + 0.5, "not down over the heart and the name chip")
    }
}

private extension Tutorial {
    func with(_ d: UserDefaults) -> Tutorial { defaults = d; return self }
}
