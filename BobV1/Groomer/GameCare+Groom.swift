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
        if isBedtimeHours { return "The Jelly Spa is closed at night. Come back in the morning!" }
        if tripActive || raceBusy || raceBook.returner != nil { return "Finish this trip first." }
        if let b = cafeBlocker(), b != .noDrops { return b.message }
        if bath.wallet.count < GroomTier.cheapest { return "The Jelly Spa starts at \(GroomTier.cheapest) Drops per Jelbie. Win a race first!" }
        return nil
    }

    /// The Town's Groomer row: blocked = a friendly toast; else the picker (who goes, which tier).
    func requestGroom() {
        if let why = groomBlocker() {
            groom.say(why)
            AudioHub.shared.play(.notEnough)
            return
        }
        select.cancel(); queued.removeAll(); callRunning = false
        voice.cancel()
        groom.openPicker(all: Array(jellies.indices))
    }

    /// The picker's tier button. Short of Drops: the café's line on the card and nothing is charged. Else the fade starts (the Drops go at the swap).
    func startGroom(_ tier: GroomTier) {
        guard groom.picking, !groom.picked.isEmpty else { return }
        if let why = GroomTier.refusal(total: tier.total(count: groom.picked.count), wallet: bath.wallet.count) {
            groom.refusal = why
            AudioHub.shared.play(.notEnough)
            return
        }
        select.cancel()
        let who = groom.picked
        groom.closePicker()
        let go = { [weak self] in self?.groom.begin(tier) ?? () }
        if outingGate(who, again: go) { return }          // the chosen Jelbies run out of the room first (GameCare+Outing.swift)
        go()
    }

    private var groomFadeBlocked: Bool {
        race.active || show.active || raceWait != nil || bath.active || focus.isActive || trayOut || dining.phase != .absent || groupActive || arranging || cafe.active || park.active
            || groomBook.actors.contains { $0.brain?.isSleeping == true }
    }

    // MARK: per fixed step

    /// Not drawn: everybody while the Jelbies are "inside" the shop, and whoever has not stepped out of the door yet.
    func groomHides(_ id: Int) -> Bool { groom.inScene && !groomBook.out.contains(id) }

    func tickGroom(_ actors: [JellyActor], dt simDt: Float) {
        groomBook.actors = actors
        tickOutExit(actors, dt: simDt)
        // the cut-scene runs on the wall clock (a slow sim must not stretch the 8-9 s visit)
        let now = CACurrentMediaTime()
        let dt = groomBook.lastTick.map { Float(min(max(now - $0, 0), 0.1)) } ?? simDt
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
        // the door opens, then they hop out into the street and run to the front
        if book.out.isEmpty, groom.cheerT >= GroomTuning.doorOpen * 0.6 {
            for (k, a) in mine.enumerated() {
                guard let b = a.brain else { continue }
                book.out.insert(a.id)
                rehome(a, at: b.fixed(GroomScenery.doorStep + SIMD2(Float(k % 2) * 0.3 - 0.15, 0)))
                b.autonomy = false; b.idleBlocked = true
                b.startTurn(to: 0, sim: a.sim)
                b.face(.excited, hold: 3)
                b.postEvent(.joyJump)
                touchPlay?.spawnHeart(now: CACurrentMediaTime())
                let spot = GroomScenery.lineUp(index: k, of: mine.count)
                b.requestNow(.goTo(b.fixed(spot)))
            }
            AudioHub.shared.play(.cheerSmall, volume: 0.7)
            return
        }
        for (k, a) in mine.enumerated() {
            guard let b = a.brain else { continue }
            let t = groom.cheerT - GroomTuning.doorOpen - GroomTuning.walkOut - Float(k) * GroomTuning.cheerStagger
            let idle = b.commandedIdle == nil && b.idleState.kind == nil && { if case .none = b.script { return true } else { return false } }()
            if t >= 0, !book.emoted.contains(a.id) {
                book.emoted.insert(a.id)
                b.abortAll(a.sim, a.skinner)
                b.commandedIdle = .joy
                b.blushBump(hold: 3, peak: 0.8)
                b.face(.excited, hold: 3)
                b.postEvent(.joyJump)
                touchPlay?.spawnHeart(now: CACurrentMediaTime())
                AudioHub.shared.chirp(jelly: a.id, .happy)
            } else if t >= GroomTuning.twirlAt, !book.twirled.contains(a.id), idle {
                book.twirled.insert(a.id)
                b.commandedIdle = .tail
                touchPlay?.spawnHeart(now: CACurrentMediaTime())
                if k == 0 { AudioHub.shared.play(.cheerSmall, volume: 0.8) }
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
        book.charged = total; book.emoted = []; book.twirled = []; book.autonomy = [:]; book.homes = [:]; book.out = []
        AudioHub.shared.play(.buyCoins)
        AudioHub.shared.playClip(GroomTuning.clipBell)
        CaptionCenter.shared.post("Shop bell")
        AudioHub.shared.playClip(GroomTuning.clipAmbience, volume: 0.9)
        CaptionCenter.shared.post("Splashing and scrubbing")
        for id in ids {
            guard let prof = jelly(id) else { continue }
            prof.grime.dirt = 0; prof.grime.sparkle = 1; prof.grime.save()          // the end state of a finished Clean
            prof.refreshLook(force: true)
            if id == 0 { bath.groomed() }
            bathPlug.wet[id] = nil
            for (kind, secs) in tier.perks { prof.perks.grant(kind, duration: secs) }
            needs(for: id).gain(.attention, 0.1)
        }
        for a in book.actors {
            guard let brain = a.brain else { continue }
            book.autonomy[a.id] = brain.autonomy; book.homes[a.id] = a.floor
            brain.abortAll(a.sim, a.skinner)
            brain.commandedIdle = nil; brain.commandedDecor = nil; brain.commandedFlip = false
            brain.autonomy = false; brain.idleBlocked = true
        }
        RoomLayout.apply(RoomCatalog.groom)
        GameCamera.configureGroom()
        syncDecor()
        if select.phase != .none { select.cancel() }
        return true
    }

    private func groomToHome() {
        let book = groomBook
        book.out = []
        RoomLayout.apply(RoomCatalog.def(store.currentRoom))
        GameCamera.endGroom(count: max(jellies.count, 1))
        if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
            for a in book.actors where a.sim.arenaRadius.isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
        }
        syncDecor()
        let ids = book.actors.filter { groom.picked.contains($0.id) }.map(\.id)
        let base = VoiceCoordinator.comeSpot
        for a in book.actors {
            guard let brain = a.brain else { continue }
            if let k = ids.firstIndex(of: a.id) {          // the groomed ones are lined up at the front centre, facing the camera
                let x = (Float(k) - Float(ids.count - 1) / 2) * GroomTuning.lineSpacing
                rehome(a, at: brain.fixed(SIMD2(base.x + x, base.y)))
                brain.startTurn(to: 0, sim: a.sim)
            } else if let h = book.homes[a.id] {
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
        A11yAnnounce.say(groom.tier.banner)
    }

    /// Back to normal life.
    private func groomEnd() {
        AudioHub.shared.stopClip(GroomTuning.clipAmbience, fade: 0.2)
        let book = groomBook
        for a in book.actors {
            guard let b = a.brain, book.autonomy[a.id] != nil else { continue }
            b.autonomy = book.autonomy[a.id] ?? true
            b.idleBlocked = false
            b.restTimer = 1.5
        }
        book.autonomy = [:]; book.homes = [:]; book.emoted = []; book.twirled = []; book.out = []; book.charged = 0
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
