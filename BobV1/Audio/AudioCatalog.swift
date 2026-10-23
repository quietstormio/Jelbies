//
//  AudioCatalog.swift
//  Names of the bundled sounds (BobV1/Audio/Resources, AAC .m4a), the pure settings model and the mixing constants.
//

import Foundation

nonisolated enum SFX: String, CaseIterable, Sendable {
    case squish, boop, wobble, letgo, footstep, zoomies, jump, chomp, slurp, setdown, splash, soapbubbles, bubblepop
    case lintroller, sparkle, snore, uitap, uiconfirm, coin, select
    /// Jelly Circuit cues (files countdown_beep_N, race_go_N, race_finish_N, stumble_N).
    case countdownBeep = "countdown_beep", raceGo = "race_go", raceFinish = "race_finish", stumble
    /// Store cues (files store_open_N, buy_coins_N, ...). The sound worker's clips, normalised; buy_coins keeps only the long variant.
    case storeOpen = "store_open", buyCoins = "buy_coins", notEnough = "not_enough", pageTurn = "page_turn", shoeOn = "shoe_on", unwrap
    case crunchNugget = "crunch_nugget", crunchFries = "crunch_fries", perkSparkle = "perk_sparkle"
    /// Decor cues (files place_item_N, beanbag_sit_N).
    case placeItem = "place_item", beanbagSit = "beanbag_sit"
    /// Training cues (files whistle_N, tick_N, good_step_N, perfect_streak_N, stat_up_N, tired_N, cheer_small_N).
    case whistle, tick, goodStep = "good_step", perfectStreak = "perfect_streak", statUp = "stat_up", tired, cheerSmall = "cheer_small"

    /// Loudness of the clip in the mix (the files themselves are peak-normalised per category).
    var gain: Float {
        switch self {
        case .footstep: return 0.45
        case .snore: return 0.175           // was 0.5: "the snoring is too loud" (0.35x)
        case .slurp: return 0.51            // was 0.85 (default): 0.6x, "a little more quiet"
        case .countdownBeep: return 0.55
        case .raceGo: return 0.65
        case .raceFinish: return 0.7
        case .stumble: return 0.6
        case .storeOpen, .pageTurn: return 0.5
        case .buyCoins, .perkSparkle: return 0.55
        case .notEnough: return 0.5
        case .shoeOn, .unwrap: return 0.45
        case .placeItem: return 0.55
        case .beanbagSit: return 0.5
        case .whistle, .statUp, .cheerSmall: return 0.6
        case .tick: return 0.55
        case .goodStep: return 0.5
        case .perfectStreak: return 0.6
        case .tired: return 0.5
        case .crunchNugget, .crunchFries: return 0.5
        case .squish, .boop, .wobble: return 0.8
        case .letgo: return 0.7
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
        case .letgo: return 0.25
        case .chomp, .slurp, .crunchNugget, .crunchFries: return 0.25
        case .soapbubbles, .lintroller, .splash: return 0.45
        case .bubblepop: return 0.07
        case .uitap, .uiconfirm: return 0.06
        case .countdownBeep, .raceGo: return 0.3
        case .tick, .goodStep: return 0.05
        default: return 0.1
        }
    }
}

nonisolated enum JellyVoice: String, Sendable { case happy, sad, babble }

/// The voice set of a CHARACTER (0 Bob, 1 Pip, 2 Moss, 3 Lavender): files chirp_jelly{c+1}_happy/_sad, babble_jelly{c+1}.
nonisolated enum JellyVoiceSet {
    static let count = 4
    static func index(character c: Int) -> Int { min(max(c, 0), count - 1) + 1 }
    static func file(character c: Int, _ v: JellyVoice) -> String {
        v == .babble ? "babble_jelly\(index(character: c))" : "chirp_jelly\(index(character: c))_\(v.rawValue)"
    }
}

/// The let-go sound: one soft boing per release, however many squash peaks the settle has (the haptics still play at every peak).
nonisolated enum TouchSound {
    static let letGoRingGap: Double = 0.5
    static let letGoBase: Float = 0.55
    static let letGoSlope: Float = 0.8
}

/// A ring is a run of pulses less than `TouchSound.letGoRingGap` apart; only its first pulse sounds.
nonisolated struct LetGoRing {
    private var last: Double = -.infinity
    init() {}
    mutating func shouldSound(now: Double) -> Bool {
        defer { last = now }
        return now - last >= TouchSound.letGoRingGap
    }
}

nonisolated enum AudioMix {
    static let music: Float = 0.5
    static let ambience: Float = 0.34
    static let sfxMaster: Float = 1
    static let crossfade: Double = 3
    /// The race crowd loop: level in the mix and the crossfade at the loop point (the file is not seamless).
    static let crowd: Float = 0.22
    static let crowdCrossfade: Double = 1.0
    /// The app's own music while the Jellies dance to music from outside (Ears): down to this, so the mic stops hearing it.
    static let danceDuck: Float = 0.15
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
