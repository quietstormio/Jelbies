//
//  GameCare+Guest.swift
//  A friend over at home (Park/GuestBook.swift holds the invitation and the rules). The guest's body is a park visitor's body (the stage's `parkActors`, the same
//  renderer slot after the roster's, so the room draws up to four), ticked by the same brain as everybody (variety, socials, the friendly socials, greetings, sleep).
//    arrive    the invitation is answered the next time the player is home and the room is free: he comes in at the back edge, walks to the front (the adopted
//              Jelbie's come-to-front walk, a wave to the camera at the end), the others hop and trot over
//    evening   (2026-11-05) he only comes from 17:00 on (GuestRules.canArrive); an invitation made earlier waits for the evening, the Jelly Wash is closed meanwhile
//    play      the guest roams and plays with the Jelbies like a housemate (friendship grows a little at home too)
//    overnight he goes to bed when the Jelbies do (the usual "goodnight": beside a sleeper, the pair-sleep arms / lean, the sleep fidgets) and wakes with the morning
//    goodbye   at the end he wakes if asleep, waves to the camera, waves again at the door and walks out
//    away      the visit lives on the wall clock: closed for the night, the app is back with him asleep (instantly, like the Jelbies); back after the end within the
//              grace he is waved off; back later, "<name> went home after the sleepover". An outing (race, café, show, park) sends the body away and he walks in again after.
//  He is not owned: no feeding, no clean-up, no wardrobe; a tap on him opens his card (name, hearts with each Jelbie, Say goodbye).
//

import Foundation
import QuartzCore
import simd

extension GameCare {
    // MARK: who can be asked

    /// The visitors the player is friends with (Friend level or better with at least one of the Jelbies), best friends first.
    func friendsToInvite() -> [ParkVisitor] {
        let chars = jellies.map(\.character)
        return parkBook.visitors
            .filter { $0.mergedInto == nil && $0.introduced && $0.bestLevel(among: chars) >= .friend }
            .sorted { a, b in
                let la = a.bestLevel(among: chars), lb = b.bestLevel(among: chars)
                if la != lb { return la > lb }
                let c = a.name.localizedCaseInsensitiveCompare(b.name)
                return c != .orderedSame ? c == .orderedAscending : a.id < b.id
            }
    }
    /// Why the Jelly Wash is closed while a friend is coming or here ("Not while Zippy is visiting"); nil = no friend is over.
    var groomGuestBlocker: String? {
        guard let cur = guestBook.visit else { return nil }
        return "Not while \(parkBook.visitor(cur.visitor)?.name ?? "your friend") is visiting"
    }
    /// "Zippy will come over this evening" / "Zippy is on the way" / "Zippy is visiting": the Friends screen's status line.
    func guestStatusText(hour hourIn: Double? = nil) -> String? {
        let hour = hourIn ?? DayClock.shared.hour
        guard let cur = guestBook.visit, let v = parkBook.visitor(cur.visitor) else { return nil }
        if cur.arrived { return "\(v.name) is visiting" }
        return GuestRules.canArrive(hour: hour) ? "\(v.name) is on the way" : "\(v.name) will come over \(GuestRules.when(hour: hour))"
    }
    func canInvite(_ vid: Int) -> Bool {
        guard guestBook.visit == nil, let v = parkBook.visitor(vid) else { return false }
        return v.bestLevel(among: jellies.map(\.character)) >= .friend
    }

