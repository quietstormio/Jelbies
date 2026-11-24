//
//  ResultCardLayoutTests.swift
//  The results cards of Jelly Volleyball, Jelly Race and the Jelly Show, HOSTED at real screen sizes (iPhone 17 Pro Max / 17e / SE-size, portrait and landscape; iPad on an iPad
//  simulator) at the default and the largest accessibility text size. The real card views, drawn from real flow objects (a settled VolleyFlow / RaceFlow, a Show played to its
//  results), placed the way the chromes place them (a top-bar band, Spacer, card, Spacer). Fails when any two text frames overlap, any text is cut short (its height is less
//  than it needs at its width), or the "Back home" / title / reward texts are off the screen.
//  With RESULT_CARD_DIR set (xcodebuild: TEST_RUNNER_RESULT_CARD_DIR) it also writes a still of every case; RESULT_CARD_PHASE = "before" / "after" names them.
//

import XCTest
import SwiftUI
import UIKit
@testable import BobV1

@MainActor
final class ResultCardLayoutTests: XCTestCase {

    // MARK: screens

    struct Screen {
        var name: String
        var w: CGFloat, h: CGFloat
        var top: CGFloat, bottom: CGFloat, side: CGFloat
        var landscape: Bool { w > h }
    }
    static var screens: [Screen] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [Screen(name: "ipad-portrait", w: 820, h: 1180, top: 24, bottom: 20, side: 0),
                    Screen(name: "ipad-landscape", w: 1180, h: 820, top: 24, bottom: 20, side: 0)]
        }
        return [Screen(name: "promax-portrait", w: 440, h: 956, top: 62, bottom: 34, side: 0),
                Screen(name: "promax-landscape", w: 956, h: 440, top: 0, bottom: 21, side: 62),
                Screen(name: "17e-portrait", w: 390, h: 844, top: 47, bottom: 34, side: 0),
                Screen(name: "17e-landscape", w: 844, h: 390, top: 0, bottom: 21, side: 47),
                Screen(name: "se-portrait", w: 375, h: 667, top: 20, bottom: 0, side: 0),
                Screen(name: "se-landscape", w: 667, h: 375, top: 0, bottom: 0, side: 0)]
    }

    // MARK: hosting

    final class Box { var infos: [ResultTextInfo] = [] }

    private var window: UIWindow?

    /// Hosts `content` full-screen at `s` and returns the probe frames (screen coordinates inside the safe area) and a still.
    func host<V: View>(_ s: Screen, ax: Bool, @ViewBuilder _ content: @escaping (CGFloat) -> V) -> ([ResultTextInfo], UIImage?) {
        let box = Box()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let sizeClass: UserInterfaceSizeClass = (s.landscape && !isPad) ? .compact : .regular
        let root = ZStack {
            LinearGradient(colors: [Color(red: 0.99, green: 0.84, blue: 0.72), Color(red: 0.33, green: 0.68, blue: 0.70), Color(red: 1.0, green: 0.80, blue: 0.48)], startPoint: .top, endPoint: .bottom)
            ScreenBody(content: content)
                .padding(.top, s.top).padding(.bottom, s.bottom).padding(.horizontal, s.side)
        }
        .ignoresSafeArea()
        .frame(width: s.w, height: s.h)
        .coordinateSpace(name: "resultScreen")
        .environment(\.resultProbeOn, true)
        .environment(\.dynamicTypeSize, ax ? .accessibility5 : .large)
        .environment(\.verticalSizeClass, sizeClass)
        .onPreferenceChange(ResultTextKey.self) { box.infos = $0 }
        let hc = UIHostingController(rootView: root)
        hc.safeAreaRegions = []
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let win = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        win.frame = CGRect(x: 0, y: 0, width: s.w, height: s.h)
        win.rootViewController = hc
        win.isHidden = false
        window = win
        hc.view.frame = win.bounds
        for _ in 0..<6 { hc.view.setNeedsLayout(); hc.view.layoutIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        let img = UIGraphicsImageRenderer(bounds: win.bounds).image { _ in _ = win.drawHierarchy(in: win.bounds, afterScreenUpdates: true) }
        return (box.infos, img)
    }

    /// The chromes' own structure around a results card (VolleyChrome / RaceChrome: topBar, Spacer, card, Spacer), measuring the screen height the same way.
    struct ScreenBody<V: View>: View {
        let content: (CGFloat) -> V
        @State private var h: CGFloat = 0
        var body: some View {
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.7)).frame(width: 240, height: 56).padding(.top, 8)
                Spacer()
                content(h)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14).padding(.bottom, 14)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h = $0 }
        }
    }

    // MARK: checks

    /// What is wrong with this render (empty = fine). `scrolls`: texts below the fold are allowed (the card scrolls inside).
    func problems(_ infos: [ResultTextInfo], _ s: Screen, scrolls: Bool) -> [String] {
        var out: [String] = []
        for i in infos where i.truncated { out.append("truncated: \(i.id) (\(Int(i.actualHeight)) < \(Int(i.idealHeight)))") }
        for a in 0..<infos.count {
            for b in (a + 1)..<max(a + 1, infos.count) {
                let x = infos[a].frame.insetBy(dx: 0.5, dy: 0.5), y = infos[b].frame.insetBy(dx: 0.5, dy: 0.5)
                if x.intersects(y) { out.append("overlap: \(infos[a].id) x \(infos[b].id)") }
            }
        }
        let safe = CGRect(x: s.side, y: s.top, width: s.w - 2 * s.side, height: s.h - s.top - s.bottom).insetBy(dx: -0.5, dy: -0.5)
        for i in infos {
            let mustShow = !scrolls || i.id == "home" || i.id == "title" || i.id == "place"
            if mustShow && !safe.contains(i.frame) { out.append("off screen: \(i.id) \(i.frame.integral)") }
            if i.frame.maxX > safe.maxX || i.frame.minX < safe.minX { out.append("clipped sideways: \(i.id) \(i.frame.integral)") }
        }
        if !infos.contains(where: { $0.id == "home" }) && !infos.contains(where: { $0.id == "done" }) { out.append("no Back home / Done text found") }
        return out
    }

    private var stillDir: String? {
        let d = ProcessInfo.processInfo.environment["RESULT_CARD_DIR"]
        return (d?.isEmpty == false) ? d : nil
    }
    private var phase: String { ProcessInfo.processInfo.environment["RESULT_CARD_PHASE"] ?? "run" }

    func save(_ img: UIImage?, _ comp: String, _ name: String) {
        guard let dir = stillDir, let data = img?.pngData() else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(comp)_\(phase)_\(name).png"))
    }

    func writeFailures(_ comp: String, _ f: [String]) {
        guard let dir = stillDir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? f.joined(separator: "\n").write(toFile: "\(dir)/failures_\(comp)_\(phase).txt", atomically: true, encoding: .utf8)
    }

    /// Runs every case on every screen at both text sizes; `scrolls` is allowed at the big text size and on the short landscape screens.
    func sweep<V: View>(_ comp: String, cases: [(String, (CGFloat) -> V)]) {
        var failures: [String] = []
        for (cname, make) in cases {
            for s in Self.screens {
                for ax in [false, true] {
                    let (infos, img) = host(s, ax: ax) { h in AnyView(make(ResultCardMetrics.maxHeight(screenH: h)).resultCardSlot()) }
                    let tag = "\(cname)_\(s.name)_\(ax ? "ax5" : "default")"
                    save(img, comp, tag)
                    let p = problems(infos, s, scrolls: ax)
                    if infos.isEmpty { failures.append("\(tag): no probes (not rendered)") }
                    if !p.isEmpty { failures.append("\(tag): " + p.joined(separator: "; ")) }
                }
            }
        }
        writeFailures(comp, failures)
        print("RESULTCARD \(comp) failures: \(failures.count)")
        for f in failures { print("RESULTCARD FAIL \(f)") }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    // MARK: Jelly Volleyball

    private func volley(won: Bool, score: [Int], coins: Int, pts: Int, after: Int, ribbon: Bool, trophies: [Trophy], name: String = "Berry", unlocked: VolleyTier? = nil, half: Bool = false) -> VolleyFlow {
        let f = VolleyFlow()
        f.playerName = name
        var s = VolleySim(mode: .match(.sandcastle), mine: [VolleyStats(), VolleyStats()], seed: 1, firstServe: 0)
        s.score = score; s.winner = won ? 0 : 1; s.phase = .over
        f.sim = s
        f.earned = coins; f.pointsEarned = pts; f.pointsAfter = after
        f.awards = TrophyAwards(place: won ? 1 : nil, newRibbon: ribbon, trophies: trophies)
        f.unlockedNow = unlocked
        f.assistFactor = half ? 0.5 : 1
        return f
    }

    private var volleyCases: [(String, (CGFloat) -> VolleyResultsCard)] {
        let long = Trophy.volleyFirst(.tidal)
        return [
            ("win-ribbon-trophy-points", { h in VolleyResultsCard(volley: self.volley(won: true, score: [3, 0], coins: 250, pts: 3, after: 2, ribbon: true, trophies: [Trophy.volleyFirst(.sandcastle)]), maxHeight: h, home: {}) }),
            ("win-everything-longest", { h in VolleyResultsCard(volley: self.volley(won: true, score: [3, 2], coins: 12_500, pts: 3, after: 128, ribbon: true, trophies: [long, .volley25], name: "Marshmallow", unlocked: .shore, half: true), maxHeight: h, home: {}) }),
            ("win-nothing-new", { h in VolleyResultsCard(volley: self.volley(won: true, score: [3, 1], coins: 250, pts: 3, after: 17, ribbon: false, trophies: []), maxHeight: h, home: {}) }),
            ("loss", { h in VolleyResultsCard(volley: self.volley(won: false, score: [1, 3], coins: 60, pts: 1, after: 9, ribbon: false, trophies: []), maxHeight: h, home: {}) }),
        ]
    }

    func testVolleyResultCardLayout() {
        sweep("volley", cases: volleyCases)
    }

    // MARK: Jelly Race

    private func race(place: Int, coins: Int, pts: Int, after: Int, ribbon: Bool, trophies: [Trophy], name: String = "Berry", unlocked: CourseTier? = nil, auto: Bool = false) -> RaceFlow {
        let f = RaceFlow()
        var ui = RaceUI()
        let names = ["Rival One", "Rival Two", "Rival Three"]
        var others = names
        var placings: [RacePlacing] = []
        for p in 1...4 {
            if p == place { placings.append(RacePlacing(racer: 0, name: name, place: p, time: 41.7 + Float(p), isPlayer: true)) }
            else { placings.append(RacePlacing(racer: p, name: others.removeFirst(), place: p, time: p == 4 ? nil : 41.7 + Float(p), isPlayer: false)) }
        }
        ui.placings = placings; ui.playerPlace = place; ui.earned = coins; ui.pointsEarned = pts; ui.pointsAfter = after; ui.playerName = name
        f.ui = ui
        f.earned = coins; f.pointsEarned = pts; f.pointsAfter = after; f.playerName = name
        f.awards = TrophyAwards(place: place, newRibbon: ribbon, trophies: trophies)
        f.unlockedNow = unlocked
        f.assist = auto ? .auto : .off
        return f
    }

    private var raceCases: [(String, (CGFloat) -> RacePlacingsCard)] {
        return [
            ("win-ribbon-trophy-points", { h in RacePlacingsCard(race: self.race(place: 1, coins: 250, pts: 3, after: 5, ribbon: true, trophies: [Trophy.firstWin(.puddle)]), maxHeight: h, home: {}) }),
            ("win-everything-longest", { h in RacePlacingsCard(race: self.race(place: 1, coins: 12_500, pts: 3, after: 128, ribbon: true, trophies: [Trophy.firstWin(.tsunami), .champion], name: "Marshmallow", unlocked: .ripple, auto: true), maxHeight: h, home: {}) }),
            ("win-nothing-new", { h in RacePlacingsCard(race: self.race(place: 1, coins: 250, pts: 3, after: 17, ribbon: false, trophies: []), maxHeight: h, home: {}) }),
            ("second-place", { h in RacePlacingsCard(race: self.race(place: 2, coins: 120, pts: 2, after: 9, ribbon: true, trophies: []), maxHeight: h, home: {}) }),
            ("fourth-place", { h in RacePlacingsCard(race: self.race(place: 4, coins: 40, pts: 1, after: 3, ribbon: false, trophies: []), maxHeight: h, home: {}) }),
        ]
    }

    func testRaceResultCardLayout() {
        sweep("race", cases: raceCases)
    }

    // MARK: Jelly Show

    /// A Show played (auto) to its results, then dressed with the awards / place the case wants.
    private func showFlow(place: Int, awards: ShowProgress.Awards?, earned: Int, name: String = "Berry", rank: ShowRank = .puddle) -> ShowFlow {
        let f = ShowFlow()
        f.songClock = { _ in nil }; f.audioReady = { _ in true }
        f.auto = true
        var p = ShowPlayerInput(name: name)
        for t in WearTag.allCases { p.condition[t] = 0.5 }
        p.glow = 0.8; p.dirt = 0; p.dance = .sway
        p.tricks = [.sit: 0.9, .jacks: 0.9, .flip: 0.9]; p.care = 1
        f.begin(playerID: 1, name: name, character: 1, input: p, rank: rank, dayKey: 20261021, bodies: 3, seed: 3)
        for _ in 0..<(60 * 400) { f.tick(dt: 1 / 60); if f.sim?.round == .results && f.trickStage == .pick { break } }
        // the places the case wants: the player in `place`, the others in order around her
        if var s = f.sim {
            var next = 1
            for i in s.entrants.indices {
                if s.entrants[i].isPlayer { s.entrants[i].place = place } else { if next == place { next += 1 }; s.entrants[i].place = next; next += 1 }
            }
            f.sim = s
        }
        f.earned = earned; f.awards = awards
        return f
    }

    private var showCases: [(String, (CGFloat) -> ResultsScreen)] {
        let rosette = WearTag.allCases.first
        return [
            ("win-cup-stickers-rosette", { _ in ResultsScreen(show: self.showFlow(place: 1, awards: ShowProgress.Awards(cup: 1, rosette: rosette, stickers: [.firstShow, .perfectDance, .glowBurst, .hatTrick], unlocked: .pond), earned: 12_500, name: "Marshmallow")) }),
            ("win-cup-only", { _ in ResultsScreen(show: self.showFlow(place: 1, awards: ShowProgress.Awards(cup: 1), earned: 300)) }),
            ("win-nothing-new", { _ in ResultsScreen(show: self.showFlow(place: 1, awards: ProgressAwardsNone.none, earned: 300)) }),
            ("fourth-place", { _ in ResultsScreen(show: self.showFlow(place: 4, awards: ProgressAwardsNone.none, earned: 40)) }),
        ]
    }

    func testShowResultsLayout() {
        var failures: [String] = []
        for (cname, make) in showCases {
            for s in Self.screens {
                for ax in [false, true] {
                    let (infos, img) = host(s, ax: ax) { _ in make(0) }
                    let tag = "\(cname)_\(s.name)_\(ax ? "ax5" : "default")"
                    save(img, "show", tag)
                    // the Show screen is full screen: its own Back / Again buttons are the controls, not a "Back home" text
                    // (the Show screen sits under the stage creature: on a short phone the lower cards scroll by design)
                    var p = problems(infos.filter { $0.id != "none" }, s, scrolls: ax || s.h < 700 || (s.landscape && s.h < 500))
                    p.removeAll { $0.hasPrefix("no Back home") }
                    if infos.isEmpty { failures.append("\(tag): no probes (not rendered)") }
                    if !p.isEmpty { failures.append("\(tag): " + p.joined(separator: "; ")) }
                }
            }
        }
        writeFailures("show", failures)
        print("RESULTCARD show failures: \(failures.count)")
        for f in failures { print("RESULTCARD FAIL \(f)") }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}

enum ProgressAwardsNone { static let none: ShowProgress.Awards? = ShowProgress.Awards() }
