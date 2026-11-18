//
//  ShowDanceSteps.swift
//  The Jelly Show's Dance round on his feet: he stands the whole song and takes one step on every beat of the song's own grid. The plan is one
//  four-beat phrase (a bar) at a time: the side step-touch is the base he always comes back to, and between the bases come other step phrases
//  (march, twist step, twirl, kick out, hop step), never the same one twice running, the gentle ones on the calm songs (Puddle / Pond) and the
//  energetic ones added on the lively songs (Lagoon / Ocean). Every step goes through the normal foot code (`startStep` + `gaitPose`, the same as the
//  walk's and the step-in-place idle's), started so that the foot PLANTS on the beat.
//
//  The Perfect accent is a stomp on the next step. A Miss never stops the stepping. He ends with feet together, facing front.
//

import Foundation
import simd

nonisolated enum ShowDanceMove: String, CaseIterable, Sendable {
    case stepTouch      // side step-touch: lead foot out, the other closes, then back the other way (L R R L); the base step
    case march          // high-knee march on the spot, chest out
    case twist          // step on the spot with the belly twisting toward the stepping foot, a loose sway
    case twirl          // four steps round on the spot: a full turn per bar
    case kickOut        // each step swings the foot wide out to the side and the body leans away
    case hopStep        // springy steps: high lift, a bounce with every plant

    var title: String {
        switch self {
        case .stepTouch: return "Step-touch"; case .march: return "March"; case .twist: return "Twist step"
        case .twirl: return "Twirl"; case .kickOut: return "Kick out"; case .hopStep: return "Hop step"
        }
    }
    /// The moves between the bases: gentle ones for the calm songs, the energetic ones added for the lively songs.
    static func pool(lively: Bool) -> [ShowDanceMove] { lively ? [.kickOut, .hopStep, .march, .twirl, .twist] : [.twist, .twirl, .march] }
}

/// One step of a phrase: which foot, how the root and the landing move, and how the body pose rides on it.
nonisolated struct DanceStepSpec: Sendable {
    var side = 0
    var rootD = SIMD2<Float>.zero, reach = SIMD2<Float>.zero          // (body frame: x = his right)
    var dyaw: Float = 0
    var peak: Float = 0.07                                            // foot lift (u, before the amplitude)
    var out: Float = 1                                                // sideways swing of the swing foot
    var inPlace = true
    var sway: Float = 0.08, bob: Float = 0.03, rock: Float = 0.3
    var twist: Float = 0, pitch: Float = 0
    var lean: Float = 0                                               // lean into the direction of travel (rad)
}