    /// Ask a friend over. True = the invitation is kept (he comes the next time the player is home and the room is free).
    @discardableResult
    func inviteFriend(_ vid: Int, kind: GuestVisit.Kind = .sleepover) -> Bool {
        guard let v = parkBook.visitor(vid) else { return false }
        if let cur = guestBook.visit {
            let other = parkBook.visitor(cur.visitor)?.name ?? "A friend"
            park.say(cur.arrived ? "\(other) is visiting right now." : "\(other) is already on the way.")
            AudioHub.shared.play(.notEnough)
            return false
        }
        guard canInvite(vid) else { return false }
        guestBook.invite(visitor: vid, kind: kind, now: Date().timeIntervalSince1970)
        park.card = nil
        AudioHub.shared.play(.uiconfirm)
        AudioHub.shared.chirp(jelly: 0, .happy)
        let hour = DayClock.shared.hour
        let when = GuestRules.when(hour: hour)
        park.say(park.inScene ? "\(v.name) will come over \(when) when you get home!" : "\(v.name) will come over \(when)!")
        return true
    }
    func cancelInvite() {
        guard let v = guestBook.visit, !v.arrived else { return }
        let n = parkBook.visitor(v.visitor)?.name ?? "Your friend"
        guestBook.cancelInvite()
        park.say("\(n) will come another day.")
    }

    // MARK: the guest's card (a tap on him)

    func guestTapped(_ bodyID: Int) {
        guard guestBook.actor?.id == bodyID else { return }
        AudioHub.shared.uiTap()
        guestBook.card.toggle()
        if let b = guestBook.actor?.brain { b.face(.happy, hold: 1.5) }
    }
    /// "Say goodbye": the visit is over now (he wakes if asleep, waves and walks out).
    func guestSayGoodbye() {
        guestBook.card = false
        guestBook.endNow(now: Date().timeIntervalSince1970)
    }

    // MARK: per fixed step

    /// The room is free for the body to be there: no outing, no veil, no curtain.
    private var guestOuting: Bool {
        if race.active || raceWait != nil || show.active || cafe.active || volley.active || volleyWork.wait != nil || groom.active { return true }          // (the beach: the guest's body is put away, 4 bodies at most; he walks in again after)
        if park.active, !park.picking, !(park.phase == .goOut && park.wipe < 0.8) { return true }
        return false
    }
    /// A quiet moment for the knock: nothing is being fed, washed or arranged and no close-up is open.
    private var guestRoomQuiet: Bool {
        !LaunchGate.shared.visible && !greetBlocked && !bath.active && !arranging && !park.active && !raceBusy && !select.isSelecting && !groom.picking
    }

    func tickGuest(_ actors: [JellyActor], dt: Float) {
        let g = guestBook
        if g.visit == nil, g.actor == nil { return }
        guard let visit = g.visit else { guestRemove(); return }
        guard let v = parkBook.visitor(visit.visitor) else { guestRemove(); g.finish(); return }
        if v.id != visit.visitor { g.repoint(to: v.id) }          // (a merged duplicate record: the visit follows the survivor)
        let now = Date().timeIntervalSince1970
        let gameNow = DayClock.shared.gameNow

        // the game clock (the wall clock when it follows the phone) decides whether the visit is over, also across a closed app
        switch GuestRules.verdict(visit, now: now, gameNow: gameNow) {
        case .dropped: guestRemove(); g.finish(); return
        case .wentHome where g.actor == nil && g.phase != .leaving:
            guestRemove(); g.finish()
            if !LaunchGate.shared.visible { park.say(GuestRules.note(v.name, visit.kind)) } else { g.pendingNote = GuestRules.note(v.name, visit.kind) }
            return
        default: break
        }
        if let n = g.pendingNote, !LaunchGate.shared.visible { g.pendingNote = nil; park.say(n) }

        // an outing sends the body away (the visit goes on)
        if guestOuting {
            if g.arrival.active || g.arrivalCard != .hidden { guestArrivalCancel() }
            if g.actor != nil { guestRemove(); g.phase = .away }
            return
        }
        guard actors.count == max(jellies.count, 1), actors.allSatisfy({ $0.brain != nil }) else { return }

        if g.actor == nil {
            g.phase = .away
            if g.arrival.active { guestArrivalStep(actors, v, visit, dt: dt); return }          // the arrival moment (Park/GuestArrival.swift): the body is made behind the card
            guard guestRoomQuiet, parkBook.spawn != nil else { g.knockT = 0; return }
            if !visit.arrived, !GuestRules.canArrive(hour: DayClock.shared.hour) { g.knockT = 0; return }          // he only comes in the evening
            g.knockT += dt
            g.spawnFailT = max(0, g.spawnFailT - dt)
            let overdue = GuestRules.isOver(visit, now: now, gameNow: gameNow)
            guard g.knockT >= GuestTuning.knock, g.spawnFailT <= 0 else { return }
            if !visit.arrived, guestWalksIn(actors, visit, overdue: overdue), guestArrivalBegin() { return }          // the first arrival: the doorbell, the card, the run-in
            guestSpawn(actors, v, visit, overdue: overdue)
            return
        }

        guard let a = g.actor, let b = a.brain else { return }
        g.phaseT += dt
        visitorLook(a, v, dt: dt, sleepLocked: false)
        guestFriends(actors, a, v, dt: dt)
        if g.arrival.active || g.hugWait != nil { guestArrivalStep(actors, v, visit, dt: dt); return }          // the arrival moment drives him until it is done

        // the end of the visit
        if g.phase != .leaving, GuestRules.isOver(visit, now: now, gameNow: gameNow) { guestBeginLeaving(actors, a, v) }
        switch g.phase {
        case .walkingIn: guestArriving(actors, a, b, v, dt: dt)
        case .here: guestAtPlay(actors, a, b, visit, dt: dt)
        case .leaving: guestLeaving(actors, a, b, v, visit, dt: dt)
        case .away: break
        }
    }

