//
//  MonkeySoak.swift
//  no-stuck-r1. DEV BUILDS ONLY (compiled out of the App Store archive). A seeded "monkey" that plays the game with random but legal input for long soaks, with the
//  stuck detector (Dev/StuckDetector.swift) watching:
//      -Monkey <seed>  [-MonkeyMinutes <wall minutes, default 60>]  [-MonkeyGap <mean s between actions, default 6>]
//      -MonkeyScript "comeall;wait:2.5;cancel;wait:60"   runs those steps instead (a case found by a soak, replayed for a video)
//  Each step is logged `[monkey] n=<n> act=<name> sim=<game s>`. The same seed gives the same sequence of choices (the game's own timing may differ).
//  Background / foreground is driven from the shell (simctl), the rest from here. `-FreezeFix 0` / `-MealUnstickOff 1` switch the old bugs back on (baselines).
//

#if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
import SwiftUI
import UIKit
import simd

@MainActor
enum MonkeySoak {
    struct LCG { var s: UInt64; mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(max(n, 1))) }
        mutating func unit() -> Double { Double(next(1_000_000)) / 1_000_000 } }

    struct Bindings { let open: Binding<Bool>; let roster: Binding<Bool>; let picker: Binding<ConsumableKind?>; let book: Binding<Bool>; let goOut: Binding<TownScreen?> }

    /// (name, weight): the soak's menu of actions.
    static let menu: [(String, Int)] = [
        ("comecancel", 12), ("welcomeplayfeed", 6), ("feed", 8), ("water", 8), ("feedone", 4), ("drinkone", 4), ("come", 4), ("comeall", 3), ("cuddle", 6),
        ("wash", 4), ("play", 8), ("menu", 6), ("picker", 4), ("roster", 2), ("book", 2), ("town", 5), ("park", 3), ("cafe", 3), ("groom", 2), ("show", 2),
        ("race", 2), ("volley", 2), ("music", 3), ("rotate", 3), ("idle", 10), ("quiet", 3), ("cancel", 3), ("release", 3),
    ]

    /// `-MonkeyStress 1`: extra overlapping inputs (a separate menu, so the default soak above stays comparable between rounds).
    static let stressMenu: [(String, Int)] = [
        ("comeduringmeal", 8), ("playthencome", 6), ("doublefeed", 5), ("bedtime", 4), ("trick", 6), ("washduringplay", 3), ("feedduringplay", 5), ("comecancel", 8),
        ("welcomeplayfeed", 5), ("cuddle", 4), ("play", 4), ("feed", 3), ("water", 3), ("park", 2), ("show", 2), ("race", 2), ("music", 2), ("rotate", 2), ("idle", 6), ("quiet", 2),
    ]

    static func run(care: GameCare, ui: Bindings) async {
        guard DevArgs.enabled else { return }
        let d = UserDefaults.standard
        func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(max(0, s) * 1e9)) }
        for _ in 0..<900 where LaunchGate.shared.visible || care.lastBrain == nil { await sleep(0.1) }
        if d.object(forKey: "FreezeFix") != nil, d.integer(forKey: "FreezeFix") == 0 { FocusGroup.handBackFix = false; FocusGroup.netEnabled = false; NSLog("[freeze] FIX OFF (hand-back and safety net)") }
        if !GameCare.unstickOn { NSLog("[mealunstick] UNSTICK OFF") }
        if !GameCare.stuckReleaseOn { NSLog("[stuck] RELEASE GUARD OFF") }
        StuckDetector.on = true
        await sleep(3)
        let seed = UInt64(max(1, d.integer(forKey: "Monkey")))
        var g = LCG(s: seed &* 2654435761)
        var n = 0
        func sim() -> Float { StuckDetector.shared.simTime }
        func say(_ a: String) { n += 1; NSLog("[monkey] n=%d act=%@ sim=%.0f", n, a, sim()) }

        if let script = d.string(forKey: "MonkeyScript") {
            NSLog("[monkey] script %@", script)
            for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !step.isEmpty {
                let kv = step.split(separator: ":", maxSplits: 1).map(String.init)
                if kv[0] == "wait" { await sleep(Double(kv.count > 1 ? kv[1] : "1") ?? 1); continue }
                say(step)
                await act(kv[0], arg: kv.count > 1 ? Int(kv[1]) : nil, care: care, ui: ui, g: &g, sleep: sleep)
            }
            NSLog("[monkey] done script")
            return
        }
        let minutes = d.double(forKey: "MonkeyMinutes") > 0 ? d.double(forKey: "MonkeyMinutes") : 60
        let gap = d.double(forKey: "MonkeyGap") > 0 ? d.double(forKey: "MonkeyGap") : 6
        let end = Date().addingTimeInterval(minutes * 60)
        let menu = d.integer(forKey: "MonkeyStress") != 0 ? Self.stressMenu : Self.menu
        let total = menu.reduce(0) { $0 + $1.1 }
        NSLog("[monkey] start seed=%llu minutes=%.0f gap=%.1f", seed, minutes, gap)
        var awayT = 0.0
        while Date() < end {
            var r = g.next(total), pick = menu[0].0
            for (name, w) in menu { if r < w { pick = name; break }; r -= w }
            // legal input only: at home with no trip on, the home buttons; during a trip the monkey waits for it (its own trip step brings it home)
            if UIApplication.shared.applicationState != .active { await sleep(1); continue }          // (the app is in the background: nobody can press anything)
            if care.tripActive || care.raceBusy || care.bath.active {          // (the bath's own screen: no care menu)
                // a trip that began after its own step gave up waiting (the park's walk-out procession): the player goes home from it after a while
                awayT += 2
                if awayT > 120 {
                    awayT = 0
                    NSLog("[monkey] home from a trip left running park=%d cafe=%d volley=%d groom=%d race=%d show=%d sim=%.0f", care.park.active ? 1 : 0, care.cafe.active ? 1 : 0, care.volley.active ? 1 : 0, care.groom.active ? 1 : 0, care.race.active ? 1 : 0, care.show.active ? 1 : 0, sim())
                    if care.park.active { care.park.goHome() }
                    if care.cafe.active { care.cafe.goHome() }
                    if care.volley.active { care.volley.goHome() }
                }
                await sleep(2); continue
            }
            awayT = 0
            if let why = illegal(pick, care: care) { NSLog("[monkey] skip act=%@ why=%@ sim=%.0f", pick, why, sim()); await sleep(1); continue }
            say(pick)
            await act(pick, arg: nil, care: care, ui: ui, g: &g, sleep: sleep)
            await sleep(gap * (0.3 + 1.4 * g.unit()))
        }
        NSLog("[monkey] done seed=%llu steps=%d sim=%.0f", seed, n, sim())
    }

    /// The button the action presses is greyed out now (HUDMenu.enabled, the same rule the HUD draws with): a player could not press it.
    static func illegal(_ a: String, care: GameCare) -> String? {
        let item: HUDItem?
        let anyTime: Set<String> = ["release", "cancel", "idle", "quiet", "music", "rotate", "feed", "water"]          // (Feed / Water in a close-up: the voice / widget path, `order()` ends the close-up first)
        if !anyTime.contains(a), care.focus.isActive { return "close-up: the care menu and Town are hidden" }
        switch a {
        case "feed", "feedone", "welcomeplayfeed", "comeduringmeal", "doublefeed": item = .feed
        case "bedtime": item = .bedtime
        case "playthencome", "washduringplay", "feedduringplay": item = .play
        case "water", "drinkone": item = .drink
        case "come", "comecancel", "cuddle": item = .come
        case "comeall": item = .callAll
        case "wash": item = .clean
        case "cancel": return care.cancelPill ? nil : "no Cancel pill"
        case "release": return care.focus.isActive ? nil : "no close-up"
        default: item = nil
        }
        guard let item else { return nil }
        return HUDMenu.enabled(item, .group, care: care) ? nil : "\(item) greyed out"
    }

    /// A Come here / Call everyone press (the detector's tap-no-effect check), as the HUD notes its own.
    static func tap(_ care: GameCare) { StuckDetector.shared.noteTap("come", care: care) }
    static func out(_ a: String, _ r: String) { NSLog("[monkey] out act=%@ %@ sim=%.0f", a, r, StuckDetector.shared.simTime) }

    /// Waits while `on()` (at most `cap` s), and like a player on a trip now and then switches the music off and on or turns the phone.
    static func tripWait(_ cap: Double, g: inout LCG, sleep: (Double) async -> Void, on: () -> Bool) async {
        var t = 0.0
        while on() && t < cap {
            await sleep(1); t += 1
            if Int(t) % 7 == 0, g.next(4) == 0 {
                if g.next(2) == 0 { AudioHub.shared.settings.musicOn = false; NSLog("[monkey] in-trip music off"); await sleep(1 + 4 * g.unit()); AudioHub.shared.settings.musicOn = true; NSLog("[monkey] in-trip music on") }
                else { rotate(&g); NSLog("[monkey] in-trip rotate") }
            }
        }
    }
    static func rotate(_ g: inout LCG) {
        let masks: [UIInterfaceOrientationMask] = [.portrait, .landscapeLeft, .landscapeRight]
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene { scene.requestGeometryUpdate(.iOS(interfaceOrientations: masks[g.next(masks.count)])) { _ in } }
    }

    private static func someJelly(_ care: GameCare, _ g: inout LCG) -> Int { g.next(max(care.jellies.count, 1)) }
    /// The player has the food the Feed button serves (a fresh game's bag can be empty: the tap is then only "No ... left in the bag").
    private static func stock(_ care: GameCare) { if let c = Consumables.with(id: care.selectedFoodID), c.stored, care.store.count(food: c.id) == 0 { care.store.grant(c.id); care.store.grant(c.id) } }
    private static func hungry(_ care: GameCare) { stock(care); for j in care.jellies { care.needs(for: j.id).set(.hunger, 0.15); care.needs(for: j.id).set(.thirst, 0.15) } }

    static func act(_ a: String, arg: Int?, care: GameCare, ui: Bindings, g: inout LCG, sleep: (Double) async -> Void) async {
        let j = arg ?? someJelly(care, &g)
        switch a {
        case "feed", "water":
            hungry(care); if a == "feed" { care.feed() } else { care.water() }
            var ate = false
            for _ in 0..<40 { await sleep(1); if care.raceBook.actors.contains(where: { $0.brain?.activity == .eating || $0.brain?.activity == .drinking }) { ate = true; break }; if !care.trayOut { break } }
            out(a, "ate=\(ate ? 1 : 0) trayOut=\(care.trayOut ? 1 : 0)")
        case "feedone": hungry(care); care.feed(jelly: j)
        case "drinkone": hungry(care); care.drink(jelly: j)
        case "come": tap(care); care.comeHere(jelly: j)
        case "comeall": tap(care); care.comeHereEveryone()
        case "cancel": care.cancelGroupAction()
        case "release": withAnimation(CareMenu.spring) { care.release() }
        case "comecancel":
            tap(care); if g.next(2) == 0 { care.comeHereEveryone() } else { care.comeHere(jelly: j) }
            await sleep(0.5 + 5.5 * g.unit())
            out(a, "phase=\(care.focus.phase)")
            if g.next(3) == 0 { withAnimation(CareMenu.spring) { care.release() } } else { care.cancelGroupAction() }
        case "cuddle":
            tap(care); care.comeHere(jelly: j)
            for _ in 0..<120 where !care.focus.isFocused { await sleep(0.1) }
            out(a, "focused=\(care.focus.isFocused ? 1 : 0)")
            await sleep(2 + 8 * g.unit())
            withAnimation(CareMenu.spring) { care.release() }
        case "welcomeplayfeed":          // the night-meal path: a welcome home, Play, then Feed / Water
            care.showWelcomeHome(j, won: g.next(2) == 0, again: false)
            await sleep(1 + 3 * g.unit())
            care.store.grant(DecorKind.ball.storeID); care.beginPlay(ball: .ball)
            await sleep(2 + 4 * g.unit())
            if g.next(2) == 0 { care.endPlay() }
            hungry(care)
            if g.next(2) == 0 { care.feed() } else { care.water() }
        case "wash":
            care.bath.grime.dirt = 0.5; care.bath.demo = true
            care.clean(jelly: 0)
            await sleep(3 + 20 * g.unit())
            if g.next(3) == 0 { care.cancelClean() }
        case "play":
            let kinds: [DecorKind] = [.ball, .soccerball, .beachball]
            let k = kinds[g.next(kinds.count)]
            care.store.grant(k.storeID); care.beginPlay(ball: k)
            for _ in 0..<(2 + g.next(5)) {
                await sleep(1.5 + 3 * g.unit())
                if care.play.phase == .inHand, let size = screenSize() {
                    care.play.viewSize = size
                    care.play.flick(from: CGPoint(x: size.width * (0.3 + 0.4 * g.unit()), y: size.height * 0.82), velocity: CGVector(dx: (g.unit() - 0.5) * size.width, dy: -size.height * (1.2 + g.unit())))
                }
            }
            if g.next(4) != 0 { care.endPlay() }
        case "menu":
            withAnimation(CareMenu.spring) { ui.open.wrappedValue = true }; await sleep(0.3 + 2 * g.unit())
            withAnimation(CareMenu.spring) { ui.open.wrappedValue = false }
        case "picker":
            ui.picker.wrappedValue = g.next(2) == 0 ? .food : .drink; await sleep(0.5 + 2 * g.unit()); ui.picker.wrappedValue = nil
        case "roster": ui.roster.wrappedValue = true; await sleep(0.5 + 2 * g.unit()); ui.roster.wrappedValue = false
        case "book": ui.book.wrappedValue = true; await sleep(0.5 + 2 * g.unit()); ui.book.wrappedValue = false
        case "town":
            let s: [TownScreen] = [.town, .shop, .track, .studio, .condition, .friends, .volley]
            withAnimation(.easeInOut(duration: 0.25)) { ui.goOut.wrappedValue = s[g.next(s.count)] }
            await sleep(1 + 3 * g.unit())
            withAnimation(.easeInOut(duration: 0.25)) { ui.goOut.wrappedValue = nil }
        case "park":
            care.requestPark()
            await sleep(1)
            if care.park.picking { care.startPark() }
            for _ in 0..<60 where !care.park.active { await sleep(0.25) }          // (the walk-out procession comes first)
            await sleep(1)
            out(a, "entered=\(care.park.active ? 1 : 0)")
            if care.park.picking { care.park.cancelPicker() }
            await tripWait(20 + 60 * g.unit(), g: &g, sleep: sleep) { care.park.active }
            if care.park.active { care.park.goHome() }
            for _ in 0..<600 where care.park.active { await sleep(0.2) }
        case "cafe":
            care.bath.wallet.add(60, silent: true)
            care.requestCafe()
            let cafeWhy = care.cafeBlocker().map { "\($0.message)" }
            for _ in 0..<200 where !care.cafe.menuOpen { await sleep(0.1) }          // (the walk-out / wake comes first)
            if care.cafe.menuOpen {
                await sleep(1 + 2 * g.unit())
                let menu: [CafeTreatID] = [.swirl, .juice, .latte, .cocoa, .pancakes]
                _ = care.orderCafe(CafeOrder(picks: Dictionary(uniqueKeysWithValues: care.cafeDinerIDs.map { ($0, care.cafeCanEat($0) ? menu[g.next(menu.count)] : .juice) })))
            }
            out(a, "entered=\(care.cafe.active ? 1 : 0) why=\(cafeWhy ?? "-")")
            await tripWait(30 + 60 * g.unit(), g: &g, sleep: sleep) { care.cafe.active }
            if care.cafe.active { care.cafe.goHome() }
            for _ in 0..<600 where care.cafe.active { await sleep(0.2) }
        case "groom":
            care.bath.wallet.add(40, silent: true)
            care.requestGroom()
            await sleep(1)
            care.startGroom(.quick)
            for _ in 0..<80 where !care.groom.inScene { await sleep(0.25) }          // (the walk-out / wake comes first)
            out(a, "entered=\(care.groom.inScene ? 1 : 0) why=\(care.groom.picking ? "picker still open" : "-")")
            if care.groom.picking { care.groom.closePicker() }
            await tripWait(180, g: &g, sleep: sleep) { care.groom.active }
        case "show":
            care.show.auto = true; care.show.autoHomeAfter = 3
            let showWhy = care.showBlocker(jelly: j)
            care.startShow(jelly: j)
            for _ in 0..<80 where !care.show.active { await sleep(0.25) }
            out(a, "entered=\(care.show.active ? 1 : 0) why=\(showWhy ?? "-")")
            await tripWait(360, g: &g, sleep: sleep) { care.show.active }
        case "race":
            care.race.autoRate = 4; care.race.autoReturnAfter = 7
            let raceWhy = care.raceBlocker(jelly: j)
            care.startRace(jelly: j)
            for _ in 0..<80 where !care.race.active { await sleep(0.25) }
            out(a, "entered=\(care.race.active ? 1 : 0) why=\(raceWhy ?? "-")")
            await tripWait(300, g: &g, sleep: sleep) { care.race.active }
        case "volley":
            let volleyWhy = care.volleyBlocker(jelly: j, match: true)
            care.startVolley(jelly: j, mode: .match(.sandcastle))
            for _ in 0..<80 where !care.volley.active { await sleep(0.25) }
            out(a, "entered=\(care.volley.active ? 1 : 0) why=\(volleyWhy ?? "-")")
            await tripWait(25 + 40 * g.unit(), g: &g, sleep: sleep) { care.volley.active }
            if care.volley.active { care.volley.goHome() }
            for _ in 0..<600 where care.volley.active { await sleep(0.2) }
        case "music":
            AudioHub.shared.settings.musicOn.toggle()
            await sleep(2 + 6 * g.unit())
            if !AudioHub.shared.settings.musicOn || g.next(2) == 0 { AudioHub.shared.settings.musicOn = true }
        case "rotate": rotate(&g)
        // stress steps (-MonkeyStress 1)
        case "comeduringmeal":
            hungry(care); if g.next(2) == 0 { care.feed() } else { care.water() }
            await sleep(2 + 8 * g.unit())
            tap(care); if g.next(2) == 0 { care.comeHere(jelly: j) } else { care.comeHereEveryone() }
            await sleep(3 + 6 * g.unit())
            if g.next(2) == 0 { withAnimation(CareMenu.spring) { care.release() } } else { care.cancelGroupAction() }
        case "playthencome":
            care.store.grant(DecorKind.ball.storeID); care.beginPlay(ball: .ball)
            await sleep(1 + 4 * g.unit())
            tap(care); care.comeHere(jelly: j)
            await sleep(2 + 6 * g.unit())
            withAnimation(CareMenu.spring) { care.release() }
            if g.next(2) == 0 { care.endPlay() }
        case "doublefeed":
            hungry(care); care.feed(); await sleep(0.2 + g.unit()); care.water(); await sleep(0.3); care.feed(jelly: j)
        case "bedtime":
            _ = care.goodnight()
            await sleep(5 + 20 * g.unit())
            if g.next(2) == 0 { care.cancelGroupAction() }
        case "trick":
            let ts: [VoiceTrick] = [.sit, .jacks, .run, .flip, .look, .spin, .hop]
            let t = ts[g.next(ts.count)]; care.store.grantTrickToEveryone(t)
            _ = care.performTrick(t, jelly: j)
        case "washduringplay":
            care.store.grant(DecorKind.ball.storeID); care.beginPlay(ball: .ball)
            await sleep(2 + 3 * g.unit())
            care.bath.grime.dirt = 0.5; care.bath.demo = true; care.clean(jelly: 0)
            await sleep(5 + 10 * g.unit())
            care.cancelClean(); care.endPlay()
        case "feedduringplay":
            care.store.grant(DecorKind.soccerball.storeID); care.beginPlay(ball: .soccerball)
            await sleep(2 + 4 * g.unit())
            hungry(care); if g.next(2) == 0 { care.feed() } else { care.water() }
            await sleep(3 + 5 * g.unit())
            if g.next(2) == 0 { care.endPlay() }
        // script-only steps (never picked by the soak): the pieces of a found case, for a replay
        case "welcome": care.showWelcomeHome(j, won: true, again: false)
        case "playball": care.store.grant(DecorKind.ball.storeID); care.beginPlay(ball: .ball)
        case "endplay": care.endPlay()
        case "hungry": hungry(care)
        case "idle": await sleep(5 + 25 * g.unit())
        case "quiet": await sleep(120 + 120 * g.unit())          // (the room left alone: longer than any stuck limit)
        default: NSLog("[monkey] unknown step %@", a)
        }
    }

    private static func screenSize() -> CGSize? { (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size }
}
#endif
