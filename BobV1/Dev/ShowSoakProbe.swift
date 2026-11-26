//
//  ShowSoakProbe.swift
//  show-soak-r1. DEV BUILDS ONLY (compiled out of the App Store archive). READ-ONLY: it never changes the game (only `configure` sets the soak's dev switches, from dev arguments).
//  The Jelly Show soak (BobV1UITests/ShowSoakUITests.swift) drives the real app through its screens; this probe, ticked once per fixed step beside the StuckDetector, writes what the
//  screens cannot show: JSON lines (one object per line) to the file named by `-ShowSoakLog <path>`:
//      {"k":"hb", ...}      a heartbeat (fixed steps counted, game seconds, host seconds), once per game second while a show is on, every 5 s at home
//      {"k":"flow", ...}    the flow's state whenever it changes (phase, round, trickStage, rivalStep, rivalPre, prePending, pickLive, turns, ...)
//      {"k":"begin" / "end" ...}  a show started (seed, rank, hint flag) / returned home
//      {"k":"FAIL","kind":..., ...}  an invariant broke (once per show per kind). Kinds: trick-stall, rivals-stall, pick-dead, entering-stall, off-centre, music-silent, music-zero-gain,
//                                    room-music-lost, scene-stuck, leftover, no-results
//  Switches (dev arguments): -ShowSoakHint set|unset|keep (the stored `show.hint.pickMove` flag, applied once at launch), -ShowSoakHintEveryShow 1 (cleared at every Show start),
//  -ShowSoakClassic 1 (random turn order off), -ShowSoakAutoDance 1 (the dance is played for him), -ShowSoakFast <s> (the dance is cut short that many song seconds in).
//

#if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
import Foundation
import QuartzCore
import simd

@MainActor
final class ShowSoakProbe {
    static let shared = ShowSoakProbe()
    nonisolated(unsafe) static let path: String? = DevArgs.enabled ? UserDefaults.standard.string(forKey: "ShowSoakLog") : nil
    private var handle: FileHandle?
    private var ticks = 0
    private var gameT: Double = 0
    private var lastHB: Double = -10
    private var lastSig = ""
    private weak var showRef: ShowFlow?
    private var hintEvery = false

    // per show
    private var showN = 0
    private var wasActive = false
    private var lastStarted = 0
    private var fired = Set<String>()
    private var age: [String: Double] = [:]
    private var lastTurns = -1
    private var turnsSince: Double = 0
    private var sawResults = false
    private var showStartT: Double = 0
    private var returnedAt: Double?
    private var returnedChecked = false
    private var roomMusicAge: Double = 0
    private var baseline: [String: String]?

    func configure(show: ShowFlow) {
        guard Self.path != nil else { return }
        showRef = show
        let d = UserDefaults.standard
        switch d.string(forKey: "ShowSoakHint") {
        case "set": d.set(true, forKey: ShowFlow.trickTutorialKey)
        case "unset": d.removeObject(forKey: ShowFlow.trickTutorialKey)
        default: break
        }
        hintEvery = d.bool(forKey: "ShowSoakHintEveryShow")
        if d.bool(forKey: "ShowSoakClassic") { show.randomTurnOrder = false }
        if d.bool(forKey: "ShowSoakAutoDance") { show.soakAutoDance = true }
        if d.object(forKey: "ShowSoakFast") != nil { show.soakFastDance = d.double(forKey: "ShowSoakFast") }
        emit(["k": "config", "hint": d.string(forKey: "ShowSoakHint") ?? "keep", "hintStored": d.bool(forKey: ShowFlow.trickTutorialKey), "classic": !show.randomTurnOrder,
              "autoDance": show.soakAutoDance, "fast": show.soakFastDance ?? -1, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"])
    }

    private func emit(_ o: [String: Any]) {
        guard let path = Self.path else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            handle = FileHandle(forWritingAtPath: path); _ = try? handle?.seekToEnd()
        }
        var o = o
        o["host"] = (CACurrentMediaTime() * 100).rounded() / 100
        o["gt"] = (gameT * 100).rounded() / 100
        o["tk"] = ticks
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return }
        handle?.write(data); handle?.write(Data("\n".utf8))
    }

