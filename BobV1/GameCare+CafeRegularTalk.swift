//
//  GameCare+CafeRegularTalk.swift
//  The in-place conversation of the café's guest pair (cafe-regulars-r1): `tickCafeInPlaceTalk` takes a list of bodies (the brain, where each one stands, which way it faces) and keeps
//  them at those spots, facing those ways, TAKING TURNS: one speaks (its own species' voice, quietly: a background murmur, a talking face and now and then a small arm gesture), the other
//  answers a moment later, then a short pause, a sip (a face with the eyes closed; the cup stands on the table) or a shared giggle. Feet planted the whole time, no sitting, no contact,
//  faces never close. Only existing brain requests and the audio hub's own voices. Self-contained on purpose: the player's table talk (GameCare+CafeLife.swift) is joined with it later.
//

import Foundation
import simd

/// One body of the conversation: the actor (its brain is used), where it stands (floor x, z), the yaw it faces and the species voice (`regularVoiceCharacter`).
struct CafeTalker {
    let actor: JellyActor
    var stand: SIMD2<Float>
    var yaw: Float
    var voice: Int
}

/// The conversation's own clock: seconds to the next beat, who spoke last, the answer that is due and who gives it.
final class CafeTalkState {
    var beatIn: Float = 1.2
    var lastSpeaker = -1
    var replyIn: Float = -1
    var replier = -1
    var giggleIn: Float = -1
    var sipIn: Float = -1
    var sipper = -1
    nonisolated deinit {}
}

extension GameCare {
    /// Tuning of the guests' murmur (shared with the tests).
    enum CafeTalkTuning {
        /// Seconds between one beat and the next (a pause after every line).
        static let pause: ClosedRange<Float> = 1.6...3.4
        /// The answer comes this long after the line.
        static let answer: ClosedRange<Float> = 1.2...1.9
        /// Shares of the beats: a line (the rest of the shares are a sip and a shared giggle).
        static let lineShare: Float = 0.68, sipShare: Float = 0.16
        /// A line is followed by a small arm gesture this often.
        static let gestureShare: Float = 0.3
    }

    private func cafeTalkIdleNow(_ b: BlobBrain) -> Bool {
        guard b.commandedIdle == nil, b.idleState.kind == nil else { return false }
        if case .none = b.script { return b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace }
        return false
    }

    /// Once per step: keeps `talkers` at their stands facing their yaws and runs the turn-taking. Any number of bodies (two is the café's guest pair); one body only holds its spot.
    func tickCafeInPlaceTalk(_ talkers: [CafeTalker], state: CafeTalkState, dt: Float) {
        guard !talkers.isEmpty else { return }
        // 1. hold the spot and the facing (the meal's calm wait: squares up to `mealFaceYaw` and only blinks), walk back if something nudged one off
        for t in talkers {
            guard let b = t.actor.brain else { continue }
            b.autonomy = false; b.idleBlocked = true; b.reserved = true; b.mealFaceYaw = t.yaw
            if cafeTalkIdleNow(b), simd_distance(Self.floorPos(b, t.actor.sim), t.stand) > 0.2 { b.requestNow(.goTo(t.stand)) }
        }
        guard talkers.count >= 2 else { return }
        func say(_ k: Int, answer: Bool) {
            let t = talkers[k]
            guard let b = t.actor.brain else { return }
            AudioHub.shared.chirp(character: t.voice, answer ? .happy : (Bool.random() ? .babble : .happy), quiet: true)
            b.face(answer ? .happy : .excited, hold: 1.2)
            if Float.random(in: 0..<1) < 0.25 { b.blushBump(hold: 1.5, peak: 0.35) }
            if cafeTalkIdleNow(b), Float.random(in: 0..<1) < CafeTalkTuning.gestureShare { b.commandedIdle = [IdleKind.giggle, .signatureFlourish].randomElement() }          // (a small arm / body gesture, feet planted)
            for (j, o) in talkers.enumerated() where j != k { o.actor.brain?.face(answer ? .joyArc : .curious, hold: 1.2) }          // (the other one listens)
        }
        // 2. the answer that is due
        if state.replyIn >= 0 {
            state.replyIn -= dt
            if state.replyIn < 0, talkers.indices.contains(state.replier) { say(state.replier, answer: true); state.lastSpeaker = state.replier }
        }
        // a sip: the eyes close for a moment, a small blush (the cup stands on the table)
        if state.sipIn >= 0 {
            state.sipIn -= dt
            if state.sipIn < 0, talkers.indices.contains(state.sipper), let b = talkers[state.sipper].actor.brain { b.face(.joyArc, hold: 1.1) }
        }
        // a shared giggle
        if state.giggleIn >= 0 {
            state.giggleIn -= dt
            if state.giggleIn < 0 {
                for t in talkers { guard let b = t.actor.brain else { continue }; b.face(.joyArc, hold: 1.0); if cafeTalkIdleNow(b) { b.commandedIdle = .giggle } }
            }
        }
        // 3. the next beat
        state.beatIn -= dt
        guard state.beatIn <= 0 else { return }
        state.beatIn = Float.random(in: CafeTalkTuning.pause)
        let roll = Float.random(in: 0..<1)
        if roll < CafeTalkTuning.lineShare || state.lastSpeaker < 0 {
            let k = state.lastSpeaker < 0 ? Int.random(in: 0..<talkers.count) : (Float.random(in: 0..<1) < 0.8 ? (state.lastSpeaker + 1) % talkers.count : state.lastSpeaker)
            state.lastSpeaker = k
            say(k, answer: false)
            state.replier = (k + 1) % talkers.count
            state.replyIn = Float.random(in: CafeTalkTuning.answer)
            state.beatIn += state.replyIn
        } else if roll < CafeTalkTuning.lineShare + CafeTalkTuning.sipShare {
            state.sipper = Int.random(in: 0..<talkers.count); state.sipIn = 0
        } else {
            state.giggleIn = 0
        }
    }
}
