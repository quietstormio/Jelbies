//
//  TipBookTests.swift
//  First-time tips (Start/TipBook.swift): one card at a time, 1.5 s apart, only while its screen is open; the flag is written when the card appears; "Show tips again" clears the tip
//  flags and nothing else; nothing shows (and a shown card hides) during a race / Show / match / meal / the first-day tour; the Camp card waits for somebody at Camp; the card text lint.
//

import XCTest
@testable import BobV1

@MainActor
final class TipBookTests: XCTestCase {
    private var t0 = Date(timeIntervalSince1970: 1_000)
    private func make(_ name: String = #function) -> (TipBook, UserDefaults, () -> Void) {
        let n = "TipBookTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        let b = TipBook(defaults: d)
        t0 = Date(timeIntervalSince1970: 1_000)
        b.now = { [unowned self] in self.t0 }
        return (b, d, { d.removePersistentDomain(forName: n) })
    }

    func testRequestTwiceIsOneCardAndTheFlagIsWrittenWhenItAppears() {
        let (b, d, done) = make(); defer { done() }
        b.screenOpened("feed")
        b.request("feed"); b.request("feed")
        XCTAssertEqual(b.queue, ["feed"])
        XCTAssertFalse(d.bool(forKey: TipBook.key("feed")), "queued is not shown: no flag yet")
        b.tick()
        XCTAssertEqual(b.current, "feed")
        XCTAssertTrue(d.bool(forKey: TipBook.key("feed")), "written on appear, before any Got it")
        b.request("feed")
        XCTAssertTrue(b.queue.isEmpty, "never again")
        b.dismiss(); t0 += 10; b.request("feed"); b.tick()
        XCTAssertNil(b.current); XCTAssertTrue(b.queue.isEmpty)
    }

    func testAFreshBookKeepsTheFlagAcrossRelaunch() {
        let (b, d, done) = make(); defer { done() }
        b.screenOpened("shop"); b.request("shop"); b.tick()
        let b2 = TipBook(defaults: d)
        b2.screenOpened("shop"); b2.request("shop"); b2.tick()
        XCTAssertNil(b2.current, "a card shown once stays shown once, even if the app was closed under it")
    }

    func testOneAtATimeThenTheNextWaitsOnePointFiveSeconds() {
        let (b, _, done) = make(); defer { done() }
        b.screenOpened("town"); b.screenOpened("shop")
        b.request("town"); b.request("shop")
        b.tick(); XCTAssertEqual(b.current, "town")
        t0 += 5; b.tick(); XCTAssertEqual(b.current, "town", "one at a time: the shop card never stacks")
        b.dismiss()
        t0 += 1.4; b.tick(); XCTAssertNil(b.current, "1.4 s after Got it is too early")
        t0 += 0.2; b.tick(); XCTAssertEqual(b.current, "shop", "1.6 s after Got it")
    }

    func testTheNextOnlyShowsIfItsScreenIsStillOpen() {
        let (b, d, done) = make(); defer { done() }
        b.screenOpened("town"); b.screenOpened("shop")
        b.request("town"); b.request("shop")
        b.tick(); b.dismiss()
        b.screenClosed("shop")          // the player left the Shop
        t0 += 2; b.tick()
        XCTAssertNil(b.current); XCTAssertEqual(b.queue, ["shop"], "stays queued for the next time that screen opens")
        XCTAssertFalse(d.bool(forKey: TipBook.key("shop")), "no flag for a card that never showed")
        b.screenOpened("shop"); b.tick()
        XCTAssertEqual(b.current, "shop")
    }

    func testLeavingTheScreenHidesTheCardAndTheFlagStays() {
        let (b, d, done) = make(); defer { done() }
        b.screenOpened("race"); b.request("race"); b.tick()
        b.screenClosed("race")
        XCTAssertNil(b.current); XCTAssertTrue(d.bool(forKey: TipBook.key("race")))
    }

    func testNothingShowsDuringARaceAShowAMatchAMealOrTheTour() {
        let cases: [(String, (inout TipContext) -> Void)] = [
            ("race", { $0.race = true }), ("show", { $0.show = true }), ("volley", { $0.volley = true }), ("raceWait", { $0.raceWait = true }),
            ("meal", { $0.meal = true }), ("tour", { $0.tour = true }), ("introHold", { $0.introHold = true }), ("cutscene", { $0.cutscene = true }),
            ("focus", { $0.focus = true }), ("nightSkip", { $0.nightSkip = true }), ("arranging", { $0.arranging = true })]
        for (name, set) in cases {
            let (b, d, done) = make(name); defer { done() }
            var ctx = TipContext(); set(&ctx)
            XCTAssertTrue(ctx.blocked, name)
            b.context = { ctx }
            b.screenOpened("town"); b.request("town"); b.tick()
            XCTAssertNil(b.current, "\(name): no card")
            XCTAssertFalse(d.bool(forKey: TipBook.key("town")), "\(name): no flag while blocked")
            ctx = TipContext(); b.context = { ctx }; b.tick()
            XCTAssertEqual(b.current, "town", "\(name): it comes once the game is free")
        }
    }

