//
//  EarsModels.swift
//  "Ears on": the sound kinds the Jellies react to, the frames the detector eats (one per classifier window or DSP frame) and the events it emits.
//  Pure data, no audio here. Everything runs on the phone: a frame is a handful of confidences, never audio.
//

import Foundation

/// What the Jellies can hear. `speech` is shown on the ear button only (no reaction).
nonisolated enum EarKind: String, CaseIterable, Sendable, Codable {
    case clap, snap, music, laugh, whistle, dogBark, doorbell, catMeow, babyCry, speech, loudBang

    /// SoundAnalysis built-in classifier (version 1) labels that count as this kind (checked against `knownClassifications` by a test).
    static let labels: [EarKind: [String]] = [
        .clap: ["clapping", "applause"],
        .snap: ["finger_snapping"],
        .music: ["music", "singing", "choir_singing", "drum", "drum_kit", "guitar", "piano", "synthesizer", "electric_guitar", "acoustic_guitar", "rapping"],
        .laugh: ["laughter", "giggling", "belly_laugh", "chuckle_chortle", "baby_laughter", "snicker"],
        .whistle: ["whistling"],
        .dogBark: ["dog_bark", "dog_bow_wow", "dog", "dog_howl", "dog_growl"],
        .doorbell: ["door_bell", "bicycle_bell", "chime", "knock"],
        .catMeow: ["cat_meow", "cat"],
        .babyCry: ["baby_crying", "crying_sobbing"],
        .speech: ["speech", "chatter"],
        .loudBang: ["boom", "door_slam", "thump_thud", "gunshot_gunfire", "glass_breaking", "firecracker", "fireworks", "thunder", "slap_smack"],
    ]
    /// Label -> kind (first kind that lists it).
    static let kindOf: [String: EarKind] = {
        var m: [String: EarKind] = [:]
        for k in EarKind.allCases { for l in labels[k] ?? [] where m[l] == nil { m[l] = k } }
        return m
    }()

    /// The small icon on the ear button while this is heard.
    var symbol: String {
        switch self {
        case .clap, .snap: return "hands.clap.fill"
        case .music: return "music.note"
        case .laugh: return "face.smiling.inverse"
        case .whistle: return "wind"
        case .dogBark: return "dog.fill"
        case .doorbell: return "bell.fill"
        case .catMeow: return "cat.fill"
        case .babyCry: return "figure.and.child.holdinghands"
        case .speech: return "bubble.left.fill"
        case .loudBang: return "exclamationmark.triangle.fill"
        }
    }
    var title: String {
        switch self {
        case .clap: return "Clap"; case .snap: return "Snap"; case .music: return "Music"; case .laugh: return "Laughter"; case .whistle: return "Whistle"
        case .dogBark: return "Dog"; case .doorbell: return "Doorbell"; case .catMeow: return "Cat"; case .babyCry: return "Baby"; case .speech: return "Talking"; case .loudBang: return "Bang"
        }
    }
}

/// One detector input: the classifier's confidences per kind for the window that ENDED at `time`, the level then, and how loud the app's own music
/// is on the speaker (0 = silent; the music exclusion reads it).
nonisolated struct EarsFrame: Sendable, Equatable {
    var time: Double
    var scores: [EarKind: Float] = [:]
    var rms: Float = 0
    var appMusic: Float = 0
    init(time: Double, scores: [EarKind: Float] = [:], rms: Float = 0, appMusic: Float = 0) {
        self.time = time; self.scores = scores; self.rms = rms; self.appMusic = appMusic
    }
    subscript(_ k: EarKind) -> Float { scores[k] ?? 0 }
}

/// A sharp attack the DSP found: when, how strong (relative to the recent envelope), how noise-like (spectral flatness 0...1; claps are broadband).
nonisolated struct EarOnset: Sendable, Equatable {
    var time: Double
    var strength: Float
    var flatness: Float
}

