//
//  JellyStats.swift
//  What a Jelly is GOOD at, kept per Jelly (persisted under his id, like needs and dirt):
//    waddle  0...1  how fast he waddles when raced: the stride of each step and the quickest step rate he trains to (RaceTuning).
//    focus   0...1  how well he keeps his mind on the track: a low focus now and then stops him to look around (player and rivals alike).
//  `waddle` is seeded from his care the first time he is seen (fed, watered, loved Jellies start a little quicker); every race nudges it up a
//  little, a win the most. `focus` starts in the middle. Pure model: nothing here knows about bodies or the screen.
//

import Foundation
import Observation

/// Persistent "condition" of a Jelly (what he has been eating and wearing: for the beauty contest later). Each 0...1, decays slowly, capped.
nonisolated enum ConditionKey: Int, CaseIterable, Codable, Sendable {
    case cute, cool, sparkle, sweet, sporty
    var title: String { ["Cute", "Cool", "Sparkle", "Sweet", "Sporty"][rawValue] }
}

nonisolated enum ConditionTuning {
    /// Lost per real hour (0.01 = a full bar takes 4 days to fade).
    static let decayPerHour: Float = 0.01
    static let cap: Float = 1
}

nonisolated enum StatTuning {
    static let defaultsKey = "BlobStats.v1"
    static let seedFocus: Float = 0.5
    /// First-seen waddle: 0.30 (all needs empty) ... 0.65 (all full).
    static let seedBase: Float = 0.30, seedCare: Float = 0.35
    /// Waddle gained by a race, by place (1-based); more for winning. Capped at 1.
    static func waddleGain(place: Int) -> Float {
        switch place { case ...1: return 0.030; case 2: return 0.018; default: return 0.010 }
    }
    static func seedWaddle(careLevels: [Float]) -> Float {
        let m = careLevels.isEmpty ? 0.7 : careLevels.reduce(0, +) / Float(careLevels.count)
        return min(max(seedBase + seedCare * min(max(m, 0), 1), 0), 1)
    }
}

@MainActor
@Observable
final class JellyStats {
    private(set) var waddle: Float
    private(set) var focus: Float
    private(set) var races = 0
    private(set) var wins = 0
    /// The condition stats as last stored (use `condition(_:)`, which applies the decay since `condStamp`).
    @ObservationIgnored private var cond: [Float] = Array(repeating: 0, count: ConditionKey.allCases.count)
    @ObservationIgnored private var condStamp: Date
    /// Bumped on a change (UI).
    private(set) var conditionRevision = 0
    @ObservationIgnored private let now: () -> Date
    /// The calendar day as one number (DayClock.dayKey): Pep refills when it changes, not after 24 hours.
    @ObservationIgnored private let dayKey: () -> Int
    /// Practice sessions finished on `pepDay` (Pep: `TrainingTuning.fullSessions` a day at full value).
    @ObservationIgnored private var pepDay = 0
    @ObservationIgnored private var pepSessions = 0
    /// What he has learned to dance: 0...1 proficiency per dance (the beauty contest reads it).
    private(set) var dances: [DanceID: Float] = [:]
    private(set) var practices = 0
    /// Bumped on any training change (UI).
    private(set) var trainingRevision = 0

    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    nonisolated deinit {}

    /// `seedWaddle` is used only when nothing is saved under `key` yet.
    init(persists: Bool = true, defaults: UserDefaults = .standard, key: String = StatTuning.defaultsKey, seedWaddle: Float = 0.5, seedFocus: Float = StatTuning.seedFocus, now: @escaping () -> Date = Date.init, dayKey: (() -> Int)? = nil) {
        self.now = now; condStamp = now()
        self.dayKey = dayKey ?? { DayClock.shared.dayKey }
        self.persists = persists; self.defaults = defaults; self.key = key
        waddle = min(max(seedWaddle, 0), 1); focus = min(max(seedFocus, 0), 1)
        if persists, let a = defaults.array(forKey: key) as? [Double], a.count >= 4 {
            waddle = min(max(Float(a[0]), 0), 1); focus = min(max(Float(a[1]), 0), 1); races = Int(a[2]); wins = Int(a[3])
        } else if persists { save() }
        if persists, let c = defaults.array(forKey: key + ".cond") as? [Double], c.count == ConditionKey.allCases.count + 1 {
            cond = c.prefix(ConditionKey.allCases.count).map { min(max(Float($0), 0), 1) }
            condStamp = Date(timeIntervalSince1970: c[ConditionKey.allCases.count])
        }
        if persists, let t = defaults.array(forKey: key + ".train") as? [Double], t.count >= 3 {
            pepDay = Int(t[0]); pepSessions = Int(t[1]); practices = Int(t[2])
        }
        if persists, let dd = defaults.dictionary(forKey: key + ".dances") as? [String: Double] {
            for (k, v) in dd { if let id = DanceID(rawValue: k) { dances[id] = min(max(Float(v), 0), 1) } }
        }
    }