    // MARK: body

    private func guestRemove() {
        let g = guestBook
        if let a = g.actor { visitorPutAway(a); parkBook.clear?() }
        g.actor = nil
        g.card = false
    }

    /// True = he comes in through the door (not already inside because the visit is over / the Jelbies are asleep).
    func guestWalksIn(_ actors: [JellyActor], _ visit: GuestVisit, overdue: Bool) -> Bool {
        let rosterAsleep = actors.contains { $0.brain?.isSleeping == true }
        let sleepingIn = visit.arrived && !overdue && rosterAsleep && actors.first?.brain?.bedtimeHours == true
        return !(overdue || sleepingIn)
    }

    /// `arrival`: the arrival moment's body (Park/GuestArrival.swift): made off the left edge of the room, held still until the run-in.
    func guestSpawn(_ actors: [JellyActor], _ v: ParkVisitor, _ visit: GuestVisit, overdue: Bool, arrival: Bool = false) {
        let g = guestBook
        let now = Date().timeIntervalSince1970
        let rosterAsleep = actors.contains { $0.brain?.isSleeping == true }
        let sleepingIn = visit.arrived && !overdue && rosterAsleep && actors.first?.brain?.bedtimeHours == true
        var spot: SIMD2<Float> = (overdue || sleepingIn) ? guestSpotNear(actors) : GuestTuning.door
        if arrival { let t = guestSpotNear(actors); g.arrivalTarget = t; spot = guestArrivalEntry(toward: t) }
        guard let a = (parkBook.spawn?([v], [spot]) ?? []).first(where: { $0.id == actors.count }), let b = a.brain else { g.spawnFailT = 3; return }
        g.actor = a
        g.greeted = false; g.settleT = 0; g.stage = 0; g.phaseT = 0; g.bedT = 1.5; g.wakeT = 0; g.friendSession = [:]
        b.sleepLocked = false
        b.idleMood = .happy
        if !visit.arrived {
            g.markArrived(now: now, sleepoverSeconds: DayClock.shared.secondsToSleepoverEnd, endsGame: DayClock.shared.sleepoverEndGame)
            if !arrival { park.say("\(v.name) came over for the evening!") }
        }
        if arrival {
            b.autonomy = false
            g.phase = .walkingIn
            return
        }
        if overdue {          // the app is back just after the end: he is still here, ready to go home
            g.phase = .here
            rehome(a, at: spot)
            return
        }
        if sleepingIn {
            g.phase = .here
            b.abortAll(a.sim, a.skinner)
            b.sleepInstant(a.sim, a.skinner)
            return
        }
        g.phase = .walkingIn
        rehome(a, at: spot)
        b.requestNow(.come(to: VoiceCoordinator.comeSpot))          // the adopted Jelbie's walk to the front (and a wave to the camera at the end)
        AudioHub.shared.chirp(jelly: a.id, .babble)
    }