/// A beat estimate: tempo and the time of one beat (`anchor`); beat k is at `anchor + k * 60 / bpm`.
nonisolated struct EarBeat: Sendable, Equatable {
    var bpm: Float
    var anchor: Double
    /// Periodicity ratio (autocorrelation peak over the band mean); larger = clearer beat.
    var strength: Float
    var period: Double { 60 / Double(bpm) }
    /// 0...1 position in the current beat at `t` (0 = on the beat) and the beat index.
    func phase(at t: Double) -> (phase: Double, index: Int) {
        let u = (t - anchor) / period
        let f = floor(u)
        return (u - f, Int(f))
    }
    /// The next beat at or after `t`.
    func nextBeat(after t: Double) -> Double { anchor + ceil((t - anchor) / period - 1e-6) * period }
}

/// What the detector decided.
nonisolated enum EarEvent: Equatable, Sendable {
    /// One clap (or a snap), laugh, whistle, bark, doorbell, meow, cry.
    case heard(EarKind)
    /// Two claps within a second: everyone comes.
    case doubleClap
    /// A loud bang; `level` 0...1 (the RMS at the spike). Very loud (>= `EarsTuning.veryLoud`) wakes sleepers.
    case bang(level: Float)
    /// External music has been going for `EarsTuning.musicHold` seconds. `beat` is nil until the tempo tracker has one.
    case musicStarted(EarBeat?)
    /// A fresh tempo / phase estimate while music plays.
    case musicBeat(EarBeat)
    /// The music has been gone for `EarsTuning.musicRelease` seconds.
    case musicStopped
}

nonisolated enum EarsTuning {
    /// Classifier confidence that switches a kind ON / OFF (hysteresis).
    static let on: [EarKind: Float] = [.clap: 0.45, .snap: 0.45, .music: 0.55, .laugh: 0.5, .whistle: 0.5, .dogBark: 0.5, .doorbell: 0.5, .catMeow: 0.5, .babyCry: 0.55, .speech: 0.5, .loudBang: 0.5]
    static let off: [EarKind: Float] = [.clap: 0.25, .snap: 0.25, .music: 0.3, .laugh: 0.3, .whistle: 0.3, .dogBark: 0.3, .doorbell: 0.3, .catMeow: 0.3, .babyCry: 0.35, .speech: 0.3, .loudBang: 0.3]
    /// Consecutive frames at or above `on` before a kind counts (transients: 1; the steady kinds: 2).
    static func onFrames(_ k: EarKind) -> Int { switch k { case .clap, .snap, .loudBang, .doorbell, .dogBark: return 1; default: return 2 } }
    /// Seconds after an event of this kind before the same kind fires again.
    static let cooldown: [EarKind: Double] = [.clap: 2.5, .snap: 2.5, .laugh: 6, .whistle: 8, .dogBark: 6, .doorbell: 8, .catMeow: 6, .babyCry: 15, .loudBang: 6, .speech: 0, .music: 0]
    static let doubleClapCooldown: Double = 8
    /// Two claps count as a double when this close; a single clap waits `clapDecide` for its partner before it fires.
    static let doubleClapWindow: Double = 1.0
    static let clapDecide: Double = 0.55
    /// DSP onsets closer than this to a clap window's end are the claps of that window.
    static let clapOnsetLookback: Double = 0.9
    /// Music must hold this long before the dance starts, and be gone this long before it stops (short dips are bridged by `musicGap`).
    static let musicHold: Double = 4
    static let musicRelease: Double = 3
    static let musicGap: Double = 1.5
    /// App-music exclusion: while the app's own music is audible, a music frame counts only when its confidence beats the learned baseline by
    /// `appMusicMargin` (and at least `appMusicFloor`). The baseline is an EMA of what the classifier says about the app's own music.
    static let appMusicFloor: Float = 0.75
    static let appMusicMargin: Float = 0.25
    static let appMusicBaselineStart: Float = 0.55
    static let appMusicAudible: Float = 0.04
    /// RMS (linear) of a loud bang and of a VERY loud one (wakes a napping Jelly).
    static let bangRms: Float = 0.35
    static let bangRatio: Float = 4
    static let veryLoud: Float = 0.7
    /// Transient kinds are ignored this long after the app played a sound effect (its jumps and boops read as claps).
    static let appSoundMask: Double = 0.3
    /// The ear button keeps showing a kind this long after it was last heard.
    static let hearingHold: Double = 1.4
}
