//
//  GameCare+Show.swift
//  The Jelly Show: the glue between the show (Show/ShowFlow.swift, ShowSim.swift) and the Jelbies of the room.
//
//  "Start show" sends the picked Jelbie to the stage. The other Jelbies' bodies are BORROWED as rival bodies (a colour tint on the same body, like the
//  race), standing either side of him; a rival with no body to borrow is a silhouette card on the screen. Bodies swap worlds only under the white fade.
//  On stage nobody roams: autonomy is off and room life is paused; tricks run as commanded idles (the voice tricks' moves), the dance as a looping
//  commanded idle, the celebration as the jump for joy. The stage keeps the room's floor, so the feet stand where they always do.
//

import Foundation
import QuartzCore
import simd

/// What GameCare keeps while a show trip is on: the room's Jelbies as the stage last gave them, who stands where, and the way home.
@MainActor
final class ShowBook {
    var actors: [JellyActor] = []
    /// Actor ids on the stage: the player's first, then the rival bodies (rival index k -> performers[k + 1]).
    var performers: [Int] = []
    /// Actor ids that wait off stage.
    var parked: [Int] = []
    var homes: [Int: SIMD2<Float>] = [:]
    var autonomy: [Int: Bool] = [:]
    var arena: [Int: Float] = [:]
    /// Rival body colours while they perform, by actor id.
    var palettes: [Int: Palette] = [:]
    /// The dance each stage body loops (nil = stand).
    var dancing: [Int: IdleKind] = [:]
    var danceRestart: [Int: Float] = [:]
    /// Seconds since the player's trick was asked for (the flop's wobble lands a beat later).
    var flopT: Float?
    /// Bodies that have turned to the crowd.
    var turned: Set<Int> = []
    nonisolated deinit {}
}

extension GameCare {
    func wireShow() {
        show.wallet = bath.wallet
        show.onSwap = { [weak self] dest in self?.showSwap(dest) }
        show.onReturned = { [weak self] id, won, again in self?.showWelcomeHome(id, won: won, again: again) }
        show.onPerform = { [weak self] t, ok in self?.showPerform(t, success: ok) }
        show.onDance = { [weak self] d, on in self?.showDance(d, on: on) }
        show.onHit = { [weak self] g in self?.showHit(g) }
        show.onResults = { [weak self] place in self?.showCelebrate(place: place) }
        show.onBurst = { [weak self] in self?.showBurst() }
        let d = UserDefaults.standard
        if d.object(forKey: "ShowAuto") != nil { show.auto = true }
        // capture aid: -ShowRank puddle|pond|lagoon|ocean opens every rank up to it and picks it
        if let r = d.string(forKey: "ShowRank"), let t = ShowRank(rawValue: r.lowercased()) {
            for b in ShowRank.allCases where b.index < t.index { show.progress.record(rank: b, place: 1, theme: .bunnyPicnic, character: 0, burst: false, perfectDance: false, hatTrick: false) }
            show.progress.chosen = t
        }
    }

    /// Why a show cannot start for this Jelbie right now, in words for the lobby (nil = it can).
    func showBlocker(jelly id: Int) -> String? {
        guard jelly(id) != nil else { return "No such Jelbie." }
        if show.active { return "A show is already on." }
        if race.active || raceWait != nil { return "He is at the track." }
        if volley.active || volleyWork.wait != nil { return "He is at the beach." }
        if trayOut || meal != nil || wanted != nil { return "A meal is out. Let him finish first." }
        if bath.active { return "The clean-up is going on." }
        if focus.isActive || focus.phase != .roaming { return "He is in the close-up. Let him go first." }
        if raceBook.returner != nil { return "Welcome him home first." }
        if voice.mode.phase != .idle || voice.voiceGoing || voice.comingNow { return "He is listening to you." }
        if !raceBook.actors.isEmpty, !(raceBook.actors.indices.contains(id) && raceBook.actors[id].brain != nil) { return "He is not in the room." }
        return nil
    }
    func canShow(jelly id: Int) -> Bool { showBlocker(jelly: id) == nil }

