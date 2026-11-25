//
//  GameCare+Groom.swift
//  The Groomer: the glue between the trip (Groomer/GroomModels.swift), the Town's row, the Jelbies and the existing bath / grime / perk stores.
//
//  The visit: the chosen Jelbies run out of the room (GameCare+Outing.swift), a white fade swaps the room for the 3D street outside the Jelly Spa (GroomRoom.swift;
//  nobody is drawn: they are inside). Under the white the picked Jelbies are cleaned through the SAME state a finished home Clean leaves (grime.dirt = 0 = no lint,
//  grime.sparkle = 1, the looks re-seeded; Bob's look lives in BathFlow.groomed()) and the tier's perks are granted (shine slows the sparkle's fade, so the Jelly Show glow
//  lasts; royal adds tidy and cozy). At the end the door opens and they hop out into the street, cheer (jump for joy with hearts, then a twirl), and a white fade takes them
//  home, lined up at the front centre. Drops are charged once, at the first swap. A guest friend is not in the roster, so he is never groomed. Persisted: nothing new.
//

import Foundation
import QuartzCore
import simd

extension GameCare {
    func wireGroom() {
        groom.onSwap = { [weak self] in self?.groomSwap($0) ?? false }
        groom.onReveal = { [weak self] in self?.groomReveal() }
        groom.onEnd = { [weak self] in self?.groomEnd() }
    }

    // MARK: blockers and the request

    /// Why the Jelly Spa cannot be entered now (the friendly line); nil = it can.
    func groomBlocker() -> String? {
        if groom.active { return "Already at the Jelly Spa!" }
        if let why = groomGuestBlocker { return why }          // a friend is coming or here: the Jelly Wash is closed
        if isBedtimeHours { return "The Jelly Spa is closed at night. Come back in the morning!" }
        if tripActive || raceBusy { return "Finish this trip first." }
        if let b = cafeBlocker(), b != .noDrops { return b.message }
        if bath.wallet.count < GroomTier.cheapest { return "The Jelly Spa starts at \(GroomTier.cheapest) JellyCoins per Jelmiko. Win a race first!" }
        return nil
    }

    /// The Town's Groomer row: blocked = a friendly toast; else the picker (who goes, which tier).
    func requestGroom() {
        if let why = groomBlocker() {
            groom.say(why)
            AudioHub.shared.play(.notEnough)
            return
        }
        select.cancel(); cutWelcomeHome(); queued.removeAll(); callRunning = false
        voice.cancel()
        groom.openPicker(all: Array(jellies.indices))
    }

    /// The picker's tier button. Short of Drops: the café's line on the card and nothing is charged. Else the fade starts (the Drops go at the swap).
    func startGroom(_ tier: GroomTier) {
        guard groom.picking, !groom.picked.isEmpty else { return }
        if let why = groomGuestBlocker { groom.closePicker(); groom.say(why); AudioHub.shared.play(.notEnough); return }          // (a friend was invited while the picker was open)
        if let why = GroomTier.refusal(total: tier.total(count: groom.picked.count), wallet: bath.wallet.count) {
            groom.refusal = why
            AudioHub.shared.play(.notEnough)
            return
        }
        select.cancel()
        let who = groom.picked
        groom.closePicker()
        let go = { [weak self] in self?.groom.begin(tier) ?? () }
        let start = { [weak self] in
            guard let self else { return }
            if self.outingGate(who, again: go) { return }          // the chosen Jelbies run out of the room first (GameCare+Outing.swift)
            go()
        }
        if wakeForTrip(who, then: start) { return }          // a sleeper gets the short wake first (park-wake-r1)
        start()
    }

    private var groomFadeBlocked: Bool {
        race.active || show.active || raceWait != nil || showBook.wait != nil || bath.active || focus.isActive || trayOut || dining.phase != .absent || groupActive || arranging || cafe.active || park.active
            || groomBook.actors.contains { groom.picked.contains($0.id) && $0.brain?.isSleeping == true }          // (a sleeper who stays home does not hold the fade)
    }

    // MARK: per fixed step

    /// Not drawn: everybody while the Jelbies are "inside" the shop, and whoever has not stepped out of the door yet.
    func groomHides(_ id: Int) -> Bool { groom.inScene && !groomBook.out.contains(id) }

    #if targetEnvironment(simulator)
    nonisolated(unsafe) static var startGroomFrames = UserDefaults.standard.integer(forKey: "StartGroom") != 0 ? 1 : 0
    #endif

