//
//  AudioCatalog.swift
//  Names of the bundled sounds (BobV1/Audio/Resources, AAC .m4a), the pure settings model and the mixing constants.
//

import Foundation

nonisolated enum SFX: String, CaseIterable, Sendable {
    case squish, boop, wobble, footstep, zoomies, jump, chomp, slurp, setdown, splash, soapbubbles, bubblepop
    case lintroller, sparkle, snore, uitap, uiconfirm, coin, select

    /// Loudness of the clip in the mix (the files themselves are peak-normalised per category).
    var gain: Float {
        switch self {
        case .footstep: return 0.45
        case .snore: return 0.175           // was 0.5: "the snoring is too loud" (0.35x)
        case .slurp: return 0.51            // was 0.85 (default): 0.6x, "a little more quiet"
        case .squish, .boop, .wobble: return 0.8
        case .uitap: return 0.6
        case .soapbubbles, .lintroller: return 0.7
        default: return 0.85
        }
    }
    /// Shortest gap between two plays of the same effect.
    var minGap: Double {
        switch self {
        case .footstep: return 0.2
        case .squish, .boop, .wobble: return 0.16
        case .chomp, .slurp: return 0.25
        case .soapbubbles, .lintroller, .splash: return 0.45
        case .bubblepop: return 0.07
        case .uitap, .uiconfirm: return 0.06
        default: return 0.1
        }
    }
}

nonisolated enum JellyVoice: String, Sendable { case happy, sad, babble }

nonisolated enum AudioMix {
    static let music: Float = 0.5
    static let ambience: Float = 0.34
    static let sfxMaster: Float = 1
    static let crossfade: Double = 3
}

/// Music and Sound Effects, separately on/off with a volume each. Persisted in UserDefaults; `-Mute 1` (and the test host) silences everything.
nonisolated struct AudioSettings: Equatable, Sendable {
    var musicOn = true, sfxOn = true
    var musicVolume: Float = 0.8, sfxVolume: Float = 0.9

    static let keys = (musicOn: "Audio.musicOn", sfxOn: "Audio.sfxOn", musicVolume: "Audio.musicVolume", sfxVolume: "Audio.sfxVolume")

    init() {}
    init(defaults d: UserDefaults) {
        if d.object(forKey: Self.keys.musicOn) != nil { musicOn = d.bool(forKey: Self.keys.musicOn) }
        if d.object(forKey: Self.keys.sfxOn) != nil { sfxOn = d.bool(forKey: Self.keys.sfxOn) }
        if d.object(forKey: Self.keys.musicVolume) != nil { musicVolume = min(max(Float(d.double(forKey: Self.keys.musicVolume)), 0), 1) }
        if d.object(forKey: Self.keys.sfxVolume) != nil { sfxVolume = min(max(Float(d.double(forKey: Self.keys.sfxVolume)), 0), 1) }
    }
    func save(to d: UserDefaults) {
        d.set(musicOn, forKey: Self.keys.musicOn); d.set(sfxOn, forKey: Self.keys.sfxOn)
        d.set(Double(musicVolume), forKey: Self.keys.musicVolume); d.set(Double(sfxVolume), forKey: Self.keys.sfxVolume)
    }
    var musicLevel: Float { musicOn ? musicVolume : 0 }
    var sfxLevel: Float { sfxOn ? sfxVolume : 0 }
}

/// A level that ramps linearly toward a target at a fixed rate (1 / seconds for a full swing).
nonisolated struct Fader: Equatable, Sendable {
    var level: Float = 0, target: Float = 0, seconds: Float = 1
    mutating func ramp(to t: Float, over s: Double) { target = t; seconds = Float(max(s, 0.01)) }
    mutating func snap(_ v: Float) { level = v; target = v }
    mutating func update(dt: Double) {
        let step = Float(dt) / seconds
        if level < target { level = min(target, level + step) } else if level > target { level = max(target, level - step) }
    }
}

/// When the sleeping Jellies snore: one snore per Jelly every 6...10 s at most, and never two Jellies within `hubGap` of each other
/// (a later one waits its turn). Pure: the hub feeds it the clock and a random source; tests drive it directly.
nonisolated struct SnoreScheduler: Sendable {
    static let interval: ClosedRange<Double> = 6...10
    static let firstDelay: ClosedRange<Double> = 2...5
    static let hubGap: Double = 2.5
    private(set) var next: [Double] = [0, 0, 0]
    private(set) var lastAny: Double = -100

    /// The Jellies that snore now (`now` seconds; `napping[i]` = asleep).
    mutating func due(napping: [Bool], now: Double, random: (ClosedRange<Double>) -> Double) -> [Int] {
        var out: [Int] = []
        for i in napping.indices where i < next.count {
            guard napping[i] else { next[i] = 0; continue }
            if next[i] == 0 { next[i] = now + random(Self.firstDelay) + Double(i) * 1.3 }       // (staggered, so a pile does not start together)
            guard now >= next[i] else { continue }
            if now - lastAny < Self.hubGap { next[i] = lastAny + Self.hubGap + random(0.2...1.0); continue }
            next[i] = now + random(Self.interval)
            lastAny = now
            out.append(i)
        }
        return out
    }
}