    // MARK: training (Pep, practice, dances)

    /// Practice sessions finished today (the day changes at midnight, whatever time has gone by).
    var sessionsToday: Int { dayKey() == pepDay ? pepSessions : 0 }
    /// Sessions left at full value today (the Pep pips).
    var pepLeft: Int { TrainingTuning.pepLeft(sessionsToday: sessionsToday) }
    var pepFactor: Float { TrainingTuning.pepFactor(sessionsToday: sessionsToday) }

    /// What a session of this accuracy / steadiness would add right now: (waddle, focus).
    func practiceGain(accuracy: Float, steadiness: Float) -> (waddle: Float, focus: Float) {
        let n = sessionsToday
        return (TrainingTuning.gain(stat: waddle, accuracy: accuracy, sessionsToday: n),
                TrainingTuning.gain(stat: focus, accuracy: steadiness * accuracy, sessionsToday: n, share: TrainingTuning.focusShare))
    }

    /// A drill is over: adds the gain to waddle and focus, uses one Pep. Returns what was added.
    @discardableResult
    func finishPractice(accuracy: Float, steadiness: Float) -> (waddle: Float, focus: Float) {
        let g = practiceGain(accuracy: accuracy, steadiness: steadiness)
        let (w0, f0) = (waddle, focus)
        waddle = min(1, waddle + g.waddle); focus = min(1, focus + g.focus)
        let today = dayKey()
        if pepDay != today { pepDay = today; pepSessions = 0 }
        pepSessions += 1; practices += 1
        trainingRevision += 1
        save(); saveTraining()
        return (waddle - w0, focus - f0)
    }

    func proficiency(_ d: DanceID) -> Float { dances[d] ?? 0 }
    var knownDances: [DanceID] { DanceID.allCases.filter { (dances[$0] ?? 0) > 0 } }
    /// Learning / practising a dance: raises its proficiency (capped at 1).
    func learn(_ d: DanceID, add: Float) {
        dances[d] = min(max((dances[d] ?? 0) + add, 0), 1)
        trainingRevision += 1
        saveTraining()
    }
    private func saveTraining() {
        guard persists else { return }
        defaults.set([Double(pepDay), Double(pepSessions), Double(practices)], forKey: key + ".train")
        defaults.set(Dictionary(uniqueKeysWithValues: dances.map { ($0.key.rawValue, Double($0.value)) }), forKey: key + ".dances")
    }

    // MARK: condition

    /// The stat now: the stored value less the slow decay since it was stored.
    func condition(_ k: ConditionKey) -> Float {
        let hours = Float(max(0, now().timeIntervalSince(condStamp)) / 3600)
        return min(max(cond[k.rawValue] - ConditionTuning.decayPerHour * hours, 0), ConditionTuning.cap)
    }
    /// Eating (or wearing) nudges the stats up by `d`; capped at 1. Everything first takes its decay so the stamp can move.
    func nudge(_ d: [ConditionKey: Float]) {
        let t = now()
        for k in ConditionKey.allCases { cond[k.rawValue] = condition(k) }
        condStamp = t
        for (k, v) in d { cond[k.rawValue] = min(max(cond[k.rawValue] + v, 0), ConditionTuning.cap) }
        conditionRevision += 1
        saveCondition()
    }
    private func saveCondition() {
        guard persists else { return }
        defaults.set(cond.map { Double($0) } + [condStamp.timeIntervalSince1970], forKey: key + ".cond")
    }

    func save() {
        guard persists else { return }
        defaults.set([Double(waddle), Double(focus), Double(races), Double(wins)], forKey: key)
    }

    /// Test / tuning hook.
    func set(waddle w: Float? = nil, focus f: Float? = nil) {
        if let w { waddle = min(max(w, 0), 1) }
        if let f { focus = min(max(f, 0), 1) }
        save()
    }

    /// A race is over: he placed `place` (1-based). Returns the waddle gained.
    @discardableResult
    func afterRace(place: Int) -> Float {
        let before = waddle
        waddle = min(1, waddle + StatTuning.waddleGain(place: place))
        races += 1
        if place == 1 { wins += 1 }
        save()
        return waddle - before
    }
}