    func tickGroom(_ actors: [JellyActor], dt simDt: Float) {
        #if targetEnvironment(simulator)
        tripArriveTick("groom", actors, dt: simDt)          // (park-arrive-r2 capture aid: Park/ParkSlideProbe.swift)
        if Self.startGroomFrames > 0, !groom.active {          // capture aid: `-StartGroom N` takes the first N Jelbies to the Jelly Spa (Quick Splash, coins topped up) once the room is up
            Self.startGroomFrames += 1
            if Self.startGroomFrames > 120 { Self.startGroomFrames = 0; if bath.wallet.count < 20 { bath.wallet.add(40, silent: true) }; groom.openPicker(all: Array(0..<max(1, min(UserDefaults.standard.integer(forKey: "StartGroom"), jellies.count)))); startGroom(.quick) }
        }
        #endif
        groomBook.actors = actors
        tickOutExit(actors, dt: simDt)
        // the cut-scene runs on the wall clock (a slow sim must not stretch the 8-9 s visit)
        let now = CACurrentMediaTime()
        let dt = groomBook.fixedDt ?? groomBook.lastTick.map { Float(min(max(now - $0, 0), 0.1)) } ?? simDt          // (`fixedDt`: tests drive the visit on the sim clock)
        groomBook.lastTick = groom.active ? now : nil
        guard groom.active else { return }
        if !groom.picking { for a in actors { a.brain?.sleepLocked = true } }
        groom.step(dt: dt, blocked: groom.phase == .fadeOut && groomFadeBlocked)
        let book = groomBook
        let picked = groom.picked
        if groom.inScene || groom.phase == .leaveIn { for a in actors { a.brain?.autonomy = false; a.brain?.idleBlocked = true } }
        if groom.dryerOn, !groom.dryerCaptioned { groom.dryerCaptioned = true; CaptionCenter.shared.post("Hair dryer humming") }
        guard groom.phase == .reveal else { return }
        let mine = actors.filter { picked.contains($0.id) }
        // the door opens, then they come out ONE AT A TIME (spaced GroomTuning.exitSpacing, and the next only once the last is a body-gap clear of the door),
        // each running to its own spot in the line-up, so the paths fan out and never overlap
        let openAt = GroomTuning.doorOpen + GroomTuning.doorSettle          // (door round: wide open AND still for a beat before the first walks into the doorway) // (no-clip-r1: the leaf is fully open before the first steps out; at 60% it still swept through the spot he stepped onto)
        if RoomLayout.dynamicBoxes.isEmpty { RoomLayout.dynamicBoxes = [GroomScenery.doorLeafBox] }
        if groom.cheerT >= openAt, book.out.count < mine.count {
            let k = book.out.count
            let a = mine[k]
            let prevClear: Bool = {
                guard k > 0, let pb = mine[k - 1].brain else { return true }
                let away = simd_length(GameCare.floorPos(pb, mine[k - 1].sim) - GroomScenery.doorStep)
                if let t0 = book.outAt[mine[k - 1].id] {
                    let waited = groom.cheerT - t0
                    if waited >= GroomTuning.exitPatience * 3 { return true }          // (never wait forever on a stalled one)
                    if waited >= GroomTuning.exitPatience, away >= 2.2 { return true }          // (a slow one: the next only once two bodies fit side by side)
                }
                if !book.laneDone.contains(mine[k - 1].id) { return false }          // (door round: the next one starts only when the last has walked clear of the doorway lane: with him still in it the peer steering swerved the new one sideways, into the frame / the planter)
                return away >= 2.6          // (no-clip-r1: never two in the doorway; 2.0 so the next one's first steps do not cross the last one's route to the line-up)
            }()
            if let b = a.brain, groom.cheerT >= openAt + Float(k) * GroomTuning.exitSpacing, prevClear {
                book.out.insert(a.id); book.outAt[a.id] = groom.cheerT
                rehome(a, at: b.fixed(GroomScenery.insideSpot))          // (door round: he starts INSIDE the shop, hidden by the wall, and walks out through the open doorway)
                b.autonomy = false; b.idleBlocked = true
                b.startTurn(to: 0, sim: a.sim)
                b.face(.excited, hold: 3)
                b.requestNow(.goTo(b.fixed(GroomScenery.laneOut)))          // (first the doorway's centre line, then his own street spot, see below)
                if k == 0 { AudioHub.shared.playClip(GroomTuning.clipHarp, volume: 0.6) }          // one soft harp flourish when they first walk out (no crowd "yay")
            }
        }
        for (k, a) in mine.enumerated() {
            guard let b = a.brain, let outAt = book.outAt[a.id] else { continue }
            // the doorway: arms forward while he is in or near the frame (the opening is 1.40, his belly 1.17, the arms stick out another 0.4); on the pavement he is sent on to his spot
            let fy = GameCare.floorPos(b, a.sim).y, zf = GroomScenery.frontZ
            let inDoor = fy > zf - 1.0 && fy < zf + 2.5 && !book.laneDone.contains(a.id)
            if inDoor { b.armDirW = 1; b.armDirEl = [0.35, 0.35]; b.armDirSa = [1.25, 1.25]; b.armDirOut = 0 }
            else if b.armDirW > 0, book.arrivedAt[a.id] == nil { b.armDirW = 0; b.armDirOut = 0 }
            if !book.laneDone.contains(a.id), fy > zf + 2.5 || groom.cheerT - outAt > 6 {
                book.laneDone.insert(a.id)
                b.postEvent(.joyJump)
                b.requestNow(.goTo(b.fixed(GroomScenery.lineUp(index: k, of: mine.count))))
            }
            // the cheer starts when he has ARRIVED at his spot (a cheer's abort must not stop the walk-out half way and leave him in the next one's way)
            if book.arrivedAt[a.id] == nil {
                let spot = b.fixed(GroomScenery.lineUp(index: k, of: mine.count))
                if simd_length(GameCare.floorPos(b, a.sim) - spot) < 0.4 || groom.cheerT - outAt > GroomTuning.walkOut + 2.6 { book.arrivedAt[a.id] = groom.cheerT }
            }
            guard let arrived = book.arrivedAt[a.id] else { continue }
            let t = groom.cheerT - arrived
            if t >= 0, !book.emoted.contains(a.id) {
                book.emoted.insert(a.id)
                b.abortAll(a.sim, a.skinner)
                b.commandedIdle = book.emote[a.id] ?? .joy          // (a DIFFERENT happy emote for each, assigned when the door opens)
                b.blushBump(hold: 3, peak: 0.8)
                b.face(.excited, hold: 3)
                b.postEvent(.joyJump)
                touchPlay?.spawnHeart(now: CACurrentMediaTime())
                AudioHub.shared.chirp(jelly: a.id, .happy)
            }
        }
    }

