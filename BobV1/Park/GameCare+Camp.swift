//
//  GameCare+Camp.swift
//  The Jelmiko Camp visit as a MODE of the park trip (camp-yard-r1): `park.place == .camp`. Same white wipe, camera, hidden home bodies, tap routing and visitor bodies as the park, but nobody comes along,
//  there is no picker, no cast from the pool, no toys, no friendships / gifts / save, no night closure (Camp is open day and night) and no bedtime call. The yard holds ONLY the Camp creatures.
//  The home Jelmiko stay on the stage hidden and still, as at the park; a sleeping one stays asleep (it is neither woken nor moved: the park wakes every sleeper before it opens, Camp leaves him asleep).
//  Everything the player does here is parkTrip-shaped: `requestCamp` -> the wipe -> `campSwap(.park)` (scenery, camera, bodies under the opaque white) -> play -> "Go home" -> `campSwap(.home)`.
//

import Foundation
import QuartzCore
import simd

extension GameCare {
    /// Where the visit reads and writes the lists (the save; tests use a suite), and what leaving does about the room: the core's `campVisitEnded` (true = the room was rebuilt, once).
    @MainActor static var campDefaults: UserDefaults = .standard
    @MainActor static var campLeave: (UserDefaults) -> Void = { _ = StartFlow.shared.campVisitEnded($0) }

    // MARK: entry

    /// Why Camp cannot be entered now (the friendly line); nil = it can. The park's rules minus the night closure and minus "a home creature is asleep".
    func campBlocker() -> String? {
        if park.active || cafe.active { return CafeBlock.busy.message }
        if raceBusy || show.active { return CafeBlock.competition.message }
        if roomSwitch.active { return CafeBlock.moving.message }
        if let b = roomActivityBlocker() {
            switch b {
            case .trip: return CafeBlock.competition.message
            case .bath: return CafeBlock.bath.message
            case .focus: return CafeBlock.focus.message
            case .meal: return CafeBlock.meal.message
            case .arranging: return CafeBlock.arranging.message
            case .sleeping: break          // (`raceBook.actors` is the home roster: a sleeping home creature must NOT block Camp; it just stays asleep, hidden. The last check of the list, so nothing behind it is skipped)
            default: return CafeBlock.busy.message
            }
        }
        if voice.mode.phase != .idle || voice.voiceGoing || voice.comingNow { return CafeBlock.listening.message }
        return nil
    }

    /// The Town's Camp tile (a later step) and `-StartCamp`: blocked = a friendly toast; else the white wipe starts at once (no picker, nobody goes along).
    func requestCamp() {
        if let why = campBlocker() {
            park.say(why)
            AudioHub.shared.play(.notEnough)
            return
        }
        select.cancel(); cutWelcomeHome(); queued.removeAll(); callRunning = false
        voice.cancel()
        if guestBook.actor != nil { guestRemove() }          // (a friend over at home goes first, as the Show does)
        park.beginCamp()
    }

    #if targetEnvironment(simulator)
    nonisolated(unsafe) static var startCampPending = UserDefaults.standard.integer(forKey: "StartCamp") != 0
    nonisolated(unsafe) static var startCampFrames = 0
    /// Capture aid: `-StartCamp 1` opens the Camp yard once the room is up (retried like `-StartPark 1`; simulator only).
    func tickCampStart() {
        if park.place == .camp, park.phase == .goOut, parkFadeBlocked {
            let why = ["race": race.active, "show": show.active, "volley": volley.active, "raceWait": raceWait != nil, "bath": bath.active, "focus": focus.isActive, "trayOut": trayOut, "dining": dining.phase != .absent, "groupActive": groupActive, "arranging": arranging, "cafe": cafe.active].filter(\.value).keys.sorted()
            NSLog("[startcamp] the fade out is blocked by %@", why.joined(separator: ","))
        }
        guard Self.startCampPending else { return }
        if park.phase != .off { Self.startCampPending = false; return }
        Self.startCampFrames += 1
        if Self.startCampFrames > 90, Self.startCampFrames % 45 == 0, !park.picking {          // (Camp sends nobody out, so an outing in progress does not hold it back)
            if let why = campBlocker() { NSLog("[startcamp] blocked at frame %d: %@", Self.startCampFrames, why) }
            else { Self.startCampPending = false; requestCamp() }
        }
    }
    #endif

    // MARK: per fixed step