    func testACardOnScreenHidesWhenARaceStartsUnderIt() {
        let (b, _, done) = make(); defer { done() }
        var ctx = TipContext(); b.context = { ctx }
        b.screenOpened("park"); b.request("park"); b.tick(); XCTAssertEqual(b.current, "park")
        ctx.race = true; b.tick(); XCTAssertNil(b.current)
    }

    func testAHoldLikeSettingsOrAHelpSheetBlocksToo() {
        let (b, _, done) = make(); defer { done() }
        b.hold("settings", true)
        b.screenOpened("town"); b.request("town"); b.tick(); XCTAssertNil(b.current)
        b.hold("settings", false); b.tick(); XCTAssertEqual(b.current, "town")
    }

    func testTheCampCardWaitsForSomebodyAtCamp() {
        let (b, _, done) = make(); defer { done() }
        b.screenOpened("camp")
        b.request("camp", when: false); XCTAssertTrue(b.queue.isEmpty, "the empty yard asks for nothing")
        b.tick(); XCTAssertNil(b.current)
        b.request("camp", when: true); b.tick(); XCTAssertEqual(b.current, "camp")
    }

    func testShowTipsAgainClearsTipFlagsOnly() {
        let (b, d, done) = make(); defer { done() }
        d.set(true, forKey: FirstDayTour.doneKey); d.set(3, forKey: "FocusHintSeen"); d.set(true, forKey: "IntroSeen.v1")
        for id in TipBook.ids { d.set(true, forKey: TipBook.key(id)) }
        b.screenOpened("shop"); b.request("shop", when: true)
        b.resetFlags()
        for k in TipBook.allKeys { XCTAssertFalse(d.bool(forKey: k), k) }
        XCTAssertTrue(d.bool(forKey: FirstDayTour.doneKey), "the first-day tour is not reset")
        XCTAssertEqual(d.integer(forKey: "FocusHintSeen"), 3); XCTAssertTrue(d.bool(forKey: "IntroSeen.v1"))
        XCTAssertTrue(b.queue.isEmpty && b.current == nil, "the queue is emptied")
        b.screenOpened("shop"); b.request("shop"); b.tick(); XCTAssertEqual(b.current, "shop", "and the cards show again")
    }

    func testEveryCardHasAFlagAndTheKeysAreOnePerCard() {
        XCTAssertEqual(Set(TipBook.cards.map(\.id)), Set(TipBook.ids))
        XCTAssertEqual(TipBook.allKeys.count, TipBook.cards.count)
        XCTAssertEqual(TipBook.key("feed"), "Jelbies.tip.feed.v1")
    }

    func testAWipeTakesTheTipFlagsWithTheRestOfTheDomain() {
        // wipeAll empties the app's whole defaults domain (StartFlow.wipeAll): the tip keys are in that domain (UserDefaults.standard), like Jelbies.firstDayTour.done.v1.
        let d = UserDefaults.standard
        d.set(true, forKey: TipBook.key("feed"))
        StartFlow.wipeAll()
        XCTAssertFalse(d.bool(forKey: TipBook.key("feed")))
        XCTAssertFalse(d.bool(forKey: FirstDayTour.doneKey))
    }

    func testCardTextLint() {
        for c in TipBook.cards {
            let all = c.title + " " + c.body
            XCTAssertFalse(all.contains("Jelmikos"), all); XCTAssertFalse(all.contains("Jelbie"), all); XCTAssertFalse(all.lowercased().contains("rival"), all)
            XCTAssertFalse(all.lowercased().contains("coins") && !all.contains("JellyCoins"), "money is always JellyCoins: \(all)")
            XCTAssertLessThanOrEqual(c.body.split(separator: " ").count, 16, c.body)          // (the design says 10 to 15; its own Feeding text is 16)
            XCTAssertFalse(c.title.isEmpty); XCTAssertFalse(c.symbol.isEmpty)
        }
        XCTAssertEqual(TipBook.card("town")?.body, "Race, dance and play to earn JellyCoins. Spend them in the Shop.")
        XCTAssertEqual(TipBook.card("camp")?.body, "When home is full, the others wait here. Tap one to bring them home.")
    }

