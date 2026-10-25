//
//  GameCare+Groom.swift
//  The Groomer: the glue between the trip (Groomer/GroomModels.swift), the Town's row, the Jelbies and the existing bath / grime / perk stores.
//
//  The visit is a cut-scene drawn over the room (GroomChrome): the room never changes. Under the opaque shop front the picked Jelbies are cleaned through the SAME state
//  a finished home Clean leaves (grime.dirt = 0 = no lint, grime.sparkle = 1, the looks re-seeded; Bob's look lives in BathFlow.groomed()), the tier's perks are granted
//  (shine slows the sparkle's fade, so the Jelly Show glow lasts; royal adds tidy and cozy) and they are lined up at the front centre facing the camera. When the shop fades
//  away they cheer: the jump for joy with hearts, then a twirl. Drops are charged once, at the swap (the visit actually starts). A guest friend is not in the roster, so
//  he is never groomed. Persisted: nothing new.
//

import Foundation
import QuartzCore
import simd

extension GameCare {
    func wireGroom() {
        groom.onSwap = { [weak self] in self?.groomSwap() ?? false }
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
        groom.begin(tier)
    }

    private var groomFadeBlocked: Bool {
        race.active || show.active || raceWait != nil || bath.active || focus.isActive || trayOut || dining.phase != .absent || groupActive || arranging || cafe.active || park.active
            || groomBook.actors.contains { $0.brain?.isSleeping == true }
    }

    // MARK: per fixed step

    func tickGroom(_ actors: [JellyActor], dt simDt: Float) {
        groomBook.actors = actors
        // the cut-scene runs on the wall clock (a slow sim must not stretch the 8-9 s visit)
        let now = CACurrentMediaTime()
        let dt = groomBook.lastTick.map { Float(min(max(now - $0, 0), 0.1)) } ?? simDt
        groomBook.lastTick = groom.active ? now : nil
        guard groom.active else { return }
        if !groom.picking { for a in actors { a.brain?.sleepLocked = true } }
        groom.step(dt: dt, blocked: groom.phase == .fadeOut && groomFadeBlocked)
        let book = groomBook
        let picked = groom.picked
        switch groom.phase {
        case .shop, .reveal:
            for a in actors where picked.contains(a.id) { a.brain?.autonomy = false; a.brain?.idleBlocked = true }
        case .cheer:
            for a in actors where picked.contains(a.id) { a.brain?.autonomy = false; a.brain?.idleBlocked = true }
        default: break
        }
        if groom.dryerOn, !groom.dryerCaptioned { groom.dryerCaptioned = true; CaptionCenter.shared.post("Hair dryer humming") }
        guard groom.phase == .reveal || groom.phase == .cheer else { return }
        for (k, a) in actors.filter({ picked.contains($0.id) }).enumerated() {
            guard let b = a.brain else { continue }
            let t = groom.cheerT - Float(k) * GroomTuning.cheerStagger
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

    // MARK: the swap, the reveal, the end

    /// The shop is opaque: charge, clean, perk, line up. False = cannot start (nothing charged).
    private func groomSwap() -> Bool {
        let tier = groom.tier
        let ids = groom.picked.filter { jelly($0) != nil }
        let total = tier.total(count: ids.count)
        guard !ids.isEmpty, bath.wallet.spend(total) else { return false }
        let book = groomBook
        book.charged = total; book.emoted = []; book.twirled = []; book.autonomy = [:]
        AudioHub.shared.play(.buyCoins)
        AudioHub.shared.playClip(GroomTuning.clipBell)
        CaptionCenter.shared.post("Shop bell")
        AudioHub.shared.playClip(GroomTuning.clipAmbience, volume: 0.9)
        CaptionCenter.shared.post("Splashing and scrubbing")
        let n = ids.count
        let base = VoiceCoordinator.comeSpot
        let actors = book.actors.filter { ids.contains($0.id) }
        for id in ids {
            guard let prof = jelly(id) else { continue }
            prof.grime.dirt = 0; prof.grime.sparkle = 1; prof.grime.save()          // the end state of a finished Clean
            prof.refreshLook(force: true)
            if id == 0 { bath.groomed() }
            bathPlug.wet[id] = nil
            for (kind, secs) in tier.perks { prof.perks.grant(kind, duration: secs) }
            needs(for: id).gain(.attention, 0.1)
        }
        for (k, a) in actors.enumerated() {
            guard let brain = a.brain else { continue }
            book.autonomy[a.id] = brain.autonomy
            brain.abortAll(a.sim, a.skinner)
            brain.commandedIdle = nil; brain.commandedDecor = nil; brain.commandedFlip = false
            let x = (Float(k) - Float(n - 1) / 2) * GroomTuning.lineSpacing
            rehome(a, at: brain.fixed(SIMD2(base.x + x, base.y)))
            brain.autonomy = false; brain.idleBlocked = true; brain.restTimer = 0.4
            brain.startTurn(to: 0, sim: a.sim)
        }
        if select.phase != .none { select.cancel() }
        return true
    }

    /// The shop fades away: the reveal sound, the caption; the cheer itself runs in `tickGroom`.
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
        for a in book.actors where groom.picked.contains(a.id) {
            guard let b = a.brain else { continue }
            b.autonomy = book.autonomy[a.id] ?? true
            b.idleBlocked = false
            b.restTimer = 1.5
        }
        book.autonomy = [:]; book.emoted = []; book.twirled = []; book.charged = 0
    }
}
