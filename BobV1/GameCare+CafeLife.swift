//
//  GameCare+CafeLife.swift
//  The café's table life: the Jelbies stand at the café table from the moment they arrive and TALK (their own chirp / babble voices, a face and a hop for the one
//  who answers), now and then a small thought bubble shows an icon over one of them, and after the cheer they stay at the table for the lounge: calm idles
//  that already exist (look, chirp, giggle, bounce, stretch), a cosy mood boost and the usual Go home. No new bodies, no sitting (their arms are too short),
//  no new contact code: everything here is existing brain requests and the audio hub's voices.
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

    /// Chatter and thoughts, once per step while they are at the table (menu, meal, cheer and lounge).
    func tickCafeTalk(_ actors: [JellyActor], dt: Float) {
        let book = cafeBook
        let live = actors.filter { $0.brain != nil }
        guard !live.isEmpty else { return }
        // the one who answers
        for (id, t) in book.replyIn {
            let left = t - dt
            if left > 0 { book.replyIn[id] = left; continue }
            book.replyIn[id] = nil
            guard let a = live.first(where: { $0.id == id }), let b = a.brain else { continue }
            AudioHub.shared.chirp(jelly: id, Bool.random() ? .happy : .babble)
            b.face(.happy, hold: 1.0)
            if cafeIdleNow(b) { b.startHopPlay(sim: a.sim, distance: 0.0001) }
        }
        // turn-taking: one speaks every few seconds, another answers a moment later
        book.chatT -= dt
        if book.chatT <= 0 {
            book.chatT = Float.random(in: CafeTuning.chatEvery)
            let pool = live.count > 1 ? live.filter { $0.id != book.lastSpeaker } : live
            if !book.regulars.isEmpty, Float.random(in: 0..<1) < 0.25, let k = book.regularVisitors.indices.randomElement(), let rb = book.regulars[k].brain {          // a regular chimes in (his own species' voice)
                AudioHub.shared.chirp(character: Self.regularVoiceCharacter(book.regularVisitors[k]), Bool.random() ? .babble : .happy)
                rb.face(.excited, hold: 1.2)
            } else if let sp = pool.randomElement(), let sb = sp.brain {
                book.lastSpeaker = sp.id
                AudioHub.shared.chirp(jelly: sp.id, Bool.random() ? .babble : .happy)
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

    /// After the cheer: back at their own stand, the cosy boost, then a calm idle every few seconds until Go home.
    func tickCafeLounge(_ actors: [JellyActor], dt: Float) {
        let book = cafeBook
        if !book.lounged {
            book.lounged = true
            if dining.phase == .present, !book.lastTreatByPlace.isEmpty { dining.restock(serving: CafePlate.cups(book.lastTreatByPlace)) }          // a cup in front of everybody: they sip
            for a in actors {
                guard let b = a.brain else { continue }
                b.abortAll(a.sim, a.skinner)
                b.commandedIdle = nil
                if let st = book.stands[a.id] { b.requestNow(.goTo(st)) }
                b.face(.happy, hold: 2)
                b.blushBump(hold: 3, peak: 0.5)
                if (book.ate[a.id] ?? 0) > 0 {          // the café-only "cozy": stronger and longer than at home
                    needs(for: a.id).gain(.attention, CafeTuning.loungeAttention)
                    jelly(a.id)?.perks.grant(.cozy, duration: PerkKind.cozy.duration * 3)
                }
                book.loungeIdle[a.id] = Float.random(in: 2...4)
            }
        }
        for a in actors {
            guard let b = a.brain, var t = book.loungeIdle[a.id] else { continue }
            guard cafeIdleNow(b) else { continue }
            t -= dt
            if t > 0 { book.loungeIdle[a.id] = t; continue }
            book.loungeIdle[a.id] = Float.random(in: 3...6)
            if let st = book.stands[a.id], simd_distance(Self.floorPos(b, a.sim), st) > 0.3 { b.requestNow(.goTo(st)); book.loungeIdle[a.id] = 2; continue }
            if abs(Self.wrapAngle(b.yaw - b.faceCameraYaw())) > 0.5 { b.startTurn(to: b.faceCameraYaw(), sim: a.sim); book.loungeIdle[a.id] = 1.3; continue }          // always facing the room, never away
            b.commandedIdle = [IdleKind.chirp, .giggle, .bounce, .stretch].randomElement()
            b.face(.happy, hold: 1.5)
            if Float.random(in: 0..<1) < 0.5 { b.blushBump(hold: 2, peak: 0.5) }
            if Float.random(in: 0..<1) < 0.25 { touchPlay?.spawnHeart(now: CACurrentMediaTime()) }
        }
    }
}