    /// Free floor near the Jelbies for a guest who is already inside.
    func guestSpotNear(_ actors: [JellyActor]) -> SIMD2<Float> {
        guard let b0 = actors.first?.brain else { return GuestTuning.door }
        let c = actors.reduce(SIMD2<Float>.zero) { $0 + $1.floor } / Float(max(actors.count, 1))
        for off in [SIMD2<Float>(1.6, 0.3), SIMD2(-1.6, 0.3), SIMD2(0, -1.5), SIMD2(0, 1.5), SIMD2(2.2, -0.8), SIMD2(-2.2, -0.8)] {
            let p = c + off
            let q = b0.fixed(p)
            if simd_distance(p, q) < 0.15, !actors.contains(where: { simd_distance($0.floor, q) < 1.3 }) { return q }
        }
        return b0.fixed(c + SIMD2(1.6, 0.3))
    }

    // MARK: arriving

    private func guestArriving(_ actors: [JellyActor], _ a: JellyActor, _ b: BlobBrain, _ v: ParkVisitor, dt: Float) {
        let g = guestBook
        let calm = b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace
        g.settleT = (calm && g.phaseT > 0.8) ? g.settleT + dt : 0
        if g.settleT > 0.3 || g.phaseT > 14 {
            g.phase = .here; g.phaseT = 0
            guestWelcome(actors, a, b)
        }
    }

    /// The Jelbies hop and trot over; the guest hops back and a heart rises.
    private func guestWelcome(_ actors: [JellyActor], _ a: JellyActor, _ b: BlobBrain) {
        guard !guestBook.greeted else { return }
        guestBook.greeted = true
        b.startHopPlay(sim: a.sim, distance: 0.0001)
        b.face(.excited, hold: 2)
        AudioHub.shared.chirp(jelly: a.id, .happy)
        touchPlay?.spawnHeart(now: CACurrentMediaTime())
        var sent = 0
        for r in actors {
            guard let rb = r.brain, !rb.isSleeping, rb.commandedIdle == nil, !rb.commanded else { continue }
            rb.face(.excited, hold: 2)
            if sent < 2, rb.idleState.kind == nil, rb.scriptIsNone {
                let toward = rb.position + (b.position - rb.position) * 0.6
                let spot = rb.fixed(toward)
                if simd_distance(spot, b.position) > 1.2 { rb.request(.goTo(spot)); sent += 1 }
            }
            if sent == 0, rb.scriptIsNone, rb.idleState.kind == nil { rb.startHopPlay(sim: r.sim, distance: 0.0001); sent += 1 }
        }
    }

    // MARK: at play, at bed

    private func guestAtPlay(_ actors: [JellyActor], _ a: JellyActor, _ b: BlobBrain, _ visit: GuestVisit, dt: Float) {
        let g = guestBook
        // a group snack for the Jelbies includes him: he cheers with them when it ends (the tray seats the three Jelbies; he is not fed)
        let serving = group.isActive || groupWanted != nil
        if g.snack, !serving, !b.isSleeping, b.scriptIsNone, b.idleState.kind == nil, !b.commanded {
            b.startHopPlay(sim: a.sim, distance: 0.0001)
            b.face(.joyArc, hold: 1.5)
            AudioHub.shared.chirp(jelly: a.id, .happy)
            touchPlay?.spawnHeart(now: CACurrentMediaTime())
        }
        g.snack = serving
        let rosterSleeping = actors.contains { $0.brain?.isSleeping == true }
        if b.bedtimeHours, rosterSleeping, !b.isSleeping, !b.sleepLocked {
            // he goes to bed a little after the Jelbies do (the usual goodnight: beside a sleeper), retried until he lies down
            g.bedT -= dt
            if g.bedT <= 0 { b.commandedGoodnight = true; g.bedT = NightRestTuning.retry }
        } else if !rosterSleeping { g.bedT = 1.5 }
        // everybody else was woken (the player's word): he wakes too, a moment later
        if b.isNapping, !rosterSleeping {
            g.wakeT += dt
            if g.wakeT > 8 { g.wakeT = 0; b.sleepWake(groggy: false) }
        } else { g.wakeT = 0 }
    }

