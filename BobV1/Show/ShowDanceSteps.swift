//
//  ShowDanceSteps.swift
//  The Jelly Show's Dance round on his feet: he stands the whole song and STEPS with the prompts. Every L / R prompt is a step of that foot that lands on the prompt's
//  beat (so a press on the beat is the foot coming down), and the beats between the prompts are filled with steps of the other foot, so he never stops stepping
//  (a missed prompt still gets its step). A press that no step answers (off the beat) starts a quick step of that foot at once.
//
//  The plan is one four-beat phrase (a bar) at a time: the side step-touch (the body sways onto the standing foot, a lean into it) is the base he always
//  comes back to, and between the bases come other phrases (march, twist step, twirl, kick out, hop step), never the same one twice running, the gentle ones on
//  the calm songs (Puddle / Pond) and the energetic ones added on the lively songs (Lagoon / Ocean). Every step goes through the normal foot code
//  (`startStep` + `gaitPose`, the same as the walk's and the step-in-place idle's).
//
//  The Perfect accent is a stomp on the next step. A Miss never stops the stepping. He ends with feet together, facing front.
//

import Foundation
import simd

nonisolated enum ShowDanceMove: String, CaseIterable, Sendable {
    case stepTouch      // side step-touch: the body sways onto the standing foot with every step; the base step
    case march          // high-knee march on the spot, chest out
    case twist          // step on the spot with the belly twisting toward the stepping foot, a loose sway
    case twirl          // steps round on the spot: a full turn per bar
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
    var rootD = SIMD2<Float>.zero                                     // (world x / z shift of the body over the step)
    var dyaw: Float = 0
    var peak: Float = 0.07                                            // foot lift (u, before the amplitude)
    var out: Float = 1                                                // sideways swing of the swing foot
    var inPlace = true
    var sway: Float = 0.08, bob: Float = 0.03, rock: Float = 0.3
    var twist: Float = 0, pitch: Float = 0
    var lean: Float = 0                                               // lean into the direction of travel (rad)
}

/// A step of the schedule: the foot plants at song time `plant`; the step lasts `st` seconds (its foot leaves the floor at `plant - swingFrac * st`).
nonisolated struct ScheduledDanceStep: Sendable {
    var plant: Double
    var side: Int
    var bar: Int
    var j = 0, n = 1                     // the step's place among the `n` steps of its bar
    var st: Float = 0.5
    var prompt = false
}

