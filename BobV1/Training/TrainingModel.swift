//
//  TrainingModel.swift
//  Practice on the track ("Rhythm Steps"): the rules as pure models (no bodies, no screen, no audio), so they run headless in tests.
//
//    TrainingTuning   the beat grid of the training music (BAKED from music_pick/picks.json), the judging windows, laps, and the stat gain formula.
//    BeatGrid         beat n of the music happens at `firstBeat + n * period` seconds of song time.
//    DrillSim         one drill: L / R prompts on the beat grid, each judged Perfect / Good / Miss from the tap's SONG time (the audio clock).
//    DanceID          the dances a Jelly can learn (the beauty contest reads `JellyStats.dances` later).
//
//  Practising is the way a Jelly gets better at racing (like teaching a Nintendogs puppy to catch frisbees): a new Jelly trips and looks around a
//  lot, a trained one almost never. Drops are NOT earned here, only in competitions.
//

import Foundation

/// Dances a Jelly can learn. Proficiency 0...1 lives on JellyStats (nothing teaches one yet; the shape is here for the beauty contest).
nonisolated enum DanceID: String, CaseIterable, Codable, Sendable {
    case sway
    var title: String { switch self { case .sway: return "Sway" } }
}

/// The course the Jelly trains / races on. Only the first exists yet.
nonisolated enum CourseTier: String, CaseIterable, Codable, Sendable {
    case puddle
    var title: String { switch self { case .puddle: return "Puddle" } }
}

nonisolated enum TrainingTuning {
    // MARK: the training music (training_1.m4a; from picks.json, measured on the 44.1 kHz decode, m4a priming skipped)
    static let bpm = 115.0
    /// Seconds of song time of beat 0.
    static let firstBeat = 0.279
    static let period = 60.0 / bpm
    static let sampleRate = 44100.0
    /// The loop (sample frames at 44.1 kHz): 20 bars = 80 beats, bar-aligned, on zero crossings.
    static let loopStartFrame = 587_500, loopEndFrame = 2_428_235
    static var loopStart: Double { Double(loopStartFrame) / sampleRate }
    static var loopEnd: Double { Double(loopEndFrame) / sampleRate }

    // MARK: judging
    /// |tap - beat| within this = Perfect / Good; anything up to `missWindow` is judged (Miss), farther away is a stray tap.
    static let perfectWindow = 0.060, goodWindow = 0.120, missWindow = 0.200
    /// Seconds between a tap's touch and the audio clock reading it (audio output + touch delay): the tap is judged at `songTime - latencyOffset`.
    static let latencyOffset = 0.040
    /// Prompts are drawn this many beats before they arrive.
    static let visibleBeats = 5

    // MARK: course
    static let laps = 3
    static let promptsPerLap = 32
    /// Beats from GO to the first prompt, and of rest between laps (the lap dip happens in it).
    static let leadInBeats = 4, restBeats = 4
    /// Laps 2 and 3 leave a beat out now and then (a rest), never two in a row.
    static let restChance: [Float] = [0, 0.12, 0.2]
    /// Seconds of stumble after a miss (shorter than the race's, the beat is slow).
    static let stumbleTime: Float = 0.45

    // MARK: gain
    /// Waddle per full-accuracy session at stat 0 with Pep. Focus gets `focusShare` of it.
    static let baseGain: Float = 0.14
    static let focusShare: Float = 0.45
    /// Gains shrink as the stat grows: 0.2 -> 0.4 takes ~3 sessions, 0.8 -> 0.9 about a dozen.
    static func diminishing(_ stat: Float) -> Float { powf(max(0, 1 - min(max(stat, 0), 1)), 1.5) }
    /// Sessions a day at full value, and what later ones are worth.
    static let fullSessions = 3
    static let spentFactor: Float = 0.25
    static func pepFactor(sessionsToday: Int) -> Float { sessionsToday < fullSessions ? 1 : spentFactor }
    static func pepLeft(sessionsToday: Int) -> Int { max(0, fullSessions - sessionsToday) }
    /// Gain = base x accuracy x diminishing(stat) x pep.
    static func gain(stat: Float, accuracy: Float, sessionsToday: Int, share: Float = 1) -> Float {
        baseGain * share * min(max(accuracy, 0), 1) * diminishing(stat) * pepFactor(sessionsToday: sessionsToday)
    }
}