nonisolated enum ShowDancePlan {
    static let beatsPerBar = 4
    /// The foot plants this far (of its step time) after the step starts (`startStep`'s swing fraction); the step runs a little shorter than a beat so two steps never overlap.
    static let swingFrac: Float = 0.8
    static let rateFactor: Float = 1.08
    static func lively(_ rank: ShowRank) -> Bool { rank.index >= ShowRank.lagoon.index }
    /// Bars in the round: the song's last prompt beat in whole bars (24 beats -> 6, 16 -> 4).
    static func bars(lastBeat: Int) -> Int { max(4, lastBeat / beatsPerBar) }

    /// The phrase of every bar: the step-touch at the start, at the end and in the middle, a different move in between (never twice running, as many different ones as the pool allows).
    static func phrases(rank: ShowRank, lastBeat: Int, seed: UInt64) -> [ShowDanceMove] {
        let n = bars(lastBeat: lastBeat)
        let pool = ShowDanceMove.pool(lively: lively(rank))
        var h = seed &* 0x9E3779B97F4A7C15 &+ UInt64(rank.index)
        func next(_ k: Int) -> Int { h = h &* 6364136223846793005 &+ 1442695040888963407; return Int((h >> 33) % UInt64(k)) }
        var order = pool
        for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, next(i + 1)) }
        var out: [ShowDanceMove] = [], used = 0
        for i in 0..<n {
            let base = i == 0 || i == n - 1 || (i % 2 == 0 && i >= 2 && i <= n - 3)
            if base { out.append(.stepTouch); continue }
            var m = order[used % order.count]; used += 1
            if let last = out.last, last == m { m = order[used % order.count]; used += 1 }
            out.append(m)
        }
        return out
    }

    /// Step `j` (0...3) of a bar of `move`, in the body frame. `lively` widens the step-touch.
    static func spec(_ move: ShowDanceMove, j: Int, bar: Int, lively: Bool) -> DanceStepSpec {
        var s = DanceStepSpec()
        let alt = j & 1
        switch move {
        case .stepTouch:
            // L R R L (mirrored every other bar): out with the lead foot, the other closes, then back
            let d: Float = bar % 2 == 0 ? 1 : -1
            let lead = d > 0 ? 1 : 0
            // (each way 2a = 0.15 / 0.16 u, back to the centre every bar; the first bar has no beat-0 step, so the whole dance spans 3a = 0.225 / 0.24 u from his mark, inside the 0.3 limit)
            let a: Float = lively ? 0.08 : 0.075
            s.inPlace = false; s.peak = 0.085; s.sway = 0.12; s.bob = 0.07; s.rock = 0.3; s.lean = 0.12
            switch j {
            case 0: s.side = lead; s.rootD = SIMD2(d * a, 0); s.reach = SIMD2(d * a, 0)
            case 1: s.side = 1 - lead; s.rootD = SIMD2(d * a, 0)
            case 2: s.side = 1 - lead; s.rootD = SIMD2(-d * a, 0); s.reach = SIMD2(-d * a, 0)
            default: s.side = lead; s.rootD = SIMD2(-d * a, 0)
            }
        case .march:
            s.side = alt; s.peak = 0.095; s.sway = 0.06; s.bob = 0.09; s.rock = 0.3; s.pitch = -0.08          // (the proud strut's lift, which passes the feet tests)
        case .twist:
            s.side = alt; s.peak = 0.075; s.sway = 0.12; s.bob = 0.07; s.rock = 0.2; s.twist = 0.15
        case .twirl:
            s.side = alt; s.inPlace = false; s.dyaw = .pi / 2; s.peak = 0.075; s.sway = 0.03; s.bob = 0.06; s.rock = 0.1
        case .kickOut:
            s.side = alt; s.peak = 0.095; s.out = 2; s.sway = 0.16; s.bob = 0.08; s.rock = 0.2
        case .hopStep:
            s.side = alt; s.peak = 0.095; s.sway = 0.08; s.bob = 0.12; s.rock = 0.4
        }
        return s
    }
}

/// What the stage keeps while the dance runs (one per Show, the player's body).
nonisolated struct ShowDanceRun: Sendable {
    var phrases: [ShowDanceMove]
    var lively: Bool
    var period: Double, firstBeat: Double
    /// The beat whose step is launched next (steps plant on beats 1 ... bars * 4 - 1; beat 0 is GO itself).
    var nextBeat = 1
    var accentPending = false
    var finished = false
    var wasSwinging = false
    /// Debug / sync log: (song time of a plant, which foot, how far from the nearest beat in seconds, the move).
    var plants: [(t: Double, side: Int, err: Double, move: ShowDanceMove)] = []
    var totalBeats: Int { phrases.count * ShowDancePlan.beatsPerBar }
    var rate: Float { ShowDancePlan.rateFactor / Float(period) }
    /// Song time the step for `beat` starts: its plant is on the beat.
    func launchTime(beat: Int) -> Double { firstBeat + Double(beat) * period - Double(ShowDancePlan.swingFrac / rate) }
    func plantTime(beat: Int) -> Double { firstBeat + Double(beat) * period }
}

/// The body's side of a dance step: the step in flight and how his pose rides on it.
nonisolated struct DanceStepDrive: Sendable {
    var cur = DanceStepSpec()
    var accent = false
    var accentDone = true
}

