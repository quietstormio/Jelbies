//
//  GlitchTour.swift
//  glitch-hunt-r1 (2026-11-24). DEV BUILDS ONLY (compiled out of the App Store archive). A fixed-order tour of every scene and the common activities, for the glitch probe
//  (Melon/GlitchProbe.swift) to watch: `-GlitchTour 1` (all steps) or `-GlitchTour "idle:120;cuddle;park"` (those steps). Each step is logged `[glitch] tour step=<name>` and tags
//  every probe line (`tag=<name>`). `[glitch] tour done` at the end.
//

#if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
import SwiftUI
import UIKit
import simd

@MainActor
enum GlitchTour {
    static let full = "idle:120;cuddle;comeall;wash;play;feed;water;idle:30;park;cafe;groom;race;show;volley;idle:60"

    static func run(care: GameCare) async {
        guard DevArgs.enabled else { return }
        let d = UserDefaults.standard
        func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(max(0, s) * 1e9)) }
        for _ in 0..<900 where LaunchGate.shared.visible || care.lastBrain == nil { await sleep(0.1) }
        await sleep(3)
        var script = d.string(forKey: "GlitchTour") ?? "1"
        if script == "1" { script = full }
        NSLog("[glitch] tour start %@", script)
        for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !step.isEmpty {
            let kv = step.split(separator: ":", maxSplits: 1).map(String.init)
            GlitchProbe.shared.tag = kv[0]
            NSLog("[glitch] tour step=%@", step)
            await act(kv[0], arg: kv.count > 1 ? Double(kv[1]) : nil, care: care, sleep: sleep)
        }
        GlitchProbe.shared.tag = "end"
        NSLog("[glitch] tour done")
    }

    private static func hungry(_ care: GameCare) { for j in care.jellies { care.needs(for: j.id).set(.hunger, 0.15); care.needs(for: j.id).set(.thirst, 0.15) } }
    private static func screenSize() -> CGSize? { (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size }

    static func act(_ a: String, arg: Double?, care: GameCare, sleep: (Double) async -> Void) async {
        switch a {
        case "idle": await sleep(arg ?? 60)
        case "cuddle":
            care.comeHere(jelly: 0)
            for _ in 0..<200 where !care.focus.isFocused { await sleep(0.1) }
            await sleep(arg ?? 15)
            withAnimation(CareMenu.spring) { care.release() }
            await sleep(10)
        case "comeall":
            care.comeHereEveryone()
            for _ in 0..<200 where !care.focus.isFocused { await sleep(0.1) }
            await sleep(arg ?? 10)
            withAnimation(CareMenu.spring) { care.release() }
            await sleep(10)
        case "wash":
            care.bath.grime.dirt = 0.5; care.bath.demo = true
            care.clean(jelly: 0)
            for _ in 0..<900 where care.bath.active { await sleep(0.2) }
            await sleep(8)
        case "play":
            care.store.grant(DecorKind.ball.storeID); care.beginPlay(ball: .ball)
            var r: UInt64 = 7
            func unit() -> Double { r = r &* 6364136223846793005 &+ 1442695040888963407; return Double((r >> 33) % 1000) / 1000 }
            for _ in 0..<Int(arg ?? 8) {
                await sleep(4)
                if care.play.phase == .inHand, let size = screenSize() {
                    care.play.viewSize = size
                    care.play.flick(from: CGPoint(x: size.width * (0.3 + 0.4 * unit()), y: size.height * 0.82), velocity: CGVector(dx: (unit() - 0.5) * size.width, dy: -size.height * (1.2 + unit())))
                }
            }
            care.endPlay()
            await sleep(8)
        case "feed":
            hungry(care); care.feed()
            await sleep(arg ?? 45)
        case "water":
            hungry(care); care.water()
            await sleep(arg ?? 35)
        case "park":
            care.requestPark()
            await sleep(1)
            if care.park.picking { care.startPark() }
            await sleep(arg ?? 90)
            if care.park.active { care.park.goHome() }
            for _ in 0..<600 where care.park.active { await sleep(0.2) }
            await sleep(6)
        case "cafe":
            care.bath.wallet.add(60, silent: true)
            care.requestCafe()
            for _ in 0..<300 where !care.cafe.menuOpen && care.cafe.active { await sleep(0.1) }
            if care.cafe.menuOpen {
                await sleep(2)
                let menu: [CafeTreatID] = [.swirl, .juice, .latte, .cocoa, .pancakes]
                var k = 0
                _ = care.orderCafe(CafeOrder(picks: Dictionary(uniqueKeysWithValues: care.cafeDinerIDs.map { id in k += 1; return (id, care.cafeCanEat(id) ? menu[k % menu.count] : .juice) })))
            }
            await sleep(arg ?? 60)
            if care.cafe.active { care.cafe.goHome() }
            for _ in 0..<600 where care.cafe.active { await sleep(0.2) }
            await sleep(6)
        case "groom":
            care.bath.wallet.add(40, silent: true)
            care.requestGroom()
            await sleep(1)
            care.startGroom(.quick)
            for _ in 0..<900 where care.groom.active { await sleep(0.2) }
            await sleep(6)
        case "show":
            care.show.auto = true; care.show.autoHomeAfter = 3
            care.startShow(jelly: 0)
            for _ in 0..<1800 where care.show.active { await sleep(0.2) }
            await sleep(6)
        case "race":
            care.race.autoRate = 4; care.race.autoReturnAfter = 7
            care.startRace(jelly: 0)
            for _ in 0..<1500 where care.race.active { await sleep(0.2) }
            await sleep(6)
        case "volley":
            care.startVolley(jelly: 0, mode: .match(.sandcastle))
            await sleep(arg ?? 60)
            if care.volley.active { care.volley.goHome() }
            for _ in 0..<600 where care.volley.active { await sleep(0.2) }
            await sleep(6)
        default: NSLog("[glitch] tour unknown step %@", a)
        }
    }
}
#endif