    /// What the player's Jelbie brings to the stage: his condition in every stat, his shine and lint, the dance he knows best, his learned tricks.
    func showPlayerInput(jelly id: Int) -> ShowPlayerInput {
        guard let p = jelly(id) else { return ShowPlayerInput() }
        var input = ShowPlayerInput(name: p.name)
        for t in WearTag.allCases { input.condition[t] = p.stats.condition(t.condition) }
        input.glow = p.grime.sparkle; input.dirt = p.grime.dirt
        input.dance = p.stats.bestDance; input.danceSkill = input.dance.map { p.stats.proficiency($0) } ?? 0
        for t in ShowTrickInfo.stageTricks where p.training.isLearned(t) && store.hasPage(t) { input.tricks[t] = p.training.reliability(t) }
        return input
    }
    /// The tags of what he wears, by slot (the Look round scores the rank's slots).
    func showOutfitTags(jelly id: Int) -> [WearSlot: [WearTag]] {
        var o: [WearSlot: [WearTag]] = [:]
        for (s, l) in store.outfit(id) { o[s] = l.tags }
        return o
    }
    /// The Ready check of the lobby: an estimate of each round out of 100 for this Jelbie at `rank` (the dance and ring taps assumed decent).
    func showEstimate(jelly id: Int, rank: ShowRank, theme: ShowTheme) -> ShowScores {
        let p = showPlayerInput(jelly: id)
        let items = rank.slotOrder.compactMap { showOutfitTags(jelly: id)[$0] }
        var s = ShowScores()
        s.look = ShowScoring.look(outfit: ShowScoring.outfitMatch(items: items, slots: rank.slots, theme: theme), main: p.stat(theme.main), friend: p.stat(theme.friend), glow: p.glow, dirt: p.dirt)
        s.dance = ShowScoring.dance(accuracy: 0.7, skill: p.danceSkill)
        let known = ShowTrickInfo.stageTricks.filter { p.tricks[$0] != nil }
        var trick: Float = 0
        for k in 0..<ShowScoring.turns {
            guard !known.isEmpty else { break }
            let t = known[k % known.count], r = p.tricks[t] ?? 0
            trick += r * 18 + (1 - r) * 8 + Float(theme.trickBonus(ShowTrickInfo.tags(t))) * 0.7 + 3.6
        }
        s.trick = min(100, trick)
        return s
    }

    /// The show seed: `-ShowSeed n`, else from the clock (the rivals come from the day, the player's rolls from this).
    static var showSeed: UInt64 {
        let d = UserDefaults.standard
        if d.object(forKey: "ShowSeed") != nil { return UInt64(max(d.integer(forKey: "ShowSeed"), 0)) }
        return UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFFFF
    }
    /// The show's calendar day (`-ShowDay yyyymmdd` for captures).
    static var showDay: Int {
        let d = UserDefaults.standard
        if d.object(forKey: "ShowDay") != nil { return d.integer(forKey: "ShowDay") }
        return DayClock.shared.dayKey
    }