    private func fail(_ kind: String, _ detail: String, _ state: [String: Any]) {
        guard fired.insert(kind).inserted else { return }
        var o = state; o["k"] = "FAIL"; o["kind"] = kind; o["detail"] = detail; o["show"] = showN
        emit(o)
    }
    /// Accumulates `dt` while `cond` holds; true once it has held for `limit` game seconds.
    private func held(_ key: String, _ cond: Bool, _ dt: Double, over limit: Double) -> Bool {
        if cond { age[key, default: 0] += dt } else { age[key] = 0 }
        return (age[key] ?? 0) > limit
    }

    func tick(care: GameCare, dt: Float) {
        guard Self.path != nil else { return }
        let show = care.show
        let dtd = Double(dt)
        ticks += 1; gameT += dtd
        let active = show.active
        // show start / end edges
        if wasActive, show.started != lastStarted {          // (a new show began before a tick saw the last one end: the lobby / room do not tick the stage)
            emit(["k": "end", "n": showN, "results": sawResults, "forfeited": show.forfeited, "late": true])
            if !sawResults, !show.forfeited { fail("no-results", "returned home without the results", state(care)) }
            wasActive = false
        }
        if active, !wasActive {
            lastStarted = show.started
            showN += 1; fired = []; age = [:]; lastTurns = -1; turnsSince = 0; sawResults = false; showStartT = gameT; returnedAt = nil; returnedChecked = false
            if hintEvery { UserDefaults.standard.removeObject(forKey: ShowFlow.trickTutorialKey) }
            emit(["k": "begin", "n": showN, "seed": show.sim.map { String($0.seed) } ?? "?", "rank": show.rank.rawValue, "hintStored": UserDefaults.standard.bool(forKey: ShowFlow.trickTutorialKey),
                  "random": show.randomTurnOrder, "preCounts": (0..<3).map { show.preCount(turn: $0) }, "audio": audioLine()])
        }
        if !active, wasActive {
            returnedAt = gameT; returnedChecked = false; roomMusicAge = 0
            emit(["k": "end", "n": showN, "results": sawResults, "forfeited": show.forfeited, "audio": audioLine()])
            if !sawResults, !show.forfeited { fail("no-results", "returned home without the results", state(care)) }
        }
        wasActive = active
        // baseline at home before the first show
        if !active, baseline == nil, showN == 0, ticks > 120, !care.tripActive { baseline = homeDump(care); emit(["k": "baseline", "n": baseline!.count]) }
        // heartbeat
        if gameT - lastHB >= (active ? 1 : 5) { lastHB = gameT; var o = state(care); o["k"] = "hb"; emit(o) }
        // flow change
        let st = state(care)
        let sig = flowSig(st)
        if sig != lastSig { lastSig = sig; var o = st; o["k"] = "flow"; emit(o) }
        if active { checkShow(care, show, dtd, st) } else { checkHome(care, show, dtd, st) }
    }

    // MARK: state

    private func audioLine() -> [String: Any] {
        let a = AudioHub.shared.soakAudio()
        return ["muted": a.muted, "started": a.started, "active": a.active, "musicOn": a.musicOn, "musicVol": Double(a.musicVolume), "dScene": a.directorScene, "dTrack": a.directorTrack,
                "engCur": a.engineCurrent, "trackPlaying": a.trackPlaying, "engineRunning": a.engineRunning, "loudest": Double(a.loudest), "level": Double(a.levelNow), "duck": Double(a.duck),
                "danceGain": Double(a.danceGain), "storm": Double(a.stormDuck), "resume": Double(a.resumeFade), "main": a.mainGain, "deckPlaying": a.deckPlaying, "gap": a.inGap,
                "roomTrack": a.roomTrack, "mic": a.micSession, "otherAudio": a.otherAudio]
    }