    // MARK: friendship at home

    private func guestFriends(_ actors: [JellyActor], _ a: JellyActor, _ v: ParkVisitor, dt: Float) {
        let g = guestBook, book = parkBook
        for (k, me) in actors.enumerated() {
            guard let prof = jelly(k), simd_distance(me.floor, a.floor) < ParkTuning.nearRadius else { continue }
            let before = v.level(with: prof.character)
            let closeness = max(FriendTuning.closeMul[before.rawValue], 1)
            me.brain?.socialBook.close[a.id] = closeness; a.brain?.socialBook.close[me.id] = closeness
            if me.brain?.isSleeping == true, a.brain?.isSleeping == true { continue }
            var rate = ParkTuning.pointsPerSecond * ParkTuning.homeMul * dt
            if a.id != me.id, me.brain?.social?.involves(a.id) == true {
                if let s = me.brain?.social, s.kind.isFriendly, s.end == nil {
                    rate *= ParkTuning.friendlyMul
                    if g.friendSession[k] != ObjectIdentifier(s) {
                        g.friendSession[k] = ObjectIdentifier(s)
                        if let up = book.add(points: ParkTuning.friendlyStartBonus, visitor: v.id, character: prof.character) { parkLevelUp(visitor: v.id, slot: k, level: up, visitorBody: a) }
                    }
                } else { rate *= ParkTuning.socialMul }
            }
            if let up = book.add(points: rate, visitor: v.id, character: prof.character) { parkLevelUp(visitor: v.id, slot: k, level: up, visitorBody: a) }
        }
    }

    // MARK: the goodbye

    private func guestBeginLeaving(_ actors: [JellyActor], _ a: JellyActor, _ v: ParkVisitor) {
        let g = guestBook
        guard g.phase != .leaving else { return }
        g.phase = .leaving; g.stage = 0; g.phaseT = 0; g.card = false
        a.brain?.abortAll(a.sim, a.skinner)
        a.brain?.autonomy = false
    }

    private func guestLeaving(_ actors: [JellyActor], _ a: JellyActor, _ b: BlobBrain, _ v: ParkVisitor, _ visit: GuestVisit, dt: Float) {
        let g = guestBook
        switch g.stage {
        case 0:          // wake up (a sleeper rolls over), then turn and wave
            if b.isSleeping {
                if !b.sleep.wakeAsked { b.sleepWake(groggy: false) }
                if g.phaseT < 8 { return }
            }
            guard g.phaseT > 0.4, b.scriptIsNone, b.idleState.kind == nil || g.phaseT > 8 else { return }
            b.requestNow(.wave)
            AudioHub.shared.chirp(jelly: a.id, .babble)
            for r in actors { if let rb = r.brain, !rb.isSleeping, rb.scriptIsNone { rb.face(.happy, hold: 2.5) } }
            g.stage = 1; g.phaseT = 0
        case 1:          // the wave to the camera is over: head for the door
            let waving = b.isWaving || b.pending != nil || b.interruptScript
            if (!waving && g.phaseT > 0.8) || g.phaseT > 6 {
                b.requestNow(.goTo(GuestTuning.door))
                g.stage = 2; g.phaseT = 0
            }
        default:         // out of the door
            let far = simd_distance(b.position, GuestTuning.door) < 0.8
            if (far && g.phaseT > 0.6) || g.phaseT > 10 {
                let name = v.name
                guestRemove()
                g.finish()
                park.say("\(name) waved goodbye and went home!")
                AudioHub.shared.chirp(jelly: 0, .happy)
            }
        }
    }
}