    // MARK: the swaps, the reveal, the end

    /// The white is opaque: to the street (charge, clean, perk) or back home (line up in the room).
    private func groomSwap(_ dest: GroomTrip.Dest) -> Bool {
        switch dest {
        case .shop: return groomToShop()
        case .home: groomToHome(); return true
        }
    }

    private func groomToShop() -> Bool {
        let tier = groom.tier
        let ids = groom.picked.filter { jelly($0) != nil }
        let total = tier.total(count: ids.count)
        guard !ids.isEmpty, bath.wallet.spend(total) else { return false }
        let book = groomBook
        book.charged = total; book.stayedAsleep = []; book.emoted = []; book.twirled = []; book.autonomy = [:]; book.homes = [:]; book.out = []; book.laneDone = []; book.outAt = [:]; book.arrivedAt = [:]; book.emote = [:]
        AudioHub.shared.playClip(GroomTuning.clipBell)
        CaptionCenter.shared.post("Shop bell")
        AudioHub.shared.playClip(GroomTuning.clipAmbience, volume: 0.9)
        CaptionCenter.shared.post("Splashing and scrubbing")
        for id in ids {
            guard let prof = jelly(id) else { continue }
            prof.grime.dirt = 0; prof.grime.sparkle = 1; prof.grime.stampWash(WashQuality.tier(tier))          // the end state of a finished Clean, and how well he was washed (the Spa is the best: WashQuality.swift)
            prof.refreshLook(force: true)
            if id == 0 { bath.groomed() }
            bathPlug.wet[id] = nil
            for (kind, secs) in tier.perks { prof.perks.grant(kind, duration: secs) }
            needs(for: id).gain(.attention, 0.1)
            bondEarn(.care, slot: id, story: ["care": "groom"])          // (the relationship: a groom)
        }
        for a in book.actors {
            guard let brain = a.brain else { continue }
            book.autonomy[a.id] = autonomySnapshot(a.id, brain); book.homes[a.id] = a.floor
            if brain.isSleeping { book.stayedAsleep.insert(a.id); continue }          // a sleeper who stays home stays exactly as he is: not woken, not moved
            brain.abortAll(a.sim, a.skinner)
            brain.commandedIdle = nil; brain.commandedDecor = nil; brain.commandedFlip = false
            brain.autonomy = false; brain.idleBlocked = true
        }
        RoomLayout.apply(RoomCatalog.groom)
        GameCamera.configureGroom()
        #if targetEnvironment(simulator)
        tripArriveStart("groom")
        #endif
        for a in book.actors where a.sim.arenaRadius.isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }          // (the room's small arena would pin the door step at z = -2.6: he could never leave the door)
        // everybody is inside the shop (not drawn): wait off to the right, so the room's spots do not become bodies in the street that block the door's walk-out (the peer steering sees them)
        for (i, a) in book.actors.enumerated() { if let b = a.brain, !book.stayedAsleep.contains(a.id) { rehome(a, at: b.fixed(SIMD2(GroomTuning.waitX, GroomScenery.laneOut.y - 0.1 + 1.4 * Float(i % 4)))) } }
        syncDecor()
        if select.phase != .none { select.cancel() }
        return true
    }

    private func groomToHome() {
        let book = groomBook
        book.out = []; book.laneDone = []; book.outAt = [:]; book.arrivedAt = [:]; book.emote = [:]
        RoomLayout.dynamicBoxes = []          // (the door leaf's)
        RoomLayout.apply(RoomCatalog.def(store.currentRoom))
        GameCamera.endGroom(count: max(jellies.count, 1))
        if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
            for a in book.actors where a.sim.arenaRadius.isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
        }
        syncDecor()
        let ids = book.actors.filter { groom.picked.contains($0.id) }.map(\.id)
        tripReturned(ids)
        let base = VoiceCoordinator.comeSpot
        for a in book.actors {
            guard let brain = a.brain, !book.stayedAsleep.contains(a.id) else { continue }          // (a sleeper who stayed home was never moved)
            if let k = ids.firstIndex(of: a.id) {          // the groomed ones are lined up at the front centre, facing the camera
                let x = (Float(k) - Float(ids.count - 1) / 2) * GroomTuning.lineSpacing
                rehome(a, at: brain.fixed(SIMD2(base.x + x, base.y)))
                brain.startTurn(to: 0, sim: a.sim)
            } else if let h = book.homes[a.id] {
                if brain.isSleeping { rehomeAsleep(a, at: brain.fixed(h)); continue }          // (dozed off during the trip: back on the home floor, still asleep: not stood up)
                rehome(a, at: brain.fixed(h))
            }
            brain.restTimer = 0.4
        }
    }

    /// The door opens: the reveal sound, the caption; the hop out and the cheer run in `tickGroom`.
    private func groomReveal() {
        AudioHub.shared.stopClip(GroomTuning.clipAmbience, fade: 0.3)
        AudioHub.shared.playClip(GroomTuning.clipReveal)
        CaptionCenter.shared.post("Sparkle!")
        groom.slogan = SpaSlogans.next()
        var g = SystemRandomNumberGenerator()
        let set = SpaExitEmotes.forced ?? SpaExitEmotes.assign(count: groom.picked.count, avoiding: SpaExitEmotes.lastSet, using: &g)
        SpaExitEmotes.lastSet = set
        for (k, id) in groom.picked.enumerated() where k < set.count { groomBook.emote[id] = set[k] }
        A11yAnnounce.say(groom.slogan)
    }

    /// Back to normal life.
    private func groomEnd() {
        AudioHub.shared.stopClip(GroomTuning.clipAmbience, fade: 0.2)
        let book = groomBook
        for a in book.actors {
            guard let b = a.brain, book.autonomy[a.id] != nil else { continue }
            if b.isSleeping { b.autonomy = book.autonomy[a.id] ?? true; b.idleBlocked = false; continue }          // (a sleeper who stayed home, or one who dozed off during the trip: not woken)
            b.abortAll(a.sim, a.skinner)          // (a longer exit emote must not hold him back from roaming)
            b.autonomy = book.autonomy[a.id] ?? true
            b.idleBlocked = false
            b.restTimer = 1.5
        }
        book.autonomy = [:]; book.homes = [:]; book.stayedAsleep = []; book.emoted = []; book.twirled = []; book.out = []; book.laneDone = []; book.outAt = [:]; book.arrivedAt = [:]; book.emote = [:]; book.charged = 0
    }

    // MARK: the street's animated bits

    /// Per frame while the street is up: the door, the window glow, bubbles, steam, sparkles (one small mesh, drawn as the animating decor).
    func refreshGroomFx(_ room: RoomRenderer) -> Bool {
        let book = groomBook
        guard groom.inScene else {
            if book.fxShown { room.setDecorActive(RoomMesh()); book.fxShown = false }
            return false
        }
        var s = GroomScenery.FxState()
        s.time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1000))
        s.shopT = groom.shopT; s.phase = groom.phase; s.doorOpen = groom.doorOpen; s.cheerT = groom.cheerT
        s.dryerOn = groom.dryerOn; s.reduce = A11ySettings.shared.reduceMotion
        room.setDecorActive(GroomScenery.fx(s))
        book.fxShown = true
        return true
    }
}