/// The beat grid of the training music.
nonisolated enum BeatGrid {
    static func time(ofBeat n: Int) -> Double { TrainingTuning.firstBeat + Double(n) * TrainingTuning.period }
    /// The first beat at or after song time `t`.
    static func beat(atOrAfter t: Double) -> Int { Int(((t - TrainingTuning.firstBeat) / TrainingTuning.period).rounded(.up)) }
    /// Where `t` is between beats: 0 on a beat, up to <1.
    static func phase(of t: Double) -> Double {
        let x = (t - TrainingTuning.firstBeat) / TrainingTuning.period
        return x - x.rounded(.down)
    }
}

nonisolated enum DrillGrade: Equatable, Sendable { case perfect, good, miss }

nonisolated struct DrillPrompt: Equatable, Sendable {
    var index: Int
    var lap: Int
    /// 0 = left, 1 = right.
    var foot: Int
    var beat: Int
    var time: Double { BeatGrid.time(ofBeat: beat) }
    var grade: DrillGrade?
}

nonisolated enum DrillEvent: Equatable, Sendable {
    /// A good hit: the Jelly steps with `foot`.
    case hit(index: Int, foot: Int, grade: DrillGrade)
    /// A miss (wrong foot, off the beat, or no tap): the Jelly trips.
    case miss(index: Int, foot: Int, late: Bool)
    case streak(Int)
    case stray
    /// The last prompt of a lap is judged (the lap dip starts when the rest begins).
    case lapEnd(lap: Int)
    case lapStart(lap: Int)
    case finished
}