nonisolated enum ShowDancePlan {
    static let beatsPerBar = 4
    /// The foot plants this far (of its step time) after the step starts (`startStep`'s swing fraction).
    static let swingFrac: Float = 0.8
    static let rateFactor: Float = 1.08
    static let minStep: Float = 0.15
    static func lively(_ rank: ShowRank) -> Bool { rank.index >= ShowRank.lagoon.index }
    /// Bars in the round: the song's last prompt beat in whole bars (24 beats -> 6, 16 -> 4).
    static func bars(lastBeat: Int) -> Int { max(4, lastBeat / beatsPerBar) }
    /// Which of his feet a prompt's L / R is: the Left button is the foot drawn on the screen's left (foot index 0 on the stage camera, checked in the real app), Right the one on the right.
    static func side(forFoot foot: Int) -> Int { foot }

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

    /// Every step of the round in time order: a step for each prompt (`prompts`: song time and which foot, as in `side(forFoot:)`), and a step on every other beat (the foot opposite
    /// the one before) so the stepping never stops. Each step's length fits between the one before and its own plant.
    static func schedule(period: Double, firstBeat: Double, bars: Int, prompts: [(time: Double, side: Int)]) -> [ScheduledDanceStep] {
        let total = bars * beatsPerBar
        let end = firstBeat + Double(total) * period
        var raw: [(t: Double, side: Int?, prompt: Bool)] = prompts.filter { $0.time > firstBeat + 0.2 * period && $0.time <= end + 0.01 }.map { ($0.time, $0.side, true) }
        for n in 1..<max(total, 1) {
            let t = firstBeat + Double(n) * period
            if !raw.contains(where: { $0.prompt && abs($0.t - t) < 0.2 }) { raw.append((t, nil, false)) }
        }
        raw.sort { $0.t < $1.t }
        var out: [ScheduledDanceStep] = []
        var prevSide = 1, prevSt: Float = 0, prevT: Double = -1
        for r in raw {
            let side = r.side ?? (1 - prevSide)
            var st = Float(period) / rateFactor
            if prevT >= 0 { st = min(st, (Float(r.t - prevT) - 0.2 * prevSt) / swingFrac) }
            if st < minStep { continue }
            let bar = min(max(Int(((r.t - firstBeat) / period - 0.001) / Double(beatsPerBar)), 0), bars - 1)
            out.append(ScheduledDanceStep(plant: r.t, side: side, bar: bar, st: st, prompt: r.prompt))
            prevSide = side; prevSt = st; prevT = r.t
        }
        // the place of each step in its bar
        var i = 0
        while i < out.count {
            var k = i
            while k < out.count, out[k].bar == out[i].bar { k += 1 }
            for q in i..<k { out[q].j = q - i; out[q].n = k - i }
            i = k
        }
        return out
    }

    /// The step `s` of `move`: `off` is how far the body is from its mark now (world x), `yaw` its heading.
    static func spec(_ move: ShowDanceMove, step s: ScheduledDanceStep, off: Float, yaw: Float, lively: Bool, final: Bool) -> DanceStepSpec {
        var p = DanceStepSpec()
        p.side = s.side
        let toMark = SIMD2<Float>(-off * 0.5, 0)
        switch move {
        case .stepTouch:
            // the body sways onto the standing foot (the stepping foot's side swings free): about 0.16 u across, a lean into it
            let b: Float = lively ? 0.09 : 0.08
            let target = s.side == 1 ? -b : b
            p.rootD = SIMD2(target - off, 0); p.inPlace = false
            p.peak = 0.085; p.sway = 0.12; p.bob = 0.07; p.rock = 0.3; p.lean = 0.10
        case .march:
            p.rootD = toMark; p.peak = 0.095; p.sway = 0.06; p.bob = 0.09; p.rock = 0.3; p.pitch = -0.08
        case .twist:
            p.rootD = toMark; p.peak = 0.075; p.sway = 0.12; p.bob = 0.07; p.rock = 0.2; p.twist = 0.15
        case .twirl:
            p.rootD = toMark; p.dyaw = 2 * .pi / Float(max(s.n, 1)); p.peak = 0.075; p.sway = 0.03; p.bob = 0.06; p.rock = 0.1
        case .kickOut:
            p.rootD = toMark; p.peak = 0.095; p.out = 2; p.sway = 0.16; p.bob = 0.08; p.rock = 0.2
        case .hopStep:
            p.rootD = toMark; p.peak = 0.095; p.sway = 0.08; p.bob = 0.12; p.rock = 0.4
        }
        if move != .twirl {
            // square up to the front a little with every step (a twirl cut short, the last bar)
            let e = wrapAngle(0 - yaw)
            p.dyaw = max(-0.5, min(0.5, e * (final ? 0.9 : 0.35)))
        }
        if abs(p.rootD.x) > 0.004 || abs(p.dyaw) > 0.004 { p.inPlace = false }
        // a quick step (a half beat) lifts less
        p.peak *= max(0.6, min(1, s.st / 0.45))
        return p
    }
}

