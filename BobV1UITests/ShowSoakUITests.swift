//
//  ShowSoakUITests.swift
//  show-soak-r1: a UI-driven soak of the REAL app's Jelly Show on its SHIPPED defaults (random turn order on, the "Pick a move" card active; no -ShowAuto, no -Mute).
//  The test taps the real screens (lobby rank card, Enter Jelly Show, Next: Trick, the trick rows, Skip, Home / Go home, Done / Show again); the app's dev-only probe
//  (BobV1/Dev/ShowSoakProbe.swift) writes what the screens cannot show (music player state, walk gates, leftovers) to SOAK_LOG, and the test asserts on both.
//
//  Env (TEST_RUNNER_ prefix on the xcodebuild line):
//    SOAK_OUT      folder for the log, the probe file and screenshots (default /tmp/show_soak)
//    SOAK_SCENARIO full | skip | home | bg | cuddle | menu      (see `scenario`)
//    SOAK_RANKS    comma list of ranks, one Show each, round and round (default puddle)
//    SOAK_SHOWS    how many Shows (default 5)
//    SOAK_SEEDS    comma list of -ShowSeedList seeds (default 1..SOAK_SHOWS)
//    SOAK_HINT     keep | set | unset (the stored show.hint.pickMove flag at launch; default unset)
//    SOAK_HINT_EVERY 1   clear the flag before every Show (so the card is up on every Show)
//    SOAK_CLASSIC  1     random turn order off (bisect aid)
//    SOAK_LAND     1     landscape
//    SOAK_ROSTER   default pip,moss,lavender (3); `bob` = one Jelmiko
//    SOAK_FAST     seconds of the dance before it is cut (default 3); 0 = the whole dance, played for him
//    SOAK_EXTRA    extra launch arguments, space separated (e.g. "-RoomSwipeOff 1")
//

import XCTest