    func testLaunchArgumentsAreDevOnly() {
        let n = "TipBookTests.args.\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!; defer { d.removePersistentDomain(forName: n) }
        d.set(1, forKey: "TipsReset"); d.set("town", forKey: "TipShow")
        XCTAssertEqual(TipBook.launchOverrides(devArgs: false, defaults: d).reset, false)
        XCTAssertNil(TipBook.launchOverrides(devArgs: false, defaults: d).show)
        XCTAssertTrue(TipBook.launchOverrides(devArgs: true, defaults: d).reset)
        XCTAssertEqual(TipBook.launchOverrides(devArgs: true, defaults: d).show, "town")
    }

    func testForcedCardIgnoresItsFlagAndTheGapButNotTheSuppression() {
        let n = "TipBookTests.forced.\(UUID().uuidString)"; let launch = UserDefaults(suiteName: n)!; defer { launch.removePersistentDomain(forName: n) }
        launch.set("shop", forKey: "TipShow")
        let (b, d, done) = make(); defer { done() }
        d.set(true, forKey: TipBook.key("shop"))
        b.applyLaunchOverrides(devArgs: true, launch: launch)
        var ctx = TipContext(); ctx.race = true; b.context = { ctx }
        b.screenOpened("shop"); b.request("shop"); b.tick(); XCTAssertNil(b.current, "suppression still holds")
        ctx.race = false; b.tick(); XCTAssertEqual(b.current, "shop", "shown although the flag was set")
    }

    func testPlacementKeepsOffFacesAndStaysClearOfTheBottomBar() {
        let size = CGSize(width: 402, height: 874), safe = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        let room = TipPlace.of("feed")
        // top rule: the message bar's band: y = safe top + 60 = 122, left margin x = 16
        XCTAssertEqual(TipPlacement.origin(room, size: size, safe: safe, heads: [], h: 122), CGPoint(x: 16, y: 122))
        // a head under the card: the card tries the left edge, then the right edge
        let head = CGPoint(x: 200, y: 200)
        let moved = TipPlacement.origin(room, size: size, safe: safe, heads: [head], h: 122)
        XCTAssertNil(moved, "a head in the middle is within 40 pt sideways of every spot: wait")
        let side = TipPlacement.origin(room, size: size, safe: safe, heads: [CGPoint(x: 200, y: 330)], h: 122)
        XCTAssertNotNil(side)
        XCTAssertEqual(TipPlacement.origin(TipPlace.of("town"), size: size, safe: safe, heads: [], h: 122), CGPoint(x: 31, y: 874 - 34 - 12 - 122), "town: bottom 828")
        XCTAssertEqual(TipPlacement.origin(TipPlace.of("race"), size: size, safe: safe, heads: [], h: 122)?.y, 764 - 122, "race: bottom 764")
        XCTAssertEqual(TipPlacement.origin(TipPlace.of("park"), size: size, safe: safe, heads: [], h: 122)?.y, 122)
    }

    func testLandscapeIPhoneHoldsTheQueueAndPortraitThenShowsTheCard() {
        let (b, d, done) = make(); defer { done() }
        var land = true; b.landscapePhone = { land }
        b.screenOpened("shop"); b.request("shop"); b.tick()
        XCTAssertNil(b.current, "landscape: no card")
        XCTAssertFalse(d.bool(forKey: TipBook.key("shop")), "landscape: no flag written")
        XCTAssertEqual(b.queue, ["shop"], "it waits in the queue")
        land = false; t0 += 5; b.tick()
        XCTAssertEqual(b.current, "shop", "back in portrait with its screen still open: it shows")
        XCTAssertTrue(d.bool(forKey: TipBook.key("shop")))
    }

    func testPortraitCardStillObeysTheGapAfterALandscapeHold() {
        let (b, _, done) = make(); defer { done() }
        var land = false; b.landscapePhone = { land }
        b.screenOpened("town"); b.screenOpened("shop"); b.request("town"); b.request("shop")
        b.tick(); b.dismiss(); land = true; t0 += 2; b.tick(); XCTAssertNil(b.current)
        land = false; b.tick(); XCTAssertEqual(b.current, "shop", "the gap had passed while held; one at a time still holds")
    }

    func testRotatingToLandscapeWithACardUpDismissesItAndKeepsItsFlag() {
        let (b, d, done) = make(); defer { done() }
        var land = false; b.landscapePhone = { land }
        b.screenOpened("spring"); b.request("spring"); b.tick(); XCTAssertEqual(b.current, "spring")
        land = true; b.tick()
        XCTAssertNil(b.current, "dismissed")
        XCTAssertTrue(d.bool(forKey: TipBook.key("spring")), "its flag stays: it counts as seen")
        land = false; t0 += 5; b.tick(); XCTAssertNil(b.current, "it does not come back")
        XCTAssertTrue(b.queue.isEmpty)
    }
}