/// What the stage keeps while the dance runs (one per Show, the player's body).
nonisolated struct ShowDanceRun: Sendable {
    var phrases: [ShowDanceMove]
    var lively: Bool
    var period: Double, firstBeat: Double
    var schedule: [ScheduledDanceStep]
    /// The step of the schedule to start next.
    var nextIndex = 0
    var mark: SIMD2<Float>?
    var accentPending = false
    /// A press waiting for an answer: which foot, the song time, and whether a step already answered it.
    var press: (side: Int, t: Double)?
    var finished = false
    var wasSwinging = false
    var launched: [(plant: Double, side: Int)] = []
    /// Debug / sync log: (song time of a plant, which foot, how far from the nearest half beat in seconds, the move).
    var plants: [(t: Double, side: Int, err: Double, move: ShowDanceMove)] = []

    init(phrases: [ShowDanceMove], lively: Bool, period: Double, firstBeat: Double, prompts: [(time: Double, side: Int)] = []) {
        self.phrases = phrases; self.lively = lively; self.period = period; self.firstBeat = firstBeat
        schedule = ShowDancePlan.schedule(period: period, firstBeat: firstBeat, bars: phrases.count, prompts: prompts)
    }
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
    func danceLaunch(_ s: DanceStepSpec, st: Float, accent: Bool) -> Bool {
        guard danceDrive != nil, !feet.active, feetInit else { return false }
        nextSwing = s.side
        let a = amplitude
        // (the stomp lifts the foot higher, capped at 0.13: more than the strut's 0.095 by a third is as high as the join has been shown clean)
        startStep(rootD: rotXZ(s.rootD, yaw), dyaw: s.dyaw, reach: .zero, peak: min(s.peak * (accent ? 1.6 : 1), 0.13) * a,
                  rate: 1 / st, swingFrac: ShowDancePlan.swingFrac, inPlace: s.inPlace, outScale: s.out)
        danceDrive?.cur = s; danceDrive?.accent = accent; danceDrive?.accentDone = !accent
        return true
    }
    /// One fixed step of the dance at song time `now`: log a plant that just happened, start the next scheduled step when its time comes, answer a press nothing has answered.
    func danceStep(_ run: inout ShowDanceRun, now: Double) {
        if run.mark == nil { run.mark = position }
        let sw = feet.swinging
        if run.wasSwinging, !sw {
            let half = run.period / 2
            let k = ((now - run.firstBeat) / half).rounded()
            let err = now - (run.firstBeat + k * half)
            let bar = min(max(Int(k / 2) / ShowDancePlan.beatsPerBar, 0), run.phrases.count - 1)
            run.plants.append((now, feet.side, err, run.phrases[bar]))
            if AudioHub.audioLog { NSLog("[melon] dance plant beat=%.1f side=%d err=%+.0f ms move=%@", k / 2, feet.side, err * 1000, run.phrases[bar].rawValue) }
        }
        run.wasSwinging = sw
        let off = position.x - (run.mark?.x ?? position.x)
        let last = run.nextIndex >= run.schedule.count - 1
        if run.nextIndex < run.schedule.count {
            let s = run.schedule[run.nextIndex]
            if now > s.plant + 0.12 { run.nextIndex += 1 }          // (a late frame: that step's moment has gone by)
            else if now >= s.plant - Double(ShowDancePlan.swingFrac * s.st) {
                let spec = ShowDancePlan.spec(run.phrases[s.bar], step: s, off: off, yaw: yaw, lively: run.lively, final: last || s.bar == run.phrases.count - 1)
                if danceLaunch(spec, st: s.st, accent: run.accentPending) { run.accentPending = false; run.launched.append((s.plant, s.side)); run.nextIndex += 1 }
            }
        }
        // a press that no step is answering (off the beat): a quick step of that foot now
        if let p = run.press {
            let answered = run.launched.contains { $0.side == p.side && $0.plant > p.t - 0.25 && $0.plant < p.t + 0.3 }
            if answered || now - p.t > 0.3 { run.press = nil }
            else if !feet.active {
                var q = DanceStepDrive().cur
                q.side = p.side; q.peak = 0.075; q.sway = 0.1; q.bob = 0.06
                if danceLaunch(q, st: 0.22, accent: run.accentPending) { run.accentPending = false; run.launched.append((now + 0.18, p.side)); run.press = nil }
            }
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