/// One drill. Time only moves when `tick(songTime:)` is called (the audio clock, or a stand-in).
nonisolated struct DrillSim: Sendable {
    private(set) var prompts: [DrillPrompt] = []
    private(set) var songTime: Double
    private(set) var perfects = 0, goods = 0, misses = 0, strays = 0
    private(set) var streak = 0, bestStreak = 0
    /// 1-based lap of the next unjudged prompt.
    private(set) var lap = 1
    private(set) var events: [DrillEvent] = []
    private(set) var finished = false
    private var lapEnded: Set<Int> = []
    private var lapStarted: Set<Int> = [1]
    let seed: UInt64

    var total: Int { prompts.count }
    var judged: Int { perfects + goods + misses }
    /// Perfect = 1, Good = 0.6, minus a little for stray taps (mashing).
    var accuracy: Float {
        guard total > 0 else { return 0 }
        let a = (Float(perfects) + 0.6 * Float(goods) - 0.5 * Float(strays)) / Float(total)
        return min(max(a, 0), 1)
    }
    /// How much of the drill was spent in streaks (best streak over the prompts): feeds Focus.
    var steadiness: Float { total > 0 ? Float(bestStreak) / Float(total) : 0 }

    /// `songTime`: song time at GO. The first prompt is `leadInBeats` after it, on the beat grid.
    init(seed: UInt64, songTime: Double) {
        self.seed = seed; self.songTime = songTime
        var rng = RaceRNG(seed: seed &* 0x9E3779B97F4A7C15 &+ 0xD81)
        var beat = BeatGrid.beat(atOrAfter: songTime + Double(TrainingTuning.leadInBeats) * TrainingTuning.period)
        var foot = Int(rng.next() * 2) % 2
        for lap in 1...TrainingTuning.laps {
            var i = 0, rested = true
            while i < TrainingTuning.promptsPerLap {
                if !rested, rng.next() < TrainingTuning.restChance[min(lap - 1, TrainingTuning.restChance.count - 1)] { beat += 1; rested = true; continue }
                prompts.append(DrillPrompt(index: prompts.count, lap: lap, foot: foot, beat: beat))
                foot = 1 - foot; beat += 1; i += 1; rested = false
            }
            beat += TrainingTuning.restBeats
        }
    }

    mutating func takeEvents() -> [DrillEvent] { let e = events; events.removeAll(keepingCapacity: true); return e }

    /// The song time the tap is judged at.
    private var judgedTime: Double { songTime - TrainingTuning.latencyOffset }

    /// Song time of the last prompt (the end of the drill).
    var endTime: Double { (prompts.last?.time ?? songTime) + TrainingTuning.goodWindow }
    /// Prompts still to come that are on screen: (index, beats ahead of now) for the view.
    func visible(at t: Double? = nil) -> [(prompt: DrillPrompt, ahead: Double)] {
        let now = (t ?? songTime) - TrainingTuning.latencyOffset
        let span = Double(TrainingTuning.visibleBeats) * TrainingTuning.period
        return prompts.filter { $0.grade == nil && $0.time - now < span && $0.time - now > -TrainingTuning.goodWindow - 0.05 }.map { ($0, ($0.time - now) / TrainingTuning.period) }
    }

    mutating func tick(songTime t: Double) {
        guard !finished else { return }
        songTime = max(songTime, t)
        // prompts nobody tapped in time
        for i in prompts.indices where prompts[i].grade == nil && judgedTime > prompts[i].time + TrainingTuning.goodWindow {
            judge(i, .miss, late: true)
        }
        // lap bookkeeping
        if let next = prompts.first(where: { $0.grade == nil }) {
            if next.lap != lap { lap = next.lap }
            if judgedTime >= next.time - Double(TrainingTuning.visibleBeats) * TrainingTuning.period, lapStarted.insert(next.lap).inserted { events.append(.lapStart(lap: next.lap)) }
        } else if !finished {
            finished = true
            events.append(.finished)
        }
    }

    /// A tap of foot 0 / 1 at song time `t` (the clock moves to it first).
    mutating func tap(foot: Int, at t: Double) {
        guard !finished else { return }
        tick(songTime: t)
        tap(foot: foot)
    }

    /// A tap of foot 0 / 1 at the current song time.
    mutating func tap(foot: Int) {
        guard !finished else { return }
        let f = foot == 0 ? 0 : 1
        let now = judgedTime
        var best: Int?
        for i in prompts.indices where prompts[i].grade == nil {
            let d = abs(prompts[i].time - now)
            if d <= TrainingTuning.missWindow, best == nil || d < abs(prompts[best!].time - now) { best = i }
            if prompts[i].time - now > TrainingTuning.missWindow { break }
        }
        guard let i = best else { strays += 1; events.append(.stray); return }
        let err = abs(prompts[i].time - now)
        if prompts[i].foot != f { judge(i, .miss, late: false); return }
        if err <= TrainingTuning.perfectWindow { judge(i, .perfect, late: false) }
        else if err <= TrainingTuning.goodWindow { judge(i, .good, late: false) }
        else { judge(i, .miss, late: now > prompts[i].time) }
    }

    private mutating func judge(_ i: Int, _ g: DrillGrade, late: Bool) {
        prompts[i].grade = g
        let p = prompts[i]
        switch g {
        case .perfect: perfects += 1; streak += 1
        case .good: goods += 1; streak += 1
        case .miss: misses += 1; streak = 0
        }
        bestStreak = max(bestStreak, streak)
        if g == .miss { events.append(.miss(index: i, foot: p.foot, late: late)) }
        else {
            events.append(.hit(index: i, foot: p.foot, grade: g))
            if streak > 0, streak % 8 == 0 { events.append(.streak(streak)) }
        }
        let lastOfLap = !prompts.contains { $0.lap == p.lap && $0.grade == nil }
        if lastOfLap, lapEnded.insert(p.lap).inserted { events.append(.lapEnd(lap: p.lap)) }
        if judged == total, !finished { finished = true; events.append(.finished) }
    }
}