    private func state(_ care: GameCare) -> [String: Any] {
        let show = care.show
        var o: [String: Any] = ["active": show.active, "phase": String(describing: show.phase), "wipe": Double(show.wipe), "blend": Double(show.cameraBlend)]
        o["forfeitAsk"] = care.forfeitAsk
        if let s = show.sim {
            o["round"] = String(describing: s.round); o["turns"] = s.turns.count; o["tricksDone"] = s.tricksDone
            o["beat"] = String(describing: show.beat)
        }
        o["trickStage"] = String(describing: show.trickStage); o["rivalStep"] = String(describing: show.rivalStep); o["rivalRound"] = show.rivalRound
        o["rivalTurn"] = show.rivalTurn ?? -1; o["pickLive"] = show.pickLive; o["entering"] = show.trickEntering
        o["musicScene"] = String(describing: show.musicScene)
        o += newFields(show)
        if show.active {
            if let f = care.soakPlayerFloor() { o["dist"] = Double(simd_distance(f, ShowStage.playerSpot)) }
            o["pGates"] = care.soakWalkGates(nil)
            o["lineFormed"] = care.showLineFormed()
            o["floors"] = care.soakFloors()
            o["allGates"] = care.soakRivalGates()
            if let i = show.rivalTurn { o["rGates"] = care.soakWalkGates(i) }
        }
        return o
    }
    /// Fields that exist only on the newer builds (show-trick-tut-r1): the one place to stub when this file is carried onto an older commit.
    private func newFields(_ show: ShowFlow) -> [String: Any] {
        ["rivalPre": show.rivalPre, "prePending": show.prePending, "tutorialUp": show.trickTutorialUp, "preTurnDone": show.soakPreTurnDone, "tutDismissed": show.tutorialDismissed,
         "hintStored": UserDefaults.standard.bool(forKey: ShowFlow.trickTutorialKey)]
    }
    private func flowSig(_ o: [String: Any]) -> String {
        ["active", "phase", "round", "turns", "beat", "trickStage", "rivalStep", "rivalRound", "rivalTurn", "pickLive", "entering", "musicScene", "rivalPre", "prePending", "tutorialUp", "forfeitAsk", "tricksDone"]
            .map { "\(o[$0] ?? "-")" }.joined(separator: "|")
    }

    // MARK: invariants while a show is on

    private func checkShow(_ care: GameCare, _ show: ShowFlow, _ dt: Double, _ st: [String: Any]) {
        guard let s = show.sim else { return }
        if s.round == .results { sawResults = true }
        let stage = show.phase == .stage && show.wipe == 0
        let trick = stage && s.round == .trick
        // trick round: the player's turns
        if s.turns.count != lastTurns { lastTurns = s.turns.count; turnsSince = 0 } else if trick { turnsSince += dt }
        if trick, turnsSince > 45, !s.tricksDone { fail("trick-stall", "no player turn for \(Int(turnsSince)) game s", st) }
        if held("rivals", trick && show.trickStage == .rivals, dt, over: 45) { fail("rivals-stall", "trickStage .rivals for over 45 game s", st) }
        if held("pickdead", trick && show.trickStage == .pick && !s.tricksDone && !show.pickLive && !show.trickEntering, dt, over: 6) { fail("pick-dead", "his go is not live for over 6 game s", st) }
        if held("entering", trick && show.trickEntering, dt, over: 9) { fail("entering-stall", "the walk-on has not ended", st) }
        if held("offcentre", trick && show.pickLive && !show.trickEntering && ((st["dist"] as? Double) ?? 0) > 0.6, dt, over: 4) { fail("off-centre", "his go is live and the performer is not at the centre", st) }
        // music
        if stage, show.musicScene != .none {
            let a = AudioHub.shared.soakAudio()
            let wanted = !a.muted && a.started && a.active && a.musicOn && a.musicVolume > 0.01 && !a.otherAudio && !a.micSession
            if held("music", wanted && !a.trackPlaying, dt, over: 8) { var o = st; o["audio"] = audioLine(); fail("music-silent", "show music \(show.musicScene) wanted and not playing", o) }
            if held("musicgain", wanted && a.trackPlaying && a.loudest < 0.004, dt, over: 8) { var o = st; o["audio"] = audioLine(); fail("music-zero-gain", "show music plays at zero gain", o) }
        } else { age["music"] = 0; age["musicgain"] = 0 }
    }