    /// Takes Jelbie `id` to the stage for a show at `rank` (the chosen rank by default).
    func startShow(jelly id: Int, rank: ShowRank? = nil, seed: UInt64? = nil) {
        guard canShow(jelly: id), let prof = jelly(id) else { return }
        let r = rank.flatMap { show.progress.unlocked($0) ? $0 : nil } ?? show.progress.chosen
        for a in raceBook.actors { if let b = a.brain, b.isSleeping { b.commandedGoodnight = false; b.sleepWake(groggy: false, fast: true) } }
        select.cancel()
        queued.removeAll(); callRunning = false
        voice.cancel()
        if outingGate([id], again: { [weak self] in self?.startShow(jelly: id, rank: rank, seed: seed) }) { return }          // he runs out of the room first
        let bodies = max(1, min(raceBook.actors.count, 4))
        show.begin(playerID: id, name: prof.name, character: prof.character, input: showPlayerInput(jelly: id), rank: r, dayKey: Self.showDay, bodies: bodies, seed: seed ?? Self.showSeed)
        show.setOutfit(showOutfitTags(jelly: id))
    }
    /// "Practise dance" (the Studio): Jelbie `id` dances `dance` alone on the stage.
    func startDancePractice(jelly id: Int, dance: DanceID, seed: UInt64? = nil) {
        guard canShow(jelly: id), let prof = jelly(id), prof.stats.danceOpen(dance) else { return }
        for a in raceBook.actors { if let b = a.brain, b.isSleeping { b.commandedGoodnight = false; b.sleepWake(groggy: false, fast: true) } }
        select.cancel()
        queued.removeAll(); callRunning = false
        voice.cancel()
        if outingGate([id], again: { [weak self] in self?.startDancePractice(jelly: id, dance: dance, seed: seed) }) { return }
        show.beginPractice(playerID: id, name: prof.name, character: prof.character, dance: dance, stats: prof.stats, seed: seed ?? Self.showSeed)
    }
    /// The lobby's rank picker.
    @discardableResult
    func chooseShowRank(_ r: ShowRank) -> Bool {
        guard show.progress.unlocked(r) else { return false }
        show.progress.chosen = r
        return true
    }

    /// The body colour a Jelbie wears on the stage (nil = his own).
    func showPalette(for id: Int) -> Palette? { showBook.palettes[id] }
    /// The rival index of a stage body (nil = the player or nobody).
    func showRival(ofActor id: Int) -> Int? { showBook.performers.firstIndex(of: id).flatMap { $0 > 0 ? $0 - 1 : nil } }
    /// Rival indices that have a body on the stage (the rest are silhouette cards).
    var showRivalsWithBodies: Set<Int> { Set(showBook.performers.indices.dropFirst().map { $0 - 1 }) }
    /// How the camera frames the stage this frame (nil = not on stage).
    var showFrame: ShowFrame? { show.onStage ? show.frame : nil }
    /// A stage body: the player's or a rival's (the wardrobe hides on the rivals and the parked).
    func showHidesWear(_ id: Int) -> Bool { show.active && (id != show.playerID) }
    /// The rival bodies are out of the picture in the solo rounds (Look, Trick): they come on for the Dance and the results.
    func showHides(_ id: Int) -> Bool {
        guard show.onStage, id != show.playerID, showBook.performers.contains(id) else { return false }
        return show.isPractice || !(show.round == .dance || (show.round == .results && show.trickStage != .performing))
    }

    // MARK: world swaps (under the white)

