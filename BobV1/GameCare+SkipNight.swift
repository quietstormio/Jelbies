//
//  GameCare+SkipNight.swift
//  "Sleep until morning": a cosy ~4 s cut-scene that skips the rest of the night on the game clock (never forced; the player can play through the night).
//    0.0-1.4  the room dims, everybody is asked to bed (the usual goodnight / sleep code, with the new sleep fidgets)
//    1.4-2.2  the view fades to a starry night with Zzz; anybody still up is put down while it is hidden
//    2.2      the clock jumps to 7:00 on the next Day; the needs / dirt catch up gently (the time-away curve: never starve); a sleepover guest is told to leave
//    2.2-4.2  the time-lapse runs to sunrise while the stars fade; 3.4 the soft chime and the Jelbies wake (stretches, yawns)
//  A tap skips to the end. Reduce Motion: a plain fade (0.5 in, jump, 0.5 out; no stars, no time-lapse).
//

import Foundation

enum NightSkipTuning {
    static let dimEnd: Float = 1.4, starsEnd: Float = 2.2, jumpAt: Float = 2.2, starsFade: Float = 2.8, wakeAt: Float = 3.4, total: Float = 4.2
    static let lapse: Double = 2.0
    /// Reduce Motion
    static let rmIn: Float = 0.5, rmWake: Float = 0.7, rmTotal: Float = 1.3
    static let dimOpacity: Double = 0.55
}

struct NightSkipState {
    var active = false
    var t: Float = 0
    var reduce = false
    var timeDone = false, woke = false
    /// 0...1 black-navy cover (dim -> full), and 0...1 how much of the starry art shows through it.
    var cover: Double = 0
    var stars: Double = 0
    /// Bumped each time the morning arrives (tests).
    var skips = 0
}

extension GameCare {
    static let nightClip = "night_to_morning_1"
    private var rosterActors: [JellyActor] { raceBook.actors.filter { $0.brain != nil && $0.id < max(jellies.count, 1) } }
    /// Every Jelbie in the roster is lying asleep (the goodnight is done): the moon button then offers the skip more loudly.
    var rosterAllAsleep: Bool { let a = rosterActors; return !a.isEmpty && a.allSatisfy { $0.brain?.isSleeping == true } }
    /// The "Sleep until morning" button is shown: evening on and all night, nothing else going on.
    var nightSkipOffered: Bool { !nightSkip.active && canBedtime && !LaunchGate.shared.visible && DayClock.shared.skipOffered }

    func startNightSkip() {
        guard nightSkipOffered else { return }
        nightSkip = NightSkipState(active: true, t: 0, reduce: A11ySettings.shared.reduceMotion)
        select.cancel()
        if !nightSkip.reduce { bedtimeAll() }
        AudioHub.shared.playClip(Self.nightClip)          // the lullaby that swells into the morning chime and birds (follows the sound settings)
        CaptionCenter.shared.post("Lullaby, then morning birds")
    }

    /// A tap during the cut-scene: finish everything now.
    func skipNightCutscene() {
        guard nightSkip.active else { return }
        AudioHub.shared.stopClip(Self.nightClip, fade: 0.4)
        nightSkip.t = nightSkip.reduce ? NightSkipTuning.rmTotal : NightSkipTuning.total
        tickNightSkip(dt: 0)
    }

    func tickNightSkip(dt: Float) {
        guard nightSkip.active else { return }
        var s = nightSkip
        s.t += dt
        let T = NightSkipTuning.self
        if s.reduce {
            let up = Double(min(s.t / T.rmIn, 1)), down = Double(1 - min(max((s.t - T.rmWake) / (T.rmTotal - T.rmWake), 0), 1))
            s.cover = s.t < T.rmWake ? up : down; s.stars = 0
            if s.t >= T.rmIn, !s.timeDone { nightSkip = s; morningArrives(sweep: false); s = nightSkip }
            if s.t >= T.rmWake, !s.woke { nightSkip = s; wakeForMorning(); s = nightSkip }
            if s.t >= T.rmTotal { s.cover = 0; s.active = false }
        } else {
            let t = s.t
            if t < T.dimEnd { s.cover = T.dimOpacity * Double(t / T.dimEnd); s.stars = 0 }
            else if t < T.starsEnd { let f = Double((t - T.dimEnd) / (T.starsEnd - T.dimEnd)); s.cover = T.dimOpacity + (1 - T.dimOpacity) * f; s.stars = f }
            else if t < T.starsFade { s.cover = 1; s.stars = 1 }
            else { let f = Double(min((t - T.starsFade) / (T.total - T.starsFade), 1)); s.cover = 1 - f * f * (3 - 2 * f); s.stars = max(0, 1 - f * 1.4) }
            if t >= T.starsEnd - 0.2, !s.timeDone { nightSkip = s; putEveryoneDown() ; s = nightSkip }
            if t >= T.jumpAt, !s.timeDone { nightSkip = s; morningArrives(sweep: true); s = nightSkip }
            if t >= T.wakeAt, !s.woke { nightSkip = s; wakeForMorning(); s = nightSkip }
            if t >= T.total { s.cover = 0; s.stars = 0; s.active = false }
        }
        nightSkip = s
    }

    /// Anybody still on their feet lies down at once, while the cover hides it.
    private func putEveryoneDown() {
        for a in rosterActors {
            guard let b = a.brain, !b.isSleeping, b.sleepEnabled else { continue }
            b.abortAll(a.sim, a.skinner); b.pending = nil
            b.sleepInstant(a.sim, a.skinner)
            nightRest.wanted.insert(a.id)
        }
    }

    /// The clock jumps to 7:00 on the next Day, and the night's worth of time catches the needs and dirt up gently.
    private func morningArrives(sweep: Bool) {
        guard !nightSkip.timeDone else { return }
        nightSkip.timeDone = true
        putEveryoneDown()
        DayClock.shared.skipToMorning(duration: NightSkipTuning.lapse, sweep: sweep)
        for j in jellies {
            j.needs.applyAway(seconds: GameClockTuning.skippedNightAway); j.needs.save()
            j.grime.applyAway(seconds: GameClockTuning.skippedNightAway); j.grime.save()
            j.refreshLook(force: false)
        }
        // a sleepover guest leaves with the morning: the usual goodbye
        if let v = guestBook.visit, v.arrived, v.kind == .sleepover { guestBook.endNow(now: Date().timeIntervalSince1970) }
        nightSkip.skips += 1
    }

    /// The soft chime, and everybody wakes with the existing stretches and yawns.
    private func wakeForMorning() {
        guard !nightSkip.woke else { return }
        nightSkip.woke = true
        nightRest.wanted.removeAll(); nightRest.dayOnce.removeAll(); nightRest.nightWoken.removeAll()
        for a in rosterActors { if let b = a.brain, b.isSleeping { b.commandedGoodnight = false; b.sleepWake(groggy: true) } }
        noteInteraction()
    }
}
