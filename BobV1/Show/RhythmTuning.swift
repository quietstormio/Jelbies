//
//  RhythmTuning.swift
//  The small shared types the Show, the Race, the Play assists and the music still use after training was removed (they used to live in Training/TrainingModel.swift):
//
//    DanceID          the dances a Jelly shows (Sway, Bop, Twirl).
//    CourseTier       the race courses.
//    TrainingTuning   the rhythm judging windows (Perfect / Good / Miss) and the audio latency offset every rhythm game reads.
//    DrillGrade       Perfect / Good / Miss.
//

import Foundation

/// Dances a Jelly can learn. Proficiency 0...1 lives on JellyStats; the Jelly Show's Dance round reads the one he shows. Each is built from an existing move: Sway sits and sways, Bop is the happy bounce, Twirl the tail spin.
nonisolated enum DanceID: String, CaseIterable, Codable, Sendable {
    case sway, bop, twirl
    var title: String { switch self { case .sway: return "Sway"; case .bop: return "Bop"; case .twirl: return "Twirl" } }
    /// The body move the dance is danced with.
    var move: IdleKind { switch self { case .sway: return .sway; case .bop: return .bounce; case .twirl: return .tail } }
    /// The starter dance.
    static let starter: DanceID = .sway
    /// A dance opens in the Studio once the one before it is known this well (the starter is always open).
    var opensAfter: (dance: DanceID, skill: Float)? { switch self { case .sway: return nil; case .bop: return (.sway, 0.5); case .twirl: return (.bop, 0.5) } }
    var blurb: String { switch self { case .sway: return "Sits and sways to the beat"; case .bop: return "Happy hops on the spot"; case .twirl: return "Spins after its own tail" } }
}

/// The course the Jelly races on (Race/RaceCourse.swift has the shapes). 
nonisolated enum CourseTier: String, CaseIterable, Codable, Sendable {
    case puddle, ripple, splash, wave, tsunami
    var title: String { switch self { case .puddle: return "Puddle"; case .ripple: return "Ripple"; case .splash: return "Splash"; case .wave: return "Wave"; case .tsunami: return "Tsunami" } }
    /// The class a racer is in on this course.
    var className: String { switch self { case .puddle: return "Starter"; case .ripple: return "Rookie"; case .splash: return "Pro"; case .wave: return "Champion"; case .tsunami: return "Legend" } }
    /// What the course is like, for the Track panel.
    var blurb: String {
        switch self {
        case .puddle: return "The straight. Tap left, right, left, right."
        case .ripple: return "Two gentle curves. Ease off a little in the bends."
        case .splash: return "S-bends, soft bumps and three low hurdles. Tap Jump just before each bar."
        case .wave: return "Tight turns, two hairpins and six hurdles. Slow down for the corners, jump the bars."
        case .tsunami: return "Hairpins and runs of hurdles, back to back. The big one."
        }
    }
    var index: Int { CourseTier.allCases.firstIndex(of: self) ?? 0 }
    /// The course below this one (nil for the Puddle).
    var below: CourseTier? { index > 0 ? CourseTier.allCases[index - 1] : nil }
    var above: CourseTier? { index + 1 < CourseTier.allCases.count ? CourseTier.allCases[index + 1] : nil }
}

nonisolated enum TrainingTuning {
    // MARK: judging
    /// |tap - beat| within this = Perfect / Good; anything up to `missWindow` is judged (Miss), farther away is a stray tap.
    static let perfectWindow = 0.060, goodWindow = 0.120, missWindow = 0.200
    /// Seconds between a tap's touch and the audio clock reading it (audio output + touch delay): the tap is judged at `songTime - latencyOffset`.
    static let latencyOffset = 0.040
}

nonisolated enum DrillGrade: Equatable, Sendable { case perfect, good, miss }
