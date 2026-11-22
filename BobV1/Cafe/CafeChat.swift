//
//  CafeChat.swift
//  cafe-talk-r1: the in-place conversation at a café table. ONE function for any table: `GameCare.tickCafeChat(seats, state:, dt:, voice:)` takes the bodies at the table
//  (brain + sim + stand + the heading each keeps), never roster ids, so the player's table and the regulars' tables share it.
//  Nobody walks, steps or turns: a speaker says a line (voice, talking face, a nod or a small lean toward the listener, sometimes a little arm gesture), the listener
//  looks at the speaker and answers a moment later (a face, a nod or a giggle), there are pauses of a second or two and now and then all of them laugh together.
//  Every motion is the planted `.giggle` idle or the additive `ChatOverlay`; the only correction is a safety net that walks / turns a body back that something else moved.
//

import Foundation
import simd

/// One body at a table. `yaw` is the heading it keeps (the two ends face each other, the middle one the room, a pair face each other three-quarter).
struct CafeChatSeat {
    var id: Int
    var brain: BlobBrain
    var sim: SoftBody
    var skinner: Skinner
    var stand: SIMD2<Float>
    var yaw: Float
}

/// A seeded random stream of the conversation's own (the brain's `rand()` sequence is never consumed here).
struct CafeChatRNG {
    var s: UInt64
    init(seed: UInt64 = 0x9E3779B97F4A7C15) { s = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> Float { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return Float(s >> 40) / Float(1 << 24) }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
    mutating func chance(_ p: Float) -> Bool { next() < p }
}

/// What the conversation of ONE table remembers.
final class CafeChatState {
    enum Act { case say(listener: Int, secs: Float), answer(to: Int, secs: Float), listen(to: Int, secs: Float), laugh }
    struct Event { var at: Float; var seat: Int; var act: Act }
    var rng: CafeChatRNG
    var clock: Float = 0
    var nextLine: Float = 0.8
    var lastSpeaker: Int?
    var events: [Event] = []
    var guardCool: [Int: Float] = [:]
    // numbers for the log and the tests
    var lines = 0, answers = 0, laughs = 0, corrections = 0
    init(seed: UInt64 = 0x9E3779B97F4A7C15) { rng = CafeChatRNG(seed: seed) }
}

extension GameCare {
    /// The table talk, once per fixed step. `voice` plays the seat's own voice (players: `AudioHub.chirp(jelly:)`, regulars: `chirp(character:)`).
    /// Pauses: the next line starts 1...2 s after the previous answer began, so a table of two or three keeps taking turns without ever talking over each other.
    func tickCafeChat(_ seats: [CafeChatSeat], state st: CafeChatState, dt: Float, voice: (CafeChatSeat, JellyVoice) -> Void) {
        guard !seats.isEmpty else { return }
        st.clock += dt
        let now = st.clock
        func seat(_ id: Int) -> CafeChatSeat? { seats.first { $0.id == id } }
        // the facing is HELD by the brain's own calm wait (a standing body turns to `mealFaceYaw` when reserved, else back to the camera): the meal's end and any abort drop it, so it is set every step
        for s in seats where s.brain.mealFaceYaw != s.yaw || !s.brain.reserved { s.brain.reserved = true; s.brain.mealFaceYaw = s.yaw }
        /// Where `to` is, as a bearing from the heading of `from` (0 = straight ahead, + = toward increasing yaw).
        func bearing(_ from: CafeChatSeat, _ to: CafeChatSeat) -> Float {
            let d = to.stand - from.stand
            return Self.wrapAngle(atan2f(d.x, d.y) - from.yaw)
        }
        // a new exchange
        if st.nextLine <= now, st.events.isEmpty {
            let pool = seats.count > 1 ? seats.filter { $0.id != st.lastSpeaker } : seats
            if let sp = pool.isEmpty ? nil : pool[min(pool.count - 1, Int(st.rng.next() * Float(pool.count)))] {
                st.lastSpeaker = sp.id
                let others = seats.filter { $0.id != sp.id }
                if seats.count >= 2, st.rng.chance(0.14) {          // all of them laugh together
                    for (k, s) in seats.enumerated() { st.events.append(.init(at: now + Float(k) * st.rng.range(0.1, 0.35), seat: s.id, act: .laugh)) }
                    st.laughs += 1
                    st.nextLine = now + 2.4 + st.rng.range(0.8, 1.6)
                } else {
                    let say = st.rng.range(1.2, 1.9)
                    let li = others.isEmpty ? nil : others[min(others.count - 1, Int(st.rng.next() * Float(others.count)))]
                    st.events.append(.init(at: now, seat: sp.id, act: .say(listener: li?.id ?? sp.id, secs: say)))
                    if let li {
                        st.events.append(.init(at: now + 0.15, seat: li.id, act: .listen(to: sp.id, secs: say + 0.2)))
                        let ans = st.rng.range(0.9, 1.3)
                        st.events.append(.init(at: now + say * 0.65 + st.rng.range(0.5, 0.9), seat: li.id, act: .answer(to: sp.id, secs: ans)))
                        if let third = others.first(where: { $0.id != li.id }), st.rng.chance(0.5) { st.events.append(.init(at: now + 0.3, seat: third.id, act: .listen(to: sp.id, secs: say))) }
                        st.nextLine = now + say * 0.65 + 0.9 + st.rng.range(1.0, 2.0)
                    } else { st.nextLine = now + say + st.rng.range(2.0, 3.5) }          // (alone: calm chirps now and then)
                }
            }
        }
        // the events that are due
        var i = 0
        while i < st.events.count {
            guard st.events[i].at <= now else { i += 1; continue }
            let e = st.events.remove(at: i)
            guard let me = seat(e.seat) else { continue }
            let b = me.brain
            switch e.act {
            case .say(let to, let secs):
                voice(me, st.rng.chance(0.5) ? .babble : .happy)
                b.face(.excited, hold: secs)
                if st.rng.chance(0.3) { b.blushBump(hold: 1.5, peak: 0.4) }
                let arm: Float = st.rng.chance(0.35) ? 1 : 0
                if let l = seat(to), l.id != me.id { b.chatPose(lean: 0.07, toward: bearing(me, l), bob: arm > 0 ? 0.02 : 0.045, bobHz: 2.6, arm: arm, mouth: 1, hold: secs) }
                else { b.chatPose(lean: 0, bob: 0.04, bobHz: 2.4, arm: arm, mouth: 1, hold: secs) }
                st.lines += 1
            case .listen(let to, let secs):
                guard let s = seat(to) else { continue }
                let br = bearing(me, s)
                b.chatPose(lean: 0.03, toward: br, look: br * 0.15, bob: st.rng.chance(0.6) ? 0.035 : 0, bobHz: 1.6, hold: secs)
                b.face(.happy, hold: min(secs, 1.2))
            case .answer(let to, let secs):
                let giggle = st.rng.chance(0.3)
                voice(me, giggle ? .giggle : (st.rng.chance(0.5) ? .happy : .babble))
                b.face(giggle ? .joyArc : .happy, hold: secs + 0.3)
                if let s = seat(to) { b.chatPose(lean: 0.06, toward: bearing(me, s), look: bearing(me, s) * 0.15, bob: 0.04, bobHz: 2.8, mouth: giggle ? 0 : 1, hold: secs) }
                if giggle, Self.cafeSeatCanPlay(b) { b.commandedIdle = .giggle }
                st.answers += 1
            case .laugh:
                voice(me, .giggle)
                b.face(.joyArc, hold: 1.4)
                b.blushBump(hold: 2, peak: 0.5)
                if Self.cafeSeatCanPlay(b) { b.commandedIdle = .giggle }
            }
        }
        // the safety net: anything that moved or turned a body is walked / turned back (the conversation itself never does)
        for s in seats {
            let b = s.brain
            st.guardCool[s.id, default: 0] -= dt
            guard Self.cafeSeatCanPlay(b), st.guardCool[s.id, default: 0] <= 0 else { continue }
            if simd_distance(Self.floorPos(b, s.sim), s.stand) > 0.12 { b.requestNow(.goTo(s.stand)); st.guardCool[s.id] = 2; st.corrections += 1 }
            else if abs(Self.wrapAngle(b.yaw - s.yaw)) > 0.12 { b.startTurn(to: s.yaw, sim: s.sim); st.guardCool[s.id] = 1.5; st.corrections += 1 }
        }
    }

    /// Standing still with nothing else going on (no walk, turn, idle or command): safe to start a planted idle or a correction.
    static func cafeSeatCanPlay(_ b: BlobBrain) -> Bool {
        guard b.commandedIdle == nil, b.idleState.kind == nil else { return false }
        if case .none = b.script { return b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace }
        return false
    }
}