    private func showSwap(_ dest: ShowFlow.Dest) {
        let book = showBook
        switch dest {
        case .stage:
            let player = show.playerID
            let others = book.actors.indices.filter { $0 != player }
            let want = show.isPractice ? 1 : min(book.actors.count, 4)
            book.performers = Array(([player] + others).prefix(want))
            book.parked = book.actors.indices.filter { !book.performers.contains($0) }
            book.palettes = [:]; book.homes = [:]; book.autonomy = [:]; book.arena = [:]; book.dancing = [:]; book.danceRestart = [:]; book.flopT = nil; book.turned = []
            let spots = ShowStage.spots(bodies: book.performers.count)
            for (k, aid) in (book.performers + book.parked).enumerated() where book.actors.indices.contains(aid) {
                let a = book.actors[aid]
                guard let brain = a.brain else { continue }
                book.homes[aid] = a.floor; book.autonomy[aid] = brain.autonomy; book.arena[aid] = a.sim.arenaRadius
                brain.abortAll(a.sim, a.skinner)
                brain.commandedIdle = nil; brain.commandedFlip = false; brain.commandedDecor = nil
                a.sim.arenaRadius = .infinity
                let onStage = k < book.performers.count
                a.sim.teleport(toXZ: onStage ? spots[k] : ShowStage.parkSpot(aid))
                brain.currentPose(a.sim)
                a.skinner.jelly.reset()
                brain.autonomy = false
                brain.idleBlocked = true
                brain.restTimer = 0.4
                if onStage, k > 0, let s = show.sim, k - 1 < s.rivals.count { book.palettes[aid] = ShowRivalSource.palette(for: s.rivals[k - 1]) }
            }
        case .room:
            let c = VoiceCoordinator.comeSpot
            var taken: [SIMD2<Float>] = [c]
            for aid in book.performers + book.parked where book.actors.indices.contains(aid) {
                let a = book.actors[aid]
                guard let brain = a.brain else { continue }
                brain.abortAll(a.sim, a.skinner)
                brain.commandedIdle = nil
                a.sim.arenaRadius = book.arena[aid] ?? a.sim.arenaRadius
                var spot = aid == show.playerID ? c : (book.homes[aid] ?? Self.greetSpot(aid))
                if aid != show.playerID, taken.contains(where: { simd_distance($0, spot) < 1.5 }) {
                    spot = [SIMD2<Float>(-1.6, 0.4), SIMD2(1.6, 0.4), SIMD2(0, -1.0), SIMD2(-1.8, -1.2)].first { s in !taken.contains { simd_distance($0, s) < 1.5 } } ?? spot
                }
                spot = brain.fixed(spot)
                taken.append(spot)
                a.sim.teleport(toXZ: spot)
                brain.currentPose(a.sim)
                a.skinner.jelly.reset()
                brain.autonomy = book.autonomy[aid] ?? true
                brain.idleBlocked = false
                brain.restTimer = 2
            }
            book.performers = []; book.parked = []; book.palettes = [:]; book.dancing = [:]
        }
    }

    // MARK: the bodies' acts

    private func stageActor(_ k: Int) -> JellyActor? {
        let book = showBook
        guard book.performers.indices.contains(k), book.actors.indices.contains(book.performers[k]) else { return nil }
        return book.actors[book.performers[k]]
    }

    /// The player's Jelbie does the trick (the voice tricks' moves); a flop is the move cut short into a wobble.
    private func showPerform(_ t: VoiceTrick, success: Bool) {
        guard let a = stageActor(0), let b = a.brain else { return }
        b.abortAll(a.sim, a.skinner)
        if t == .flip { b.commandedFlipFail = !success; b.commandedFlip = true }
        else if let k = VoiceCoordinator.idleKind(for: t) {
            if success { b.commandedIdle = k } else { b.commandedIdle = k; showBook.flopT = 0 }
        }
        if success { b.face(.excited, hold: 1.2) } else { b.face(.worried, hold: 1.4) }
        for k in 1..<max(showBook.performers.count, 1) {                  // the rivals watch: a giggle at a flop, a happy face at a landing
            guard let r = stageActor(k), let rb = r.brain else { continue }
            rb.face(success ? .happy : .oh, hold: 1.2)
        }
    }
    /// Everybody on the stage dances (`on`) with the player's dance (the rivals copy him) or stands.
    private func showDance(_ d: DanceID?, on: Bool) {
        let book = showBook
        for (k, aid) in book.performers.enumerated() where book.actors.indices.contains(aid) {
            guard let b = book.actors[aid].brain else { continue }
            if on {
                let move = (d ?? .sway).move
                book.dancing[aid] = move
                book.danceRestart[aid] = Float(k) * 0.35          // a little stagger so the row is not in lockstep
                b.face(.happy, hold: 3)
            } else {
                book.dancing[aid] = nil
                if b.idleState.kind != nil, !b.idleState.yielding { b.idleState.yielding = true; b.idleState.yieldT = 0 }
            }
        }
    }
    /// A Perfect / Good / Slip: the player's face and blush follow the beat.
    private func showHit(_ g: DrillGrade) {
        guard let a = stageActor(0), let b = a.brain else { return }
        switch g {
        case .perfect: b.blushBump(hold: 0.8, peak: 0.6); b.face(.joyArc, hold: 0.5)
        case .good: b.face(.happy, hold: 0.4)
        case .miss: b.face(.oh, hold: 0.5); b.jellyKick = max(b.jellyKick, 1.2)
        }
    }
    private func showBurst() {
        guard let a = stageActor(0), let b = a.brain else { return }
        b.blushBump(hold: 3, peak: 0.9)
        touchPlay?.spawnHeart(now: CACurrentMediaTime())
    }
    /// The results are in: the player's Jelbie jumps for joy and blushes; the rivals react (a bounce for a winner, a giggle for the rest).
    private func showCelebrate(place: Int) {
        let book = showBook
        for (k, aid) in book.performers.enumerated() where book.actors.indices.contains(aid) {
            let a = book.actors[aid]
            guard let b = a.brain else { continue }
            b.abortAll(a.sim, a.skinner)
            if k == 0 {
                b.commandedIdle = .joy
                b.blushBump(hold: 3.5, peak: place == 1 ? 0.9 : 0.7)
                b.face(place <= 2 ? .excited : .happy, hold: 2.5)
                b.postEvent(.joyJump)
            } else {
                b.commandedIdle = place == 1 ? .bounce : .giggle
                b.face(place == 1 ? .happy : .joyArc, hold: 2)
            }
        }
        if place == 1 { touchPlay?.spawnHeart(now: CACurrentMediaTime()) }
    }

