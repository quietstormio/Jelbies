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
    /// Borrowed rival bodies (the park's visitor bodies, ids after the roster's) for the rivals the roster has no spare Jelbie for; gone when the trip is over.
    var extra: [JellyActor] = []
    var extraSpecs: [ParkVisitor] = []
    /// Rival index -> the actor id that plays her on the stage (the player's spare Jelbies first, then the borrowed bodies). A rival without an entry is a silhouette card.
    var rivalBody: [Int: Int] = [:]
    /// Seconds since a rival's flop began, by actor id (the wobble lands a beat later).
    var flops: [Int: Float] = [:]
    /// Where each walking body was sent (the player's Jelbie and the rivals), to know when it has arrived.
    var goals: [Int: SIMD2<Float>] = [:]
    /// The Trick round's stage is set (rivals at their rest spots).
    var trickSet = false
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
        show.onRival = { [weak self] cue in self?.showRivalCue(cue) }
        show.rivalReady = { [weak self] who, centre in self?.showArrived(who, atCentre: centre) ?? true }
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
        if race.active || raceWait != nil { return "\(jelly(id)?.name ?? "Your Jelbie") is at Jelly Race." }
        if volley.active || volleyWork.wait != nil { return "\(jelly(id)?.name ?? "Your Jelbie") is at the beach." }
        if trayOut || meal != nil || wanted != nil { return "A meal is out. Let \(jelly(id)?.name ?? "Your Jelbie") finish first." }
        if bath.active { return "The clean-up is going on." }
        if focus.isActive || focus.phase != .roaming { return "\(jelly(id)?.name ?? "Your Jelbie") is in the close-up. Let go first." }
        if voice.mode.phase != .idle || voice.voiceGoing || voice.comingNow { return "\(jelly(id)?.name ?? "Your Jelbie") is listening to you." }
        if !raceBook.actors.isEmpty, !(raceBook.actors.indices.contains(id) && raceBook.actors[id].brain != nil) { return "\(jelly(id)?.name ?? "Your Jelbie") is not in the room." }
        return nil
    }
    func canShow(jelly id: Int) -> Bool { showBlocker(jelly: id) == nil }

    /// What the player's Jelbie brings to the stage: his condition in every stat, his shine and lint, the dance he knows best, his learned tricks.
    func showPlayerInput(jelly id: Int) -> ShowPlayerInput {
        guard let p = jelly(id) else { return ShowPlayerInput() }
        var input = ShowPlayerInput(name: p.name)
        for t in WearTag.allCases { input.condition[t] = p.stats.condition(t.condition) }
        input.glow = p.grime.sparkle; input.dirt = p.grime.dirt
        input.dance = p.stats.bestDance
        for t in ShowTrickInfo.stageTricks where store.knows(t, character: p.character) { input.tricks[t] = 1 }          // what he knows: defaults + bought for him / for everyone
        input.care = showCare(jelly: id)
        return input
    }
    /// How well cared for he is, 0...1: the mean of his three needs (hunger, thirst, attention) and how clean he is. Lowers the chance a trick slips.
    func showCare(jelly id: Int) -> Float {
        guard let p = jelly(id) else { return 0.5 }
        let n = NeedKind.allCases.map { p.needs.level($0) }
        let all = n + [1 - p.grime.dirt]
        return min(max(all.reduce(0, +) / Float(all.count), 0), 1)
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
        s.dance = ShowScoring.dance(accuracy: 0.7)
        // the three best tricks on his menu, each worth its points less the chance it slips into the flop
        let menu = ShowTrickInfo.menu(learned: p.tricks.keys)
        let worth: [Float] = menu.map { t in
            let d = ShowTrickInfo.difficulty(t), miss = ShowScoring.missChance(difficulty: d, care: p.care)
            let tb = Float(theme.trickBonus(ShowTrickInfo.tags(t)))
            return (1 - miss) * Float(ShowScoring.basePoints(difficulty: d, repeated: false)) + miss * Float(ShowTuning.flopPoints) + tb
        }
        s.trick = min(100, worth.sorted(by: >).prefix(ShowScoring.turns).reduce(0, +))
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
        cutWelcomeHome()
        queued.removeAll(); callRunning = false
        voice.cancel()
        if outingGate([id], again: { [weak self] in self?.startShow(jelly: id, rank: rank, seed: seed) }) { return }          // he runs out of the room first
        let bodies = max(1, min(raceBook.actors.count, 4))
        show.begin(playerID: id, name: prof.name, character: prof.character, input: showPlayerInput(jelly: id), rank: r, dayKey: Self.showDay, bodies: bodies, seed: seed ?? Self.showSeed)
        show.setOutfit(showOutfitTags(jelly: id))
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
        guard show.onStage, id != show.playerID else { return false }
        let inTrick = show.round == .trick || (show.round == .results && show.trickStage != .pick)          // (the last turn's rivals play on after the sim has its results)
        if showBook.extra.contains(where: { $0.id == id }) { return !inTrick }          // the borrowed bodies are on only for the Trick round
        guard showBook.performers.contains(id) else { return false }
        return !(show.round == .dance || inTrick || show.round == .results)
    }

    // MARK: world swaps (under the white)

    private func showSwap(_ dest: ShowFlow.Dest) {
        let book = showBook
        switch dest {
        case .stage:
            let player = show.playerID
            let others = book.actors.indices.filter { $0 != player }
            let want = min(book.actors.count, 4)
            book.performers = Array(([player] + others).prefix(want))
            book.parked = book.actors.indices.filter { !book.performers.contains($0) }
            book.palettes = [:]; book.homes = [:]; book.autonomy = [:]; book.arena = [:]; book.dancing = [:]; book.danceRestart = [:]; book.flopT = nil; book.turned = []
            book.flops = [:]; book.goals = [:]; book.rivalBody = [:]; book.trickSet = false
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
            showSpawnExtras()
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
            showRemoveExtras()
            book.flops = [:]; book.goals = [:]; book.rivalBody = [:]; book.trickSet = false
        }
    }

    // MARK: the rivals' bodies (borrowed like the race's temporary rivals)

    /// Every rival gets a body for the Trick round: the player's spare Jelbies first (tinted, as in the dance), then the park's visitor bodies for the rest, named and
    /// tinted from the rival and given the species signature of her colour (the race's path, GameCare+Race.swift). They wait far off stage and are hidden until the Trick round.
    private func showSpawnExtras() {
        let book = showBook
        guard let s = show.sim, !book.actors.isEmpty else { return }
        let spare = max(book.performers.count - 1, 0)
        for k in 0..<min(spare, s.rivals.count) { book.rivalBody[k] = book.performers[k + 1] }
        let missing = s.rivals.count - spare
        guard missing > 0, book.extra.isEmpty, let spawn = parkBook.spawn else { return }
        let specs: [ParkVisitor] = (spare..<s.rivals.count).map { i in
            ParkVisitor(id: 9100 + i, name: s.rivals[i].name, colour: .cream, signature: LocalRivalSource.signature(forTint: s.rivals[i].tint), wear: nil, style: .balanced, blurb: "", greeting: "")
        }
        if guestBook.actor != nil { guestRemove() }          // (the guest's body is normally gone already: a trip puts it away first)
        let bodies = spawn(specs, specs.indices.map { SIMD2<Float>(40 + Float($0) * 3, 0) })
        guard bodies.count == specs.count, bodies.enumerated().allSatisfy({ $0.element.id == book.actors.count + $0.offset }) else { parkBook.clear?(); return }
        book.extra = bodies; book.extraSpecs = specs
        for (j, a) in bodies.enumerated() {
            a.sim.arenaRadius = .infinity
            a.sim.teleport(toXZ: Self.showFarSpot(j))
            a.brain?.currentPose(a.sim)
            a.brain?.autonomy = false; a.brain?.idleBlocked = true
            book.rivalBody[spare + j] = a.id
            book.palettes[a.id] = ShowRivalSource.palette(for: s.rivals[spare + j])
        }
    }
    /// The borrowed bodies go (the swap home, under the white): looks put away, bodies hidden, nothing left behind.
    private func showRemoveExtras() {
        let book = showBook
        guard !book.extra.isEmpty else { return }
        for a in book.extra { a.brain?.abortAll(a.sim, a.skinner); visitorPutAway(a) }
        parkBook.clear?()
        let ids = Set(book.extra.map(\.id))
        book.palettes = book.palettes.filter { !ids.contains($0.key) }
        book.flops = book.flops.filter { !ids.contains($0.key) }
        book.goals = book.goals.filter { !ids.contains($0.key) }
        book.extra = []; book.extraSpecs = []
    }
    static func showFarSpot(_ j: Int) -> SIMD2<Float> { SIMD2(40 + Float(j) * 3, 2) }
    /// The stage body of an actor id: the roster's, then the borrowed ones.
    private func showBody(_ aid: Int) -> JellyActor? {
        let book = showBook
        if book.actors.indices.contains(aid) { return book.actors[aid] }
        return book.extra.first { $0.id == aid }
    }
    private func rivalActor(_ i: Int) -> JellyActor? { showBook.rivalBody[i].flatMap { showBody($0) } }

    /// Puts a body at `p` at once (the walk's end, Skip, the Trick round's set), facing the crowd.
    private func showSnap(_ a: JellyActor, to p: SIMD2<Float>) {
        guard let b = a.brain else { return }
        b.abortAll(a.sim, a.skinner)
        b.commandedIdle = nil; b.commandedFlip = false
        a.sim.teleport(toXZ: p)
        b.currentPose(a.sim)
        a.skinner.jelly.reset()
        b.restTimer = 0.4
        if abs(b.yaw) > 0.25 { b.startTurn(to: 0, sim: a.sim) }
    }
    /// A walk to `p` (stepping, then a turn to the crowd): the goal is remembered to know when he is there.
    private func showWalk(_ a: JellyActor, to p: SIMD2<Float>) {
        guard let b = a.brain else { return }
        b.abortAll(a.sim, a.skinner)
        b.commandedIdle = nil; b.commandedFlip = false
        showBook.flops[a.id] = nil
        showBook.goals[a.id] = b.fixed(p)
        b.requestNow(.come(to: p))
    }
    /// The Trick round's stage: the rivals stand at their rest spots; after it they are back in the dance row (and the borrowed ones far off) for the results.
    private func showSetTrick(_ on: Bool) {
        let book = showBook
        book.trickSet = on
        guard let s = show.sim else { return }
        let row = ShowStage.spots(bodies: book.performers.count)
        for k in s.rivals.indices {
            guard let a = rivalActor(k) else { continue }
            if on { showSnap(a, to: ShowStage.rivalRest(k)) }
            else if let idx = book.performers.firstIndex(of: a.id) { showSnap(a, to: row[idx]) }
            else if let j = book.extra.firstIndex(where: { $0.id == a.id }) { showSnap(a, to: Self.showFarSpot(j)) }
        }
        if let p = stageActor(0) { showSnap(p, to: ShowStage.playerSpot) }
        book.goals = [:]; book.flops = [:]
    }
    /// The flow asks for the rivals' turn on the bodies.
    private func showRivalCue(_ cue: ShowFlow.RivalCue) {
        let book = showBook
        switch cue {
        case .playerAside(let aside):
            guard let a = stageActor(0) else { return }
            showWalk(a, to: aside ? ShowStage.playerAside : ShowStage.playerSpot)
        case .walkIn(let i):
            guard let a = rivalActor(i) else { return }
            showWalk(a, to: ShowStage.playerSpot)
        case .perform(let i, let t, let ok):
            guard let a = rivalActor(i), let b = a.brain else { return }
            if let g = book.goals[a.id], simd_distance(SIMD2(b.px, b.pz), g) > 0.8 { showSnap(a, to: g) }          // (a walk that never got there: he is in the middle for his trick)
            book.goals[a.id] = nil
            showDoTrick(a, t, success: ok, others: a.id)
        case .walkOut(let i):
            guard let a = rivalActor(i) else { return }
            showWalk(a, to: ShowStage.rivalRest(i))
        case .snap:
            guard let s = show.sim else { return }
            for k in s.rivals.indices { if let a = rivalActor(k) { showSnap(a, to: ShowStage.rivalRest(k)) } }
            if let p = stageActor(0) { showSnap(p, to: ShowStage.playerSpot) }
            book.goals = [:]; book.flops = [:]
        }
    }
    /// Has the body got where it was sent (nil = the player's Jelbie; `atCentre` is only the flow's wording)? A body with no walk under way is there.
    private func showArrived(_ who: Int?, atCentre: Bool) -> Bool {
        let book = showBook
        let a = who.map { rivalActor($0) } ?? stageActor(0)
        guard let a, let b = a.brain, let g = book.goals[a.id] else { return true }
        if b.pending != nil { return false }
        if case .none = b.script {} else { return false }
        if simd_distance(SIMD2(b.px, b.pz), g) < 0.6 { book.goals[a.id] = nil; return true }
        return false
    }

    // MARK: the bodies' acts

    private func stageActor(_ k: Int) -> JellyActor? {
        let book = showBook
        guard book.performers.indices.contains(k), book.actors.indices.contains(book.performers[k]) else { return nil }
        return book.actors[book.performers[k]]
    }

    /// The player's Jelbie does the trick (the voice tricks' moves); a flop is the move cut short into a wobble.
    private func showPerform(_ t: VoiceTrick, success: Bool) {
        guard let a = stageActor(0) else { return }
        showDoTrick(a, t, success: success, others: a.id)
    }
    /// A body does `t` (the same moves for the player and the rivals). The others on the stage watch: a giggle at a flop, a happy face at a landing.
    private func showDoTrick(_ a: JellyActor, _ t: VoiceTrick, success: Bool, others skip: Int) {
        guard let b = a.brain else { return }
        let player = a.id == stageActor(0)?.id
        b.abortAll(a.sim, a.skinner)
        if t == .flip { b.commandedFlipFail = !success; b.commandedFlip = true }
        else if let k = VoiceCoordinator.idleKind(for: t) {
            if success { b.commandedIdle = k } else { b.commandedIdle = k; if player { showBook.flopT = 0 } else { showBook.flops[a.id] = 0 } }
        }
        if success { b.face(.excited, hold: 1.2) } else { b.face(.worried, hold: 1.4) }
        var watchers: [JellyActor] = showBook.performers.compactMap { showBody($0) }
        watchers += showBook.extra
        for r in watchers where r.id != skip {
            guard let rb = r.brain else { continue }
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
                if place == 1 { b.proudStrutCue() }          // (batch-2 emote: a chest-out strut when he is next free)
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
        for (a, v) in zip(book.extra, book.extraSpecs) {          // the borrowed rival bodies: held like the others, their species art on
            guard let b = a.brain else { continue }
            b.idleBlocked = true; b.autonomy = false
            visitorLook(a, v, dt: dt)
        }
        // the Trick round's stage: the rivals to their rest spots when it begins, back to the row when it is over
        let inTrick = show.round == .trick || (show.round == .results && show.trickStage != .pick)
        if inTrick != book.trickSet, show.wipe == 0 { showSetTrick(inTrick) }
        for (aid, f0) in book.flops {          // a rival's cute flop: the move is cut short after a beat and she wobbles
            guard let a = showBody(aid), let b = a.brain else { book.flops[aid] = nil; continue }
            let f = f0 + dt
            if f > 0.9 { book.flops[aid] = nil; b.abortAll(a.sim, a.skinner); b.jellyKick = max(b.jellyKick, 2.4); b.face(.worried, hold: 1) } else { book.flops[aid] = f }
        }
        for (k, aid) in book.performers.enumerated() where actors.indices.contains(aid) {
            let a = actors[aid]
            guard let b = a.brain else { continue }
            b.idleBlocked = true
            b.autonomy = false
            // face the crowd once the stage is up (a stepping turn to heading 0, toward the camera), once per body
            if show.phase == .stage, show.wipe == 0, !book.turned.contains(aid), b.idleState.kind == nil, case .none = b.script {
                book.turned.insert(aid)
                if abs(b.yaw) > 0.25 { b.startTurn(to: 0, sim: a.sim) }
                if k == 0, show.round == .look { b.face(.happy, hold: 2.5) }          // the walk-on: a pleased pose for the judges
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
        if again { requestTown(.studio) }
    }
}