extension BlobBrain {
    /// Begin the step `s` now (the stage decides the moment). False while a step is still in the air.
    @discardableResult
    func danceLaunch(_ s: DanceStepSpec, rate: Float, accent: Bool) -> Bool {
        guard danceDrive != nil, !feet.active, feetInit else { return false }
        nextSwing = s.side
        let a = amplitude
        // (the stomp lifts the foot higher, capped at 0.13: more than the strut's 0.095 by a third is as high as the join has been shown clean)
        startStep(rootD: rotXZ(s.rootD, yaw), dyaw: s.dyaw, reach: rotXZ(s.reach, yaw), peak: min(s.peak * (accent ? 1.6 : 1), 0.13) * a,
                  rate: rate, swingFrac: ShowDancePlan.swingFrac, inPlace: s.inPlace, outScale: s.out)
        danceDrive?.cur = s; danceDrive?.accent = accent; danceDrive?.accentDone = !accent
        return true
    }
    /// One fixed step of the dance at song time `now`: log a plant that just happened (how far from the beat), then start the next beat's step when its time comes.
    func danceStep(_ run: inout ShowDanceRun, now: Double) {
        let sw = feet.swinging
        if run.wasSwinging, !sw {
            let k = ((now - run.firstBeat) / run.period).rounded()
            let err = now - (run.firstBeat + k * run.period)
            let mv = run.phrases[min(max(Int(k) / ShowDancePlan.beatsPerBar, 0), run.phrases.count - 1)]
            run.plants.append((now, feet.side, err, mv))
            if AudioHub.audioLog { NSLog("[melon] dance plant beat=%d side=%d err=%+.0f ms move=%@", Int(k), feet.side, err * 1000, mv.rawValue) }
        }
        run.wasSwinging = sw
        let n = run.nextBeat
        guard n < run.totalBeats else { return }
        if now > run.plantTime(beat: n) + 0.12 { run.nextBeat += 1; return }          // (a late frame: that beat has gone by)
        if now >= run.launchTime(beat: n) {
            let spec = ShowDancePlan.spec(run.phrases[n / ShowDancePlan.beatsPerBar], j: n % ShowDancePlan.beatsPerBar, bar: n / ShowDancePlan.beatsPerBar, lively: run.lively)
            if danceLaunch(spec, rate: run.rate, accent: run.accentPending) { run.accentPending = false; run.nextBeat += 1 }
        }
    }
    /// Each tick of the dance's stepping script: the body pose that rides on the step.
    func danceTick() {
        guard let d = danceDrive else { return }
        let a = amplitude
        gaitPose(sway: d.cur.sway, bob: d.cur.bob, rock: d.cur.rock)
        armWalkWant = 1          // the arm nubs swing against the feet (the walk's counter-swing, driven by the stepping)
        guard feet.active else { armDirW = max(0, armDirW - runDt / 0.2); return }
        let side: Float = feet.side == 1 ? 1 : -1
        let env = sinf(.pi * feet.stepU)
        pitch += d.cur.pitch * a * env
        if d.cur.lean != 0 { roll = roll * 0.4 - (d.cur.rootD.x > 0 ? 1 : -1) * d.cur.lean * a * env }          // (into the step: toward the way he is going)
        if d.accent {          // the stomp: both arms pumped up with it
            armDirW = env
            for s in 0..<2 { armDirEl[s] = 0.5; armDirSa[s] = s == 0 ? 0.9 : -0.9 }
            armDirOut = 0
        } else if armDirW > 0 { armDirW = max(0, armDirW - runDt / 0.15) }
        if d.cur.twist != 0 { twist = d.cur.twist * side * env * a }
        if d.accent, !d.accentDone, !feet.swinging {          // the stomp: the plant lands with a jiggle and a little squash
            danceDrive?.accentDone = true
            jellyKick = max(jellyKick, 1.6)
            squash *= 0.96
        }
    }
}