    /// Once per fixed step while the yard is up (after the wipe-in has started).
    func tickCamp(dt: Float) {
        for a in parkBook.actors { if let c = CampBook.shared.bodies[a.id] { campLook(a, c, dt: dt) } }
        for a in parkBook.actors { let c = a.sim.centroid(); bubbleHub.heads[a.id] = SIMD3(c.x, c.y + BlobShape.H * 0.5, c.z) }          // (where a heart over a Camp body is drawn)
        tickCampStroke(dt: dt)
        tickCampLeaving(dt: dt)
        let want: Float = (CampUI.shared.selected != nil && CampUI.shared.sheet == .none && !CampUI.shared.moving) ? 1 : 0          // the yard moves aside for an open card
        GameCamera.campCardLift += (want - GameCamera.campCardLift) * min(1, dt * 6)
        #if targetEnvironment(simulator)
        if Self.spreadLogOn, park.phase == .playing { campSpreadSample(dt: dt) }
        campDemoTick()
        #endif
    }

    /// One Camp body's look for this step, from the COPY taken when it appeared (never from the save): the twin of `tickWear` + `tickFeature` + `visitorLook`.
    func campLook(_ a: JellyActor, _ c: CampCreature, dt: Float) {
        guard let b = a.brain else { return }
        b.idleMood = .happy
        b.sleepLocked = true
        b.feature = c.feature
        b.pandaInk = c.panda
        wardrobe.tick(id: a.id, brain: b, sim: a.sim, outfit: c.worn, role: .none, hideAll: false, dt: dt)
        features.setWingTint(a.id, c.whiteWing ? WhiteWing.wingTint : nil)
        features.setSpikeTint(a.id, c.spikeTint)
        features.tick(id: a.id, brain: b, sim: a.sim, feature: c.feature, worn: wornArt(a.id), hideAll: false, dt: dt)
        if let s = features.slot(a.id) {
            b.wingsFolded = c.feature == .wings && s.fit.folded
            b.wingFlapLimit = c.feature == .wings ? s.fit.flapMax : 75
            wardrobe.setArtOverride(a.id, s.fit.hatVariant)
        }
    }

    /// The Camp bodies the stage wears / shoes / fits (none outside the yard).
    func campBodies(_ parkActors: [JellyActor]) -> [JellyActor] { park.place == .camp && park.inScene ? parkActors : [] }

    /// A tap on a Camp body selects its creature (its chip lights, the card opens) and it smiles; a tap on the grass lets go of the selection.
    func campTapped(_ bodyID: Int?) {
        let ui = CampUI.shared
        guard ui.sheet == .none, ui.leaving == nil else { return }
        guard let id = bodyID, let a = parkBook.actors.first(where: { $0.id == id }), let c = CampBook.shared.bodies[id] else { ui.selected = nil; return }
        AudioHub.shared.uiTap()
        ui.select(c.id)
        a.brain?.face(.happy, hold: 1.5)
    }

    #if targetEnvironment(simulator)
    /// `-CampDemo select|bringhome|swap|dropoff|goodbye|goodbyego` (simulator captures; a command line cannot tap): ~6 s into the yard, does that thing to the first Camp creature once.
    nonisolated(unsafe) static var demoState = UserDefaults.standard.string(forKey: "CampDemo")
    nonisolated(unsafe) static var demoFrames = 0, demoMoved = false, demoStrokeBody = -1, demoStrokeUntil = 0
    func campDemoTick() {
        guard let m = Self.demoState, park.phase == .playing, let first = CampUI.shared.members.first ?? (m == "home" ? CampCreature.make(instance: 0, worn: [:]) : nil) else { return }
        Self.demoFrames += 1
        if Self.demoStrokeBody >= 0 { if Self.demoFrames < Self.demoStrokeUntil { CampUI.shared.strokeMoved(body: Self.demoStrokeBody, now: CACurrentMediaTime()) } else { Self.demoStrokeBody = -1 } }
        if m == "home", Self.demoFrames == 1200 { park.goHome(); return }
        if m == "movehome", Self.demoMoved, Self.demoFrames > 361 + 300 { Self.demoMoved = false; park.goHome(); return }
        guard Self.demoFrames == 360 else { return }
        let ui = CampUI.shared
        switch m {
        case "select": ui.select(first.id)
        case "bringhome": ui.select(first.id); campBringHomeTapped(first.id)
        case "swap": ui.select(first.id); campBringHomeTapped(first.id)
        case "dropoff": campDropOffTapped()
        case "goodbye": ui.select(first.id); ui.sheet = .goodbye(first.id)
        case let x where x.hasPrefix("stroke:"):          // `-CampDemo stroke:Maple`: strokes that creature for 6 s
            if let c = CampUI.shared.members.first(where: { $0.name.lowercased() == x.dropFirst(7).lowercased() }), let a = parkBook.actors.first(where: { CampBook.shared.bodies[$0.id]?.id == c.id }) { Self.demoStrokeBody = a.id; Self.demoStrokeUntil = Self.demoFrames + 360 }
        case "goodbyego": ui.select(first.id); campGoodbyeConfirmed(first.id)
        case "movehome":          // a net change, then leave: bring home (or swap with the last at home when home is full)
            ui.select(first.id); Self.demoMoved = true
            if let out = JellyRoster.savedIDs().last, JellyRoster.savedIDs().count >= JellyRoster.maxCount { campSwapConfirmed(incoming: first.id, out: out) } else { campBringHomeTapped(first.id) }
        default: break
        }
    }
    #endif

