//
//  GameCare+CafeLife.swift
//  The café's table life: the Jelbies stand at the café table from the moment they arrive and TALK (their own chirp / babble voices, a face and a hop for the one
//  who answers), now and then a small thought bubble shows an icon over one of them, and after the cheer they stay at the table for the lounge: a cosy mood boost,
//  the usual Go home and (cafe-talk-r1) the in-place conversation (CafeChat.swift): everybody stays on his stand with his facing (the two ends at each other, the middle
//  one the room, a pair at each other), nobody walks, steps or turns, and they take turns talking, nodding and laughing. No new bodies, no sitting (their arms are too short),
//  no new contact code: everything here is existing brain requests, the planted giggle, the small chat overlay and the audio hub's voices.
//

import Foundation
import QuartzCore
import simd

extension GameCare {
    private func cafeIdleNow(_ b: BlobBrain) -> Bool {
        guard b.commandedIdle == nil, b.idleState.kind == nil else { return false }
        if case .none = b.script { return b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace }
        return false
    }

    /// A treat is done: from now on this diner only sits and talks (cheer, lounge and done phases count for everybody).
    func cafeFinished(_ id: Int) -> Bool {
        switch cafe.phase { case .cheer, .lounge, .done: return true; case .eating: return cafe.served.contains(id); default: return false }
    }
    /// cafe-busy-r1: every diner whose treat is done keeps his seat and his facing, every step (the group serving hands a finished diner back to his own life: it unreserves him, so he would turn to
    /// the camera, and the café's tray-clear step-aside would walk him off his stand). `-CafeCalmOff 1` is the old behaviour (A/B).
    func cafeHoldFinished(_ actors: [JellyActor]) {
        guard !Self.cafeCalmOff, cafe.phase == .eating || cafe.phase == .cheer || cafe.phase == .lounge || cafe.phase == .done else { return }
        for s in cafeSeats(actors) where cafeFinished(s.id) {
            let b = s.brain
            if !b.reserved || b.mealFaceYaw != s.yaw { b.reserved = true; b.mealFaceYaw = s.yaw }
            b.idleBlocked = true; b.autonomy = false
        }
    }
    /// The customers who are sitting at their tables now.
    var cafeSeatedCustomers: [CafeMember] { cafeBook.crowd.live.values.flatMap { $0.members.filter { $0.state == .seated } } }

    /// Chatter and thoughts, once per step while they are at the table (menu, meal, cheer and lounge).
    func tickCafeTalk(_ actors: [JellyActor], dt: Float) {
        let book = cafeBook
        let live = actors.filter { $0.brain != nil }
        guard !live.isEmpty else { return }
        CafeTalkProbe.shared.tick(self, actors, dt: dt)
        let lounging = cafe.phase == .lounge || cafe.phase == .done          // (cafe-talk-r1: from the lounge on, the in-place conversation talks; the menu / meal / cheer chatter below is as it was)
        // the one who answers
        for (id, t) in book.replyIn where !lounging {
            let left = t - dt
            if left > 0 { book.replyIn[id] = left; continue }
            book.replyIn[id] = nil
            guard let a = live.first(where: { $0.id == id }), let b = a.brain else { continue }
            AudioHub.shared.chirp(jelly: id, Bool.random() ? .happy : .babble, src: "cafe")
            b.face(.happy, hold: 1.0)
            if cafeIdleNow(b), Self.cafeCalmOff || !cafeFinished(id) { b.startHopPlay(sim: a.sim, distance: 0.0001) }          // (cafe-busy-r1: nobody hops once his treat is done)
        }
        // turn-taking: one speaks every few seconds, another answers a moment later
        book.chatT -= dt
        if lounging {
            if book.chatT <= 0 {
                book.chatT = Float.random(in: CafeTuning.chatEvery)
                if Float.random(in: 0..<1) < 0.25, let m = cafeSeatedCustomers.randomElement(), let rb = m.actor.brain {          // a customer chimes in (his own species' voice)
                    AudioHub.shared.chirp(character: Self.regularVoiceCharacter(m.visitor), Bool.random() ? .babble : .happy, quiet: true)
                    rb.face(.excited, hold: 1.2)
                }
            }
        } else if book.chatT <= 0 {
            book.chatT = Float.random(in: CafeTuning.chatEvery)
            let pool = live.count > 1 ? live.filter { $0.id != book.lastSpeaker } : live
            if Float.random(in: 0..<1) < 0.25, let m = cafeSeatedCustomers.randomElement(), let rb = m.actor.brain {          // a customer chimes in (his own species' voice)
                AudioHub.shared.chirp(character: Self.regularVoiceCharacter(m.visitor), Bool.random() ? .babble : .happy, quiet: true)
                rb.face(.excited, hold: 1.2)
            } else if let sp = pool.randomElement(), let sb = sp.brain {
                book.lastSpeaker = sp.id
                AudioHub.shared.chirp(jelly: sp.id, Bool.random() ? .babble : .happy, src: "cafe")
                sb.face(.excited, hold: 1.2)
                if Float.random(in: 0..<1) < 0.3 { sb.blushBump(hold: 1.5, peak: 0.4) }
                if let li = live.filter({ $0.id != sp.id }).randomElement() { book.replyIn[li.id] = Float.random(in: 0.8...1.4) }
            }
        }
        // thought bubbles: one at a time (so they never overlap), 3...5 s, café icons
        if var t = book.thought {
            t.left -= dt
            if t.left <= 0 { book.thought = nil; book.thoughtT = Float.random(in: 1.5...3.5) } else { book.thought = t }
        } else {
            book.thoughtT -= dt
            if book.thoughtT <= 0, let who = live.randomElement() {
                var rng = SystemRandomNumberGenerator()
                book.thought = CafeThought.pick(who: who.id, friends: live.map(\.id), using: &rng, seconds: CafeTuning.thoughtSeconds)
                book.thoughtT = Float.random(in: CafeTuning.thoughtEvery)
            }
        }
    }