    // MARK: at home

    private func checkHome(_ care: GameCare, _ show: ShowFlow, _ dt: Double, _ st: [String: Any]) {
        guard let r = returnedAt, !returnedChecked else { return }
        let since = gameT - r
        let a = AudioHub.shared.soakAudio()
        if since > 4, since < 40 {
            // the stage's scene must be gone; the room's music (or a gap between songs, or the Studio lobby's own scene) is back
            let stageScene = a.directorScene == "show" || a.directorScene.hasPrefix("danceSong") || a.directorScene == "results"
            if stageScene { var o = st; o["audio"] = audioLine(); fail("scene-stuck", "the stage's music scene is still on \(Int(since)) s after the return", o) }
            let wanted = !a.muted && a.started && a.active && a.musicOn && a.musicVolume > 0.01 && !a.otherAudio && !a.micSession && !a.inGap && a.directorScene == "none"
            if held("roommusic", wanted && !a.deckPlaying, dt, over: 8) { var o = st; o["audio"] = audioLine(); fail("room-music-lost", "room music is not playing after the return", o) }
        }
        if since > 6, !returnedChecked {
            returnedChecked = true
            let now = homeDump(care)
            var diffs: [String: String] = [:]
            if let b = baseline { for (k, v) in now where b[k] != v { diffs[k] = "\(b[k] ?? "∅") -> \(v)" } }
            emit(["k": "leftover", "n": showN, "diffs": diffs])
            let hard = diffs.filter { k, _ in !k.hasPrefix("book.gameClock") && !k.hasPrefix("book.placements") && !k.hasPrefix("book.retryAt") && !k.hasPrefix("book.homes") && !k.hasPrefix("book.autonomy") && !k.hasPrefix("book.arena") && !k.hasPrefix("actor") && !k.hasPrefix("book.spot") && !k.hasPrefix("book.actors") }
            if !hard.isEmpty { fail("leftover", hard.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; "), st) }
            let bodies = diffs.filter { $0.key.hasPrefix("actor") }
            if !bodies.isEmpty { fail("leftover", "room bodies differ: " + bodies.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; "), st) }
        }
    }

    private func homeDump(_ care: GameCare) -> [String: String] {
        let show = care.show
        var d: [String: String] = [:]
        for (k, v) in care.soakShowBookDump() { d["book." + k] = v }
        for (k, v) in care.soakRoomBodies() { d[k] = v }
        d["flow.phase"] = "\(show.phase)"; d["flow.sim"] = show.sim == nil ? "nil" : "some"; d["flow.beat"] = "\(show.beat)"; d["flow.trickStage"] = "\(show.trickStage)"
        d["flow.rivalTurn"] = "\(show.rivalTurn ?? -1)"; d["flow.rivalPre"] = "\(show.rivalPre)"; d["flow.leaving"] = "\(show.leaving)"; d["flow.performed"] = "\(show.rivalPerformed.count)"
        d["flow.wipe"] = "\(show.wipe)"; d["flow.blend"] = "\(show.cameraBlend)"; d["care.forfeitAsk"] = "\(care.forfeitAsk)"; d["care.tripActive"] = "\(care.tripActive)"
        d["care.wardrobeHeld"] = "\(care.soakWardrobeHeld)"
        return d
    }
}

private func += (l: inout [String: Any], r: [String: Any]) { for (k, v) in r { l[k] = v } }
#endif