final class ShowSoakUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var out: String { env["SOAK_OUT"] ?? "/tmp/show_soak" }
    private var scenario: String { env["SOAK_SCENARIO"] ?? "full" }
    private var land: Bool { env["SOAK_LAND"] == "1" }
    private var probePath: String { "\(out)/probe.jsonl" }
    private var logPath: String { "\(out)/soak.log" }
    private var shotN = 0
    private var rng: UInt64 = 0x1234_5678_9ABC
    private var rngBox = SplitMix(state: 0xBEEF)
    struct SplitMix: RandomNumberGenerator { var state: UInt64; mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }

    private func rand(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(max(n, 1))) }
    private func log(_ s: String) {
        NSLog("[soak] %@", s)
        let line = String(format: "%.1f ", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100000)) + s + "\n"
        if let h = FileHandle(forWritingAtPath: logPath) { _ = try? h.seekToEnd(); h.write(Data(line.utf8)); try? h.close() } else { try? line.write(toFile: logPath, atomically: false, encoding: .utf8) }
    }
    private func shot(_ n: String) {
        shotN += 1
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(String(format: "%03d", shotN))_\(n).png"))
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    // MARK: the probe's file

    private func probe() -> [[String: Any]] {
        guard let d = FileManager.default.contents(atPath: probePath), let s = String(data: d, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }
    private func lastFlow() -> [String: Any]? { probe().last { ($0["k"] as? String) == "flow" } }
    private func count(_ kind: String) -> Int { probe().filter { ($0["k"] as? String) == kind }.count }
    private var failsSeen = 0
    private func reportFails(_ label: String) {
        let fails = probe().filter { ($0["k"] as? String) == "FAIL" }
        if fails.count > failsSeen {
            for f in fails[failsSeen...] {
                let d = (try? JSONSerialization.data(withJSONObject: f, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "\(f)"
                log("PROBE FAIL (\(label)) \(d)")
                XCTFail("probe: \(f["kind"] ?? "?") \(f["detail"] ?? "") [\(label)]")
            }
            failsSeen = fails.count
            shot("probefail_\(label)")
        }
    }

    // MARK: launching

    private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = land ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        let roster = env["SOAK_ROSTER"] ?? "pip,moss,lavender"
        let n = Int(env["SOAK_SHOWS"] ?? "5") ?? 5
        let seeds = env["SOAK_SEEDS"] ?? (1...max(n, 1)).map(String.init).joined(separator: ",")
        var a = ["-SetRoster", roster, "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "5000", "-BlobNoWander", "1", "-ClockHour", "14",
                 "-ShowRank", "ocean", "-LobbyAuto", "show", "-ShowSeedList", seeds,
                 "-ShowSoakLog", probePath, "-ShowSoakHint", env["SOAK_HINT"] ?? "unset", "-ShowSoakFast", env["SOAK_FAST"] ?? "3", "-ShowSoakAutoDance", "1", "-AudioLog", "1"]
        if env["SOAK_HINT_EVERY"] == "1" { a += ["-ShowSoakHintEveryShow", "1"] }
        if env["SOAK_CLASSIC"] == "1" { a += ["-ShowSoakClassic", "1"] }
        if land { a += ["-ForceOrientation", "left"] }
        if let x = env["SOAK_EXTRA"] { a += x.split(separator: " ").map(String.init) }
        app.launchArguments += a
        app.launch()
        log("launched: \(a.joined(separator: " "))")
        return app
    }

    // MARK: one Show

    /// Opens the lobby from wherever the room / lobby is.
    private func openLobby(_ app: XCUIApplication) -> Bool {
        if el(app, "studio-show").waitForExistence(timeout: 3) { return true }
        if scenario == "cuddle" {          // a cuddle, let go, then straight to the lobby
            let c = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)); c.tap(); sleep(2)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        }
        if scenario == "menu" { let m = app.buttons["care-menu"]; if m.exists { m.tap(); sleep(1); m.tap() } }
        if el(app, "forfeit-card").exists { el(app, "forfeit-keep").tap() }
        let out = app.buttons["go-out"]
        if out.waitForExistence(timeout: 40) { out.tap() }
        let st = app.buttons["town-studio"]
        if st.waitForExistence(timeout: 10) { st.tap() }
        return el(app, "studio-show").waitForExistence(timeout: 20)
    }

    /// `isHittable` reads false for every button over the Metal stage on this simulator (dance-next is plainly on screen), so "usable" = exists, enabled, a real frame on the screen;
    /// the tap is a coordinate tap at its centre (so a card covered by an overlay would still FAIL to be accepted: the turn counter is the proof).
    private func press(_ e: XCUIElement) { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    /// A card as the screen showed it a moment ago (a snapshot: an element that disappears mid-read - the turn moved on - is skipped instead of aborting the run under load).
    private struct Row { let el: XCUIElement; let label: String; let enabled: Bool; let frame: CGRect }
    private func trickRows(_ app: XCUIApplication) -> [Row] {
        let q = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trick-' AND label CONTAINS ' points'"))
        // only the cards INSIDE the menu's own frame (the list scrolls: a row beyond it is not on the screen, a tap there lands on something else)
        let box = (try? el(app, "trick-cards").snapshot())?.frame ?? .zero
        return q.allElementsBoundByIndex.compactMap { e in
            guard let s = try? e.snapshot() else { return nil }
            if !box.isEmpty, s.frame.minY < box.minY - 2 || s.frame.maxY > box.maxY + 2 { return nil }
            return Row(el: e, label: s.label, enabled: s.isEnabled, frame: s.frame)
        }
    }
    /// A tap at a card's snapshot position (no element lookup at tap time).
    private func tapRow(_ app: XCUIApplication, _ r: Row) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: r.frame.midX, dy: r.frame.midY)).tap()
    }
    private func pillLabel(_ app: XCUIApplication) -> String {
        guard let s = try? el(app, "trick-turns").snapshot() else { return "" }
        return s.label
    }

    /// Runs one Show end to end; returns false when the app is gone / the Show never reached its results (reported).
    private func oneShow(_ app: XCUIApplication, index: Int, rank: String, again: Bool) -> Bool {
        let tag = "show\(index)-\(rank)"
        guard openLobby(app) else { XCTFail("[\(tag)] the lobby never opened"); shot("\(tag)_nolobby"); return false }
        let card = el(app, "rank-\(rank)")
        if card.exists, !card.frame.isEmpty { press(card); sleep(1); log("[\(tag)] rank card \(rank) tapped") }
        let go = el(app, "studio-show")
        for _ in 0..<30 where !go.isEnabled { sleep(1) }          // (a sleeper is woken first, a meal out finishes)
        XCTAssertTrue(go.isEnabled, "[\(tag)] Enter Jelly Show is enabled: \(el(app, "studio-why").label)")
        let begins = count("begin")
        go.tap()
        let t0 = Date()
        var returned = false, turnsDone = -1, lastProgress = Date(), results = false, picks = 0
        var fired = Set<String>()
        let bgPhases = ["walkout", "rival-go", "player-go", "results"]
        var cardsSeenAt = Date(), cardsCheckedAt = Date.distantPast, queuedTurns = Set<Int>(), yourGoSince: Date?
        let homeAt = ["walkout", "rival-go", "player-go", "player-trick", "player-back"][rand(5)]          // (no Home pill on the results card: Done is the way home there)
        while Date().timeIntervalSince(t0) < 480 {
            guard app.state == .runningForeground else { XCTFail("[\(tag)] the app is not in the foreground (crashed?): \(app.state.rawValue)"); shot("\(tag)_gone"); return false }
            reportFails(tag)
            if count("begin") <= begins { usleep(500_000); if Date().timeIntervalSince(t0) > 40 { XCTFail("[\(tag)] the Show never began"); shot("\(tag)_nobegin"); return false }; continue }
            if count("end") >= count("begin") { break }          // (home again: after a Forfeit)
            let f = lastFlow() ?? [:]
            let round = f["round"] as? String ?? "-", stage = f["trickStage"] as? String ?? "-", step = f["rivalStep"] as? String ?? "-"
            let live = f["pickLive"] as? Bool ?? false, entering = f["entering"] as? Bool ?? false, pre = f["rivalPre"] as? Bool ?? false
            let turns = f["turns"] as? Int ?? 0
            let phase: String = {
                switch round {
                case "look", "dance": return round
                case "trick": return entering ? "walkout" : stage == "rivals" ? (step == "playerBack" ? "player-back" : "rival-go") : stage == "performing" ? "player-trick" : (live ? "player-go" : "pre-wait")
                case "results": return stage == "rivals" ? "rival-go" : "results"
                default: return "-"
                }
            }()
            if turns != turnsDone || round != "trick" { if turns != turnsDone { turnsDone = turns }; lastProgress = Date() }
            // scenario injections ---------------------------------------------------------------
            let key = "\(phase)#\(turns)#\(pre ? "pre" : "post")"
            if scenario == "bg", bgPhases.contains(phase), fired.insert(phase).inserted {
                log("[\(tag)] background at \(phase) (turns=\(turns) pre=\(pre))")
                XCUIDevice.shared.press(.home); sleep(UInt32(2 + rand(3)))
                // `app.activate()` leaves this headless simulator's app in .runningBackground (state 3) for good, so the return is asked of the outside driver:
                // a file at SOAK_OUT/fg.request is answered by `simctl launch <udid> io.mgsllc.BobV1` (an already running app is just brought to the front), and the answer is fg.done
                try? FileManager.default.removeItem(atPath: "\(out)/fg.done")
                FileManager.default.createFile(atPath: "\(out)/fg.request", contents: nil)
                let tb = Date(); while !FileManager.default.fileExists(atPath: "\(out)/fg.done"), Date().timeIntervalSince(tb) < 30 { usleep(300_000) }
                if app.state != .runningForeground { app.activate() }
                let tc = Date(); while app.state != .runningForeground, Date().timeIntervalSince(tc) < 20 { usleep(300_000) }
                log("[\(tag)] foreground again: state=\(app.state.rawValue)"); sleep(2)
                continue
            }
            if scenario == "home", phase == homeAt, fired.insert("home").inserted {
                log("[\(tag)] Home (forfeit) at \(phase) (turns=\(turns))")
                let pill = el(app, "forfeit-home")
                if pill.waitForExistence(timeout: 5) { pill.tap(); if el(app, "forfeit-go").waitForExistence(timeout: 5) { if rand(2) == 0 { el(app, "forfeit-keep").tap(); sleep(1); pill.tap() }; el(app, "forfeit-go").tap() } } else { XCTFail("[\(tag)] no Home pill at \(phase)"); shot("\(tag)_nohome") }
                for _ in 0..<30 where count("end") < count("begin") { sleep(1) }
                sleep(10)          // (the probe judges the room 6 s after the return: the next Show must not start before it has)
                reportFails(tag)
                return true
            }
            if scenario == "skip", phase == "rival-go" || phase == "player-back" || phase == "walkout" || phase == "pre-wait" {
                let sk = el(app, "rivals-skip")
                if sk.exists, !sk.frame.isEmpty, fired.insert("skip-\(key)").inserted, rand(3) != 0 { log("[\(tag)] Skip at \(phase) turns=\(turns) pre=\(pre)"); press(sk); sleep(1); continue }
            }
            // the screens ------------------------------------------------------------------------
            let next = el(app, "dance-next")
            if Int(Date().timeIntervalSince(t0)) % 10 == 0, fired.insert("hb\(Int(Date().timeIntervalSince(t0)))").inserted { log("[\(tag)] poll phase=\(phase) round=\(round) turns=\(turns) next.exists=\(next.exists) hittable=\(next.exists && next.isHittable)") }
            if round == "dance", next.exists, next.isEnabled, !next.frame.isEmpty { press(next); log("[\(tag)] Next: Trick"); continue }
            if round == "trick", f["tutorialUp"] as? Bool == true, rand(6) == 0, fired.insert("tut\(turns)").inserted { let t = el(app, "trick-tutorial"); if t.exists { t.tap() } }
            // show-perfect-r1: the cards are up and enabled from the first second of the Trick round (every 3 s the screen is asked); not his go yet = a tap QUEUES the move ("Up next"), once per turn at random
            if round != "trick" { cardsSeenAt = Date(); yourGoSince = nil }
            // "Your go" on the pill without a live pick for over 1.5 s is a FAIL (the screen's own label, asked on every poll while the probe says it is not his go)
            if round == "trick", !live, !entering, f["tricksDone"] as? Bool != true, f["wipe"] as? Double == 0 {
                if pillLabel(app).contains("Your go") { if yourGoSince == nil { yourGoSince = Date() } else if Date().timeIntervalSince(yourGoSince!) > 1.5 { XCTFail("[\(tag)] the pill says Your go but the pick is not live (\(phase), turns \(turns))"); shot("\(tag)_yourgo_notlive"); yourGoSince = nil } } else { yourGoSince = nil }
            } else { yourGoSince = nil }
            if round == "trick", f["tricksDone"] as? Bool != true, f["wipe"] as? Double == 0, Date().timeIntervalSince(cardsCheckedAt) > 3 {
                cardsCheckedAt = Date()
                let ok = trickRows(app).filter { $0.enabled && !$0.frame.isEmpty }
                if !ok.isEmpty { cardsSeenAt = Date() }
                else if Date().timeIntervalSince(cardsSeenAt) > 20 { XCTFail("[\(tag)] no enabled trick card for over 20 s (phase \(phase), turns \(turns))"); shot("\(tag)_nocards20"); cardsSeenAt = Date() }
                if !live, scenario != "skip", !queuedTurns.contains(turns), phase == "rival-go" || phase == "walkout" || phase == "pre-wait" || phase == "player-back", rand(2) == 0, let r = ok.randomElement(using: &rngBox) {
                    queuedTurns.insert(turns)
                    log("[\(tag)] turn \(turns + 1): QUEUE \(r.label.prefix(40)) at \(phase)")
                    tapRow(app, r)
                    var queued = false
                    for _ in 0..<8 { usleep(400_000); let q = lastFlow()?["queued"] as? String ?? "-"; if q != "-" || (lastFlow()?["pickLive"] as? Bool ?? false) || (lastFlow()?["turns"] as? Int ?? 0) > turns { queued = true; break } }
                    if !queued { XCTFail("[\(tag)] a tap on a dim trick card was NOT queued (turn \(turns + 1), \(phase))"); shot("\(tag)_notqueued") }
                    continue
                }
            }
            if round == "trick", stage == "pick", live, !entering, (f["queued"] as? String ?? "-") != "-" { usleep(300_000); continue }          // (the queued move runs by itself)
            if round == "trick", stage == "pick", live, !entering {
                let rows = trickRows(app)
                let ok = rows.filter { $0.enabled && !$0.frame.isEmpty }
                if let r = ok.first(where: { !$0.label.contains("shown already") }) ?? ok.first {
                    log("[\(tag)] turn \(turns + 1): pick \(r.label.prefix(40))")
                    tapRow(app, r); picks += 1
                    var accepted = false
                    for _ in 0..<12 { usleep(500_000); if (lastFlow()?["turns"] as? Int ?? 0) > turns { accepted = true; break } }
                    if !accepted { XCTFail("[\(tag)] a tap on an enabled, hittable trick was NOT accepted (turn \(turns + 1))"); shot("\(tag)_tapnotaccepted") }
                } else if Date().timeIntervalSince(lastProgress) > 8 {
                    XCTFail("[\(tag)] turn \(turns + 1): the probe says his go is live but no trick card is enabled+hittable (\(rows.count) rows: \(rows.map { $0.enabled ? "on" : "off" }))")
                    shot("\(tag)_nocards"); try? app.debugDescription.write(toFile: "\(out)/\(tag)_tree.txt", atomically: false, encoding: .utf8); lastProgress = Date()
                }
                continue
            }
            if round == "results", stage == "pick" {
                results = true
                let btn = el(app, again ? "results-again" : "results-done")
                if btn.exists, !btn.frame.isEmpty { sleep(2); shot("\(tag)_results"); log("[\(tag)] results; \(again ? "Show again" : "Done")"); press(btn)
                // back in the lobby (Show again) or the room (Done): the probe only learns of it at its next stage tick, so the screens are the signal
                let t1 = Date(); while Date().timeIntervalSince(t1) < 40, !(again ? el(app, "studio-show").exists : app.buttons["go-out"].exists) { usleep(500_000) }
                if !(again ? el(app, "studio-show").exists : app.buttons["go-out"].exists) { XCTFail("[\(tag)] after results the \(again ? "lobby" : "room") never came back"); shot("\(tag)_noreturn"); return false }
                returned = true; break
                }
            }
            if Date().timeIntervalSince(lastProgress) > 120 { XCTFail("[\(tag)] no progress for 120 s at phase \(phase) turns=\(turns) stage=\(stage) step=\(step)"); shot("\(tag)_stall"); try? app.debugDescription.write(toFile: "\(out)/\(tag)_tree.txt", atomically: false, encoding: .utf8); return false }
            usleep(400_000)
        }
        reportFails(tag)
        if !returned, count("end") < count("begin") { XCTFail("[\(tag)] the Show did not finish in 8 minutes"); shot("\(tag)_timeout"); return false }
        XCTAssertTrue(results, "[\(tag)] reached the results (picks=\(picks))")
        // the room is back: music restored (the probe judges it 4-40 s after the return)
        sleep(10)
        reportFails("\(tag)-home")
        log("[\(tag)] done: picks=\(picks) results=\(results)")
        return true
    }

    private func waitUp(_ app: XCUIApplication) {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 180 { if app.buttons["go-out"].exists || el(app, "studio-show").exists { sleep(5); return }; usleep(700_000) }
        XCTFail("the app never came up")
    }

    private func soakRun() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: probePath)
        var app = launch()
        waitUp(app)
        sleep(5)
        let ranks = (env["SOAK_RANKS"] ?? "puddle").split(separator: ",").map(String.init)
        let n = Int(env["SOAK_SHOWS"] ?? "5") ?? 5
        for i in 0..<n {
            let again = scenario == "full" ? (i % 2 == 0) : false
            if !oneShow(app, index: i + 1, rank: ranks[i % ranks.count], again: again) {
                app.terminate(); app = launch(); waitUp(app)
            }
        }
        log("finished \(n) shows; FAIL lines: \(failsSeen)")
        app.terminate()
    }

    @MainActor func testSoak() { soakRun() }
}