    /// The bodies at the player's table with the heading each keeps: the two ends at each other (`chatYaw`), the middle one the room, a pair at each other (three-quarter,
    /// toward the room a little), one alone the room.
    func cafeSeats(_ actors: [JellyActor]) -> [CafeChatSeat] {
        let book = cafeBook
        let diners = actors.filter { $0.brain != nil && book.stands[$0.id] != nil }
        return diners.compactMap { a -> CafeChatSeat? in
            guard let b = a.brain, let st = book.stands[a.id] else { return nil }
            var yaw = b.faceCameraYaw()
            if let cy = book.chatYaw[a.id] { yaw = cy }
            else if diners.count == 2, let o = diners.first(where: { $0.id != a.id }), let os = book.stands[o.id] {
                let d = os - st
                yaw = yaw + Self.wrapAngle(atan2f(d.x, d.y) - yaw) * 0.75
            }
            return CafeChatSeat(id: a.id, brain: b, sim: a.sim, skinner: a.skinner, stand: st, yaw: yaw)
        }
    }

    /// After the cheer: they stay on their own stand (walked back only if something really moved them), the cosy boost, then the table talk until Go home.
    func tickCafeLounge(_ actors: [JellyActor], dt: Float) {
        let book = cafeBook
        if !book.lounged {
            book.lounged = true
            book.replyIn = [:]          // (a stale answer from the cheer never hops in the lounge)
            if dining.phase == .present, !book.lastTreatByPlace.isEmpty { dining.restock(serving: CafePlate.cups(book.lastTreatByPlace, straws: true)) }          // a cup in front of everybody: they sip
            let seats = cafeSeats(actors)
            for a in actors {
                guard let b = a.brain else { continue }
                if Self.cafeCalmOff { b.abortAll(a.sim, a.skinner); b.commandedIdle = nil }          // (cafe-busy-r1: nothing is aborted, nobody is walked back: they have been held on their stand since their treat was done)
                if let s = seats.first(where: { $0.id == a.id }) {
                    b.reserved = true; b.mealFaceYaw = s.yaw          // (the calm wait holds his facing: the ends at each other, the middle the room, a pair at each other)
                    if Self.cafeCalmOff, simd_distance(Self.floorPos(b, a.sim), s.stand) > 0.15 { b.requestNow(.goTo(s.stand)) }
                }
                b.face(.happy, hold: 2)
                b.blushBump(hold: 3, peak: 0.5)
                if (book.ate[a.id] ?? 0) > 0 {          // the café-only "cozy": stronger and longer than at home
                    needs(for: a.id).gain(.attention, CafeTuning.loungeAttention)
                    jelly(a.id)?.perks.grant(.cozy, duration: PerkKind.cozy.duration * 3)
                }
            }
            book.chat = CafeChatState()
        }
        tickCafeChat(cafeSeats(actors), state: book.chat, dt: dt) { [weak self] s, v in
            AudioHub.shared.chirp(jelly: s.id, v, src: "cafe")
            if Float.random(in: 0..<1) < 0.1 { self?.touchPlay?.spawnHeart(now: CACurrentMediaTime()) }
        }
    }
}