    #if targetEnvironment(simulator)
    /// `-CampSpreadLog 1` (simulator captures): every 30 s of the yard playing, `[campspread]` with the mean nearest-neighbour distance (sampled each second) and the share of the yard's 1 m cells any body has stood in so far.
    nonisolated(unsafe) static var spreadLogOn = UserDefaults.standard.integer(forKey: "CampSpreadLog") != 0
    nonisolated(unsafe) static var spreadT: Float = 0, spreadClock: Float = 0, spreadNN: [Float] = [], spreadCells = Set<Int>()
    func campSpreadSample(dt: Float) {
        Self.spreadT += dt; Self.spreadClock += dt
        guard Self.spreadClock >= 1 else { return }
        Self.spreadClock = 0
        let p = parkBook.actors.map(\.floor)
        guard p.count >= 2 else { return }
        var sum: Float = 0
        for i in p.indices { sum += p.indices.filter { $0 != i }.map { simd_distance(p[i], p[$0]) }.min() ?? 0 }
        Self.spreadNN.append(sum / Float(p.count))
        for q in p { let c = Int(floorf(q.x + 3)), r = Int(floorf(q.y + 3.5)); if c >= 0, c < 6, r >= 0, r < 8 { Self.spreadCells.insert(r * 6 + c) } }
        if Int(Self.spreadT.rounded()) % 30 == 0 {
            NSLog("[campspread] t=%.0f meanNN=%.2f coverage=%d/48 bodies=%d", Self.spreadT, Self.spreadNN.reduce(0, +) / Float(Self.spreadNN.count), Self.spreadCells.count, p.count)
        }
    }
    #endif

    // MARK: the world swaps (under the white)