    // MARK: per fixed step (the stage calls it every step, with every Jelbie)

    func tickShow(_ actors: [JellyActor], dt: Float) {
        showBook.actors = actors
        if show.active { for a in actors { a.brain?.sleepLocked = true } }
        show.tick(dt: dt)
        guard show.active, show.onStage else { return }
        let book = showBook
        for (k, aid) in book.performers.enumerated() where actors.indices.contains(aid) {
            let a = actors[aid]
            guard let b = a.brain else { continue }
            b.idleBlocked = true
            b.autonomy = false
            // face the crowd once the stage is up (a stepping turn to heading 0, toward the camera), once per body
            if show.phase == .stage, show.wipe == 0, !book.turned.contains(aid), b.idleState.kind == nil, case .none = b.script {
                book.turned.insert(aid)
                if abs(b.yaw) > 0.25 { b.startTurn(to: 0, sim: a.sim) }
            }
            // the dance loops: when the move ends, start it again (after the stagger)
            if let move = book.dancing[aid], b.idleState.kind == nil, b.commandedIdle == nil, case .none = b.script {
                let wait = book.danceRestart[aid] ?? 0
                if wait <= 0 { b.commandedIdle = move; book.danceRestart[aid] = 0.25 } else { book.danceRestart[aid] = wait - dt }
            }
            if k == 0, var f = book.flopT {               // the cute flop: the move is cut short after a beat and he wobbles
                f += dt
                if f > 0.9 { book.flopT = nil; b.abortAll(a.sim, a.skinner); b.jellyKick = max(b.jellyKick, 2.4); b.face(.worried, hold: 1) } else { book.flopT = f }
            }
        }
    }

    // MARK: welcome home

    /// Back in the room: a 1st is celebrated like a race win (everybody bounces); "Show again" reopens the lobby.
    func showWelcomeHome(_ id: Int, won: Bool, again: Bool) {
        let book = raceBook
        book.returner = id; book.won = won; book.homeAge = 0; book.returnerHopped = false; book.celebrated = false
        greetPending = Set((0..<max(jellies.count, 1)).filter { $0 != id && $0 > 0 })
        greetOthers = [:]
        bubbleHub.greetClock = 0; bubbleHub.greetHearts = [:]
        if id != 0 { greeting = true; greetHop = false; queued = [.come(to: greetSpotNow(0))] }
        if again { requestTown(.show) }
    }
}
