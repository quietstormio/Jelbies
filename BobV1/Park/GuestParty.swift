//
//  GuestParty.swift
//  The welcome party (2026-11-06, "make the celebration when a friend comes over a little longer and more dramatic, everyone jumps around and makes Jelbie noises,
//  then back to normal ... maybe a group emote"). It runs AFTER the arrival's group hug (Park/GuestArrival.swift is untouched up to the hug):
//    hug      the existing group hug (about 8 s: walk in, huddle 5.8 s, break apart with hops)
//    dance    EVERYONE (the home Jelbies and the guest) in a group emote through the public start API `socialStartGroup`: the ring dance (chimes, bounces, quarter
//             turns, about 10 s) while the crew fits it (it takes three: two home + the guest); the circle dance (a ring that hops round, up to five) for a bigger house
//    finale   a few staggered happy hops in place (0.2...0.5 s apart per Jelbie), each with a voice
//    done     everybody is back to normal roaming (nothing held, no stuck state)
//  The voices (2 here + the emotes' own) go through the existing chirp / context voices, staggered per Jelbie, so the 2.2 s hush per Jelbie is never fought.
//  Only existing public brain moves are used: `socialStartGroup`, `startHopPlay` (the locked in-place hop that already passes EmoteFeetTests), `face`.
//

import Foundation
import simd

nonisolated enum PartyTuning {
    /// After the hug is over, a beat before the dance.
    static let startDelay: Float = 0.5
    /// The hug never started (a household of one, somebody busy): the dance is tried after this long anyway.
    static let noHugWait: Float = 4
    /// The longest the hug is waited for.
    static let hugMax: Float = 16
    /// The group emote start is retried this long, then the party goes straight to the finale.
    static let danceStartMax: Float = 4
    static let danceMax: Float = 24
    /// The finale: each Jelbie does this many happy hops in place, the first after `0.2...0.5 s` x its place (staggered), the next `hopGap` later.
    static let finaleHops = 2
    static let stagger: ClosedRange<Float> = 0.2...0.5
    static let hopGap: Float = 1.4
    static let finaleMax: Float = 9
    /// Voices of the party itself (seconds from its start, plus `voiceStagger` x the Jelbie's place): one in the hug, one in the dance; the finale's hop adds the third.
    static let voiceAt: [Float] = [1.5, 9.0]
    static let voiceStagger: Float = 0.45
}

@MainActor
struct GuestParty {
    enum Stage { case off, hug, dance, finale, done }
    private(set) var stage: Stage = .off
    /// Seconds since the party began / since this stage began.
    private(set) var t: Float = 0, stageT: Float = 0
    /// The group emote that ran, who was in it (steer ids) and the hug that came first.
    private(set) var kind: SocialKind?
    private(set) var crew: [Int] = []
    private(set) var hugSeen = false
    private(set) var danceStarted = false
    /// Per member (by place): hops started in the finale, the next hop's time, voices made.
    private(set) var hops: [Int] = []
    private var nextHop: [Float] = []
    private var voices: [Int] = []

    var active: Bool { stage != .off && stage != .done }

    mutating func begin() {
        self = GuestParty()
        stage = .hug
    }
    mutating func cancel() { stage = .off }

    /// Where a member's hop starts in the finale: each place `stagger` (0.2...0.5 s, a fixed non-uniform pattern) after the one before.
    static func hopOffset(place i: Int) -> Float {
        let r = PartyTuning.stagger
        var o: Float = 0
        for k in 0..<max(i, 0) { o += r.lowerBound + ((Float(k) + 1) * 0.618).truncatingRemainder(dividingBy: 1) * (r.upperBound - r.lowerBound) }
        return o
    }

    private mutating func go(_ s: Stage) { stage = s; stageT = 0 }

    /// One fixed step. `brains` / `sims`: the home Jelbies and the guest (any order, all of them). `voice(place, which)` makes the noise.
    mutating func step(brains: [BlobBrain], sims: [SoftBody], dt: Float, voice: (Int, JellyVoice) -> Void) {
        guard active, brains.count == sims.count, !brains.isEmpty else { return }
        if hops.count != brains.count { hops = [Int](repeating: 0, count: brains.count); nextHop = [Float](repeating: 0, count: brains.count); voices = [Int](repeating: 0, count: brains.count) }
        t += dt; stageT += dt

        // the party's own voices, staggered per Jelbie, through the hush (one in the hug, one in the dance)
        for i in brains.indices where voices[i] < PartyTuning.voiceAt.count && t >= PartyTuning.voiceAt[voices[i]] + Float(i) * PartyTuning.voiceStagger {
            if !brains[i].isSleeping { voice(i, voices[i] == 0 ? .happy : .babble) }
            voices[i] += 1
        }

        let anySocial = brains.contains { $0.social != nil }
        switch stage {
        case .hug:
            if brains.contains(where: { $0.social?.kind == .groupHug }) { hugSeen = true }
            if hugSeen, !anySocial, stageT > PartyTuning.startDelay { go(.dance) }
            else if !hugSeen, stageT > PartyTuning.noHugWait, !anySocial { go(.dance) }
            else if stageT > PartyTuning.hugMax { go(.dance) }
        case .dance:
            if !danceStarted {
                let awake = brains.indices.filter { !brains[$0].isSleeping }
                let k: SocialKind = awake.count <= EmoteTuning.treatCrew ? .ringDance : .circleDance
                if awake.count >= 3, let s = awake.first(where: { brains[$0].socialFree }) {
                    let others = awake.filter { $0 != s }.map { brains[$0] }
                    if brains[s].socialStartGroup(k, with: others, sims[s]) {
                        danceStarted = true; kind = k
                        crew = brains[s].social?.crewIDs ?? []
                    }
                }
                if !danceStarted, stageT > PartyTuning.danceStartMax { go(.finale) }
            } else if !anySocial, stageT > 0.5 { go(.finale) }
            else if stageT > PartyTuning.danceMax { go(.finale) }
        case .finale:
            var allDone = true
            for i in brains.indices {
                let b = brains[i]
                if b.isSleeping { continue }
                if hops[i] >= PartyTuning.finaleHops { continue }
                allDone = false
                if hops[i] == 0, nextHop[i] == 0 { nextHop[i] = Self.hopOffset(place: i) + 0.2 }
                if stageT >= nextHop[i], b.fxFree, b.social == nil, !b.commanded, !b.held {
                    b.startHopPlay(sim: sims[i], distance: 0.0001)
                    b.face(.joyArc, hold: 1.2)
                    if hops[i] == 0 { voice(i, i % 2 == 0 ? .yay : .wheee) }
                    hops[i] += 1
                    nextHop[i] = stageT + PartyTuning.hopGap + Self.hopOffset(place: i) * 0.3
                }
            }
            if (allDone && brains.allSatisfy({ $0.fxFree || $0.isSleeping }) && stageT > 0.8) || stageT > PartyTuning.finaleMax { go(.done) }
        case .off, .done: break
        }
    }
}