    func campSwap(_ dest: ParkTrip.Dest) {
        let book = parkBook, work = book.work
        let roster = book.roster
        switch dest {
        case .park:
            work.homes = [:]; work.autonomy = [:]; work.arena = [:]; work.owed = [:]; work.giftState = 0; work.saveT = 0; work.friendSession = [:]; work.shared.reset()
            work.ownToys = []; work.hopHost = nil
            book.comers = []; book.cast = []          // nobody comes along: every home body is hidden (`parkHides`)
            for a in roster {
                guard let brain = a.brain else { continue }
                work.homes[a.id] = a.floor; work.autonomy[a.id] = autonomySnapshot(a.id, brain); work.arena[a.id] = a.sim.arenaRadius
                if brain.isSleeping { continue }          // a sleeper stays exactly as it is
                brain.abortAll(a.sim, a.skinner)
                brain.commandedIdle = nil; brain.commandedDecor = nil; brain.commandedFlip = false
            }
            RoomLayout.apply(RoomCatalog.camp)
            GameCamera.configureCamp()
            if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
                for a in roster where a.sim.arenaRadius.isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
            }
            syncDecor()
            StartFlow.shared.campVisitBegan(Self.campDefaults)          // (the saved home list: on the way out, a net change rebuilds the room once)
            CampUI.shared.reset(arrival: StartFlow.shared.campArrival); StartFlow.shared.campArrival = nil
            CampUI.shared.entryHome = JellyRoster.savedIDs(Self.campDefaults)
            campSpawnNow()
            if select.phase != .none { select.cancel() }
            park.card = nil
        case .home:
            campClearBodies()
            RoomLayout.apply(RoomCatalog.def(store.currentRoom))
            GameCamera.endPark(count: max(jellies.count, 1))
            if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
                for a in roster where (work.arena[a.id] ?? a.sim.arenaRadius).isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
            }
            syncDecor()
            for a in roster {
                guard let brain = a.brain else { continue }
                brain.autonomy = work.autonomy[a.id] ?? true
                brain.idleBlocked = false
                if brain.isSleeping { continue }          // (asleep at home through the whole visit: not moved, not woken)
                if let spot = work.homes[a.id] { rehome(a, at: brain.fixed(spot)) }
                brain.restTimer = 2
            }
            work.homes = [:]; work.autonomy = [:]; work.arena = [:]; work.owed = [:]
            book.comers = []
            park.card = nil
            // a creature came home / went to Camp / swapped (net): the room is rebuilt once from the saved lists, behind the app's curtain (StartFlow); no net change: nothing is rebuilt
            if StartFlow.homeChanged(since: CampUI.shared.entryHome, Self.campDefaults) { leftActive(); voice.training.save(); voice.cancel() }
            Self.campLeave(Self.campDefaults)
            CampUI.shared.reset(arrival: nil)
        }
    }

    // MARK: stroking a Camp creature (Y7)

    /// A drag of 30 pt or more that began on a Camp body strokes it: the home cuddle's pieces on a visitor body (no TouchPlay: that machinery is the room's focus mode). Eyes closed in a joyful arc, a blush,
    /// a heart every 0.6 s over its head with a soft haptic tick, its own happy chirp (its species' voice, through the voice gate, so never more often than the gate lets it), wandering paused.
    static let strokeHeartEvery = 0.6
    func tickCampStroke(dt: Float, now: Double = CACurrentMediaTime()) {
        let ui = CampUI.shared
        guard let s = ui.stroke else { return }
        guard let a = parkBook.actors.first(where: { $0.id == s.body }), let b = a.brain, now - s.lastMove < 0.3, park.phase == .playing else {
            if let a = parkBook.actors.first(where: { $0.id == s.body }), let b = a.brain, let was = ui.strokeWasAutonomous.removeValue(forKey: s.body) { b.autonomy = was }
            ui.stroke = nil
            return
        }
        if ui.strokeWasAutonomous[s.body] == nil { ui.strokeWasAutonomous[s.body] = b.autonomy; AudioHub.shared.chirp(jelly: s.body, .happy, src: "camp"); ui.strokeStats.chirps += 1 }
        b.autonomy = false
        b.socialBook.cooldown = max(b.socialBook.cooldown, 3)
        b.face(.joyArc, hold: 0.5)
        b.blushBump(hold: 0.5, peak: 0.45)
        if now - s.lastHeart >= Self.strokeHeartEvery {
            ui.stroke?.lastHeart = now
            bubbleHub.spawnHeart(for: s.body, now: now); ui.strokeStats.hearts += 1
            touchPlay?.haptics.transient(now: now, intensity: 0.35, sharpness: 0.25); ui.strokeStats.haptics += 1
            if Int(now - s.began) % 3 == 2, now - s.began > 1 { AudioHub.shared.chirp(jelly: s.body, .happy, src: "camp"); ui.strokeStats.chirps += 1 }          // (a purr-like murmur every few seconds of a long stroke)
        }
    }

    // MARK: the yard's bodies

    /// The Camp creatures from the SAVED lists, copied once, on their spots (only under an opaque white).
    func campSpawnNow() {
        let book = parkBook
        let list = Array(Self.campSource().prefix(JellyCamp.cap))          // (never more than six)
        CampUI.shared.members = list
        let bodies = CampBook.shared.spawn?(list, CampLayout.spots(count: list.count)) ?? []
        book.actors = Array(bodies.prefix(list.count))
        for (a, c) in zip(book.actors, list) { CampBook.shared.bodies[a.id] = c; JellyRoster.visitBodies[a.id] = c.id; a.brain?.face(.excited, hold: 1.5) }
    }

    /// The looks are put away and the bodies hidden (the wardrobe and feature slots are by body id).
    func campClearBodies() {
        let book = parkBook
        for a in book.actors { visitorPutAway(a); features.setWingTint(a.id, nil); features.setSpikeTint(a.id, nil) }
        CampBook.shared.bodies = [:]; JellyRoster.visitBodies = [:]
        book.clear?()
        book.actors = []; book.cast = []
    }

    /// The white is opaque after a move: the yard's bodies are made again from the saved lists.
    func campRefresh() {
        let ui = CampUI.shared
        campClearBodies()
        campSpawnNow()
        if let sel = ui.selected, !ui.members.contains(where: { $0.id == sel }) { ui.selected = nil }
        ui.leaving = nil
        if let t = ui.pendingToast { park.say(t); ui.pendingToast = nil }
    }

    // MARK: the moves (each through the core's wrappers, then a white wipe and a new yard)

    func campRefused(_ line: String) { park.say(line); AudioHub.shared.play(.notEnough) }

    /// "Bring home": straight when home has room, else the swap sheet (who goes to Camp?).
    func campBringHomeTapped(_ id: Int, defaults d: UserDefaults = .standard) {
        let l = JellyCamp.savedLists(d)
        if JellyCamp.canBringHome(id, home: l.home, camp: l.camp) {
            guard StartFlow.shared.campBringHome(id, defaults: d) else { campRefused("That did not work. Try again."); return }
            CampUI.shared.pendingToast = "\(JellyRoster.nameOf(id)) is coming home!"
            CampUI.shared.finishMove()
            park.beginRefresh()
        } else if l.home.count >= JellyRoster.maxCount, l.camp.contains(id) {
            CampUI.shared.sheet = .swap(incoming: id)
        } else { campRefused("Camp is not open for that right now.") }
    }

    /// The swap sheet's "Swap".
    func campSwapConfirmed(incoming inID: Int, out outID: Int, defaults d: UserDefaults = .standard) {
        guard StartFlow.shared.campSwap(in: inID, out: outID, defaults: d) else { campRefused("That did not work. Try again."); return }
        CampUI.shared.pendingToast = "\(JellyRoster.nameOf(inID)) is coming home, \(JellyRoster.nameOf(outID)) goes to Camp."
        CampUI.shared.finishMove()
        park.beginRefresh()
    }

    /// "Drop off": the picker, or a short line when it cannot be.
    func campDropOffTapped(defaults d: UserDefaults = .standard) {
        let l = JellyCamp.savedLists(d)
        if l.camp.count >= JellyCamp.cap { campRefused("Camp is full. Bring someone home first."); return }
        if l.home.count < 2 { campRefused("Keep at least one Jelmiko at home."); return }
        CampUI.shared.sheet = .dropOff
    }

    func campDropOffConfirmed(_ id: Int, defaults d: UserDefaults = .standard) {
        guard StartFlow.shared.campSendToCamp(id, defaults: d) else { campRefused("That did not work. Try again."); return }
        CampUI.shared.pendingToast = "\(JellyRoster.nameOf(id)) is at Camp now."
        CampUI.shared.finishMove()
        park.beginRefresh()
    }

    // MARK: say goodbye (committed at the hold; the body waves, walks to the gate, then the white brings the yard back without it)

    func campGoodbyeConfirmed(_ id: Int, defaults d: UserDefaults = .standard) {
        let ui = CampUI.shared
        let name = ui.members.first { $0.id == id }?.name ?? JellyRoster.nameOf(id)          // (the copy's name: the save is about to be purged)
        guard StartFlow.shared.campSayGoodbye(id, defaults: d) else { campRefused("That did not work. Try again."); return }
        // the live wallet follows what the core wrote (an absolute target): never add on top of it
        let target = d.integer(forKey: DropsWallet.key)
        if target != bath.wallet.count { bath.wallet.add(target - bath.wallet.count, silent: true) }
        ui.sheet = .none; ui.selected = nil
        ui.pendingToast = "+\(JellyCamp.thankYouCoins) JellyCoins. Bye, \(name)!"
        AudioHub.shared.play(.perkSparkle)
        if let a = parkBook.actors.first(where: { CampBook.shared.bodies[$0.id]?.id == id }), let b = a.brain {
            b.autonomy = false
            b.requestNow(.wave)
            ui.leaving = CampUI.Leaving(bodyID: a.id, instance: id, stage: .waving, t: 0)
        } else { ui.finishMove(); park.beginRefresh() }
    }

    /// Per step while a creature is saying goodbye: wave, then walk to the gate, then the white wipe (a timeout at every stage; a refused walk falls back to the wipe).
    func tickCampLeaving(dt: Float) {
        let ui = CampUI.shared
        guard var l = ui.leaving, park.phase == .playing, let a = parkBook.actors.first(where: { $0.id == l.bodyID }), let b = a.brain else { return }
        l.t += dt
        switch l.stage {
        case .waving:
            if (l.t > 1.2 && b.scriptIsNone && b.activity != .waving) || l.t > 5 {
                b.autonomy = false
                b.request(.goTo(b.fixed(SIMD2(CampScenery.gateX, 4.2))))
                l.stage = .walking; l.t = 0
            }
        case .walking:
            let arrived = simd_distance(a.floor, SIMD2(CampScenery.gateX, 4.2)) < 0.9
            if arrived || l.t > 7 { l.stage = .done; ui.leaving = l; ui.finishMove(); park.beginRefresh(); return }
        case .done: return
        }
        ui.leaving = l
    }
}

