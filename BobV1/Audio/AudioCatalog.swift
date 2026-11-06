//
//  AudioCatalog.swift
//  Names of the bundled sounds (BobV1/Audio/Resources, AAC .m4a), the pure settings model and the mixing constants.
//

import Foundation

nonisolated enum SFX: String, CaseIterable, Sendable {
    case squish, boop, wobble, letgo, footstep, zoomies, jump, chomp, slurp, setdown, splash, soapbubbles, bubblepop
    /// Clean flow (files scrub_loop_N looping scrub bed, squeak_polish_N window-squeak per shine stroke, shine_finish_N sparkle + squeak).
    case scrubLoop = "scrub_loop", squeakPolish = "squeak_polish", shineFinish = "shine_finish"
    case lintroller, sparkle, snore, uitap, uiconfirm, coin, select
    /// Spending JellyCoins (purchase_1: a toy register bell with a tiny coin jingle; coin_1...3 are the lighter earn clinks).
    case purchase
    /// The doorbell when a friend arrives (doorbell_1: a soft two-note ding-dong).
    case doorbell
    /// Jelly Circuit cues (files countdown_beep_N, race_go_N, race_finish_N, stumble_N).
    case countdownBeep = "countdown_beep", raceGo = "race_go", raceFinish = "race_finish", stumble
    /// Store cues (files store_open_N, buy_coins_N, ...). The sound worker's clips, normalised; buy_coins keeps only the long variant.
    case storeOpen = "store_open", buyCoins = "buy_coins", notEnough = "not_enough", pageTurn = "page_turn", shoeOn = "shoe_on", unwrap
    case crunchNugget = "crunch_nugget", crunchFries = "crunch_fries", perkSparkle = "perk_sparkle"
    /// Decor cues (files place_item_N, beanbag_sit_N).
    case placeItem = "place_item", beanbagSit = "beanbag_sit"
    /// Training cues (files whistle_N, tick_N, good_step_N, perfect_streak_N, stat_up_N, tired_N, cheer_small_N).
    /// Volleyball cues (volley_bonk_N, volley_spike_N, volley_land_N, volley_point_N).
    case volleyBonk = "volley_bonk", volleySpike = "volley_spike", volleyLand = "volley_land", volleyPoint = "volley_point"
    /// Solo emote cues (files emote_hic_1 ... : one soft clip each, 2026-11-02; BlobBrain+Emotes.swift). Each plays at most once per 10 s.
    case emoteHic = "emote_hic", emoteAchoo = "emote_achoo", emoteWoozy = "emote_woozy", emoteBow = "emote_bow", emotePat = "emote_pat"
    case emoteTail = "emote_tail", emoteFlutter = "emote_flutter", emoteSpin = "emote_spin", emoteWiggle = "emote_wiggle"
    /// Group emotes (2026-11-02): the high five's soft bump boop (highfive_boop_N), the conga line's waddle tick (conga_tick_N), the ring dance's chimes (ring_chime_N).
    /// Batch-2 emotes (2026-11-02, g-emotes3): vocals in the Jelbie voice band (spinhug, starsigh, tilt, welcome, checkin) and soft non-vocal clips (twinkle, strut, sploot).
    case emoteSpinHug = "emote_spinhug", emoteStarSigh = "emote_starsigh", emoteTilt = "emote_tilt", emoteWelcome = "emote_welcome", emoteCheckIn = "emote_checkin"
    case emoteTwinkle = "emote_twinkle", emoteStrut = "emote_strut", emoteSploot = "emote_sploot"
    case highFiveBoop = "highfive_boop", congaTick = "conga_tick", ringChime = "ring_chime"
    /// Bubble wand (2026-11-02, ElevenLabs, soft): the stream's bloop, a Jelbie's pop, a happy giggle after it (bubblewand_bloop_N / _pop_N / _chirp_N).
    case bubbleBloop = "bubblewand_bloop", bubblePop = "bubblewand_pop", bubbleChirp = "bubblewand_chirp"
    case whistle, tick, goodStep = "good_step", perfectStreak = "perfect_streak", statUp = "stat_up", tired, cheerSmall = "cheer_small"

    /// Loudness of the clip in the mix (the files themselves are peak-normalised per category).
    var gain: Float {
        switch self {
        case .footstep: return 0.45
        case .snore: return 0.55            // 2026-11-05: the files are now -22 LUFS (were -32) and this was 0.12 (effective -51 LUFS: inaudible on the phone speaker): now about -28 LUFS at the speaker, under the chirps (-25)
        case .slurp: return 0.51            // was 0.85 (default): 0.6x, "a little more quiet"
        case .countdownBeep: return 0.55
        case .raceGo: return 0.65
        case .raceFinish: return 0.7
        case .stumble: return 0.6
        case .storeOpen, .pageTurn: return 0.5
        case .buyCoins, .perkSparkle: return 0.55
        case .purchase, .doorbell: return 0.7
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
        case .emoteHic, .emoteAchoo, .emoteWoozy, .emoteBow, .emotePat, .emoteTail, .emoteFlutter, .emoteSpin, .emoteWiggle: return 0.5          // (soft: the user once complained of too many clown sounds)
        case .emoteSpinHug, .emoteStarSigh, .emoteTilt, .emoteWelcome, .emoteCheckIn: return 0.5
        case .emoteTwinkle, .emoteStrut, .emoteSploot: return 0.55
        case .highFiveBoop: return 0.8
        case .bubbleBloop: return 0.3          // (very soft: a stream of them)
        case .bubblePop: return 0.4
        case .bubbleChirp: return 0.4
        case .congaTick: return 0.45
        case .ringChime: return 0.6
        case .volleyBonk, .volleySpike, .volleyLand: return 0.8
        case .volleyPoint: return 0.6
        case .letgo: return 0.7
        case .uitap: return 0.6
        case .soapbubbles, .lintroller: return 0.7
        case .scrubLoop: return 0.5
        case .squeakPolish: return 0.6
        case .shineFinish: return 0.7
        default: return 0.85
        }
    }
    /// Shortest gap between two plays of the same effect.
    var minGap: Double {
        switch self {
        case .footstep: return 0.2
        case .squish, .boop, .wobble: return 0.16
        case .emoteHic, .emoteAchoo, .emoteWoozy, .emoteBow, .emotePat, .emoteTail, .emoteFlutter, .emoteSpin, .emoteWiggle: return 10          // never twice within 10 s
        case .emoteSpinHug, .emoteStarSigh, .emoteTilt, .emoteWelcome, .emoteCheckIn, .emoteTwinkle, .emoteStrut, .emoteSploot: return 8          // never twice within 8 s
        case .highFiveBoop: return 0.3
        case .bubbleBloop: return 0.5
        case .bubblePop: return 0.12
        case .bubbleChirp: return 1.5
        case .congaTick: return 0.2
        case .ringChime: return 0.25
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

/// The Clean flow's per-sound rate limits (seconds between two plays) and levels: the old bubble-pop / soap-bubble / splash spam read as a clown horn.
nonisolated enum BathSFX {
    static let popGap: Double = 0.6, popVolume: Float = 0.35
    static let soapGap: Double = 1.5, soapVolume: Float = 0.6
    static let splashGap: Double = 0.4, splashVolume: Float = 0.6
    static let squeakGap: Double = 0.35, squeakVolume: Float = 1, squeakRateSpread: Float = 0.08
    static let scrubFade: TimeInterval = 0.15
}

/// Lets a sound through at most once per `gap` seconds (pure: the caller supplies the clock).
nonisolated struct SoundGate: Sendable {
    let gap: Double
    private var last: Double = -.infinity
    init(gap: Double) { self.gap = gap }
    mutating func allow(now: Double) -> Bool {
        guard now - last >= gap else { return false }
        last = now
        return true
    }
}

nonisolated enum JellyVoice: String, Sendable, CaseIterable {
    case happy, sad, babble
    /// The context voices (2026-11-05): a short call that fits the moment, <type>_jelly{n}.m4a, rendered by the same synth as the chirps.
    case curious, ooh, hum, giggle, hello, yawn, yay, uhoh
    /// Round 2, batch B (2026-11-05): hmm, wheee, tasty, aww, huh, pfft, lala, eep, mmhmm, nyoo. Only the four base voices have them; Teddy / Pearl / Panda borrow the nearest.
    case hmm, wheee, tasty, aww, huh, pfft, lala, eep, mmhmm, nyoo
    var isContext: Bool { switch self { case .happy, .sad, .babble: return false; default: return true } }
    /// Batch B: no per-character set for the three newer species, and no _v2 / _v3.
    var isBatchB: Bool { switch self { case .hmm, .wheee, .tasty, .aww, .huh, .pfft, .lala, .eep, .mmhmm, .nyoo: return true; default: return false } }
    /// Round 1's eight have two more variants (_v2, _v3) for the four base voices, so a repeat differs.
    var hasVariants: Bool { isContext && !isBatchB }
}

/// The voice set of a CHARACTER (0 Bob, 1 Pip, 2 Moss, 3 Lavender, 4 Teddy, 5 Pearl, 6 Panda): files chirp_jelly{c+1}_happy/_sad, babble_jelly{c+1}, <type>_jelly{c+1}[_v2|_v3].
/// Snores and sleep coos exist for the first four only (`count`); Teddy, Pearl and Panda use Lavender's.
nonisolated enum JellyVoiceSet {
    static let count = 4
    static let voiceSets = 7
    static func index(character c: Int) -> Int { min(max(c, 0), voiceSets - 1) + 1 }
    /// The snore / coo set: the first four characters' (Teddy, Pearl and Panda share Lavender's).
    static func baseIndex(character c: Int) -> Int { min(max(c, 0), count - 1) + 1 }
    /// Batch-B voices for the newer species: Teddy -> Bob, Pearl -> Lavender, Panda -> Moss (and a pitch trim for Teddy, who is lower than Bob).
    static func borrowed(_ n: Int) -> Int { n <= 4 ? n : (n == 5 ? 1 : (n == 6 ? 4 : 3)) }
    static func rate(character c: Int, _ v: JellyVoice) -> Float { v.isBatchB && index(character: c) == 5 ? 0.87 : 1 }
    /// `variant` 1...3 (2 and 3 exist for the base four's round-1 types only; anything else plays the first).
    static func file(character c: Int, _ v: JellyVoice, variant: Int = 1) -> String {
        let n = index(character: c)
        switch v {
        case .babble: return "babble_jelly\(n)"
        case .happy, .sad: return "chirp_jelly\(n)_\(v.rawValue)"
        default:
            let m = v.isBatchB ? borrowed(n) : n
            return "\(v.rawValue)_jelly\(m)" + (v.hasVariants && m <= 4 && variant > 1 ? "_v\(min(variant, 3))" : "")
        }
    }
}

extension JellyVoiceSet {
    /// The context voice (and the chance of it) for the start of an idle move: look / peek -> curious, sit / lie / sway -> hum, the playful ones -> giggle, the yawn -> yawn, a stumble / startle -> uh-oh.
    static func contextVoice(forIdle kind: IdleKind, mood: IdleMood = .happy) -> (voice: JellyVoice, chance: Double)? {
        switch kind {
        case .look, .peek, .decorPeek, .window, .stopLook: return (Bool.random() ? .curious : .hmm, 0.15)
        case .sit, .decorSit, .lieDown, .sway, .stretch: return (.hum, 0.15)
        case .slump: return (Bool.random() ? .pfft : .nyoo, 0.2)
        case .zoomies, .run: return (Bool.random() ? .wheee : .giggle, 0.18)
        case .skipHop, .bounce, .decorHop, .decorSlide, .slide, .joy, .giggle, .jacks, .trot: return (.giggle, 0.15)
        case .yawn: return (.yawn, 0.4)
        case .stumble: return (.uhoh, 0.4)
        case .startle: return (Bool.random() ? .eep : .huh, 0.4)
        case .sigh, .tailHug: return (.aww, 0.2)
        case .wander: return mood == .happy ? (.lala, 0.05) : (mood == .grumpy ? (.pfft, 0.05) : nil)
        default: return nil
        }
    }
    /// A chance of the bubble-pop variant (snore_jelly{c}_2) over the plain snore (_1).
    static let snorePopChance: Double = 0.3
    /// The snore file of a CHARACTER: snore_jelly{c+1}_{1|2}. `roll` in 0..<1 picks the variant (2 = ends in a tiny bubble pop).
    static func snoreFile(character c: Int, roll: Double) -> String {
        "snore_jelly\(baseIndex(character: c))_\(roll < snorePopChance ? 2 : 1)"
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
    /// The storm (Melon/Weather.swift): clip volumes as passed to `playClip` (which scales by 1.5), so a thunder peaks at 0.21 of the sound-effects level - under the
    /// race crowd's 0.22 - a far rumble and the sigh softer, the rain on the glass a quiet bed; the music dips to `stormDuck` at a rumble and returns over `stormDuckBack` s.
    static let stormThunder: Float = 0.14, stormRumble: Float = 0.10, stormSigh: Float = 0.10, stormRain: Float = 0.07
    static let stormDuckClose: Float = 0.7, stormDuckFar: Float = 0.85, stormDuckBack: Double = 3.0
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

/// When the sleeping Jellies snore: one snore per Jelly every 20...40 s, and never two Jellies within `hubGap` of each other
/// (a later one waits its turn). Pure: the hub feeds it the clock and a random source; tests drive it directly.
nonisolated struct SnoreScheduler: Sendable {
    /// 2026-11-06 "play more often": the snore pace is 13...24 s and 5...12 s first, divided by `speedUp` (a test sets it to 1 for the "before").
    /// 2026-11-06 (again): a little more on top (user: "little snoring"): x1.08 (`SleepMurmurTuning.snoreBoost`), so 1.35 * 1.08.
    nonisolated(unsafe) static var speedUp: Double = 1.35 * SleepMurmurTuning.snoreBoost
    static var interval: ClosedRange<Double> { (13 / speedUp)...(24 / speedUp) }        // was 6...10, then 20...40 (inaudible), then 13...24
    static var firstDelay: ClosedRange<Double> { (5 / speedUp)...(12 / speedUp) }
    static let hubGap: Double = 3.5
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

// MARK: - sleep sounds (2026-11-04): soft coos and a quieter extra snore, ON TOP of the snores above (those keep their rate)

extension JellyVoiceSet {
    static let sleepCooVariants = 3
    /// sleep_coo_jelly{c}_{1...3}: a soft hummed "oo" in the character's voice. `roll` in 0..<1 picks the variant.
    static func sleepCooFile(character c: Int, roll: Double) -> String {
        "sleep_coo_jelly\(baseIndex(character: c))_\(min(Int(roll * Double(sleepCooVariants)), sleepCooVariants - 1) + 1)"
    }
}

nonisolated enum SleepSound: Equatable, Sendable { case coo, softSnore }

/// Extra sleeping sounds per napping Jelly: a coo about every 9...18 s, now and then (`softSnoreChance`) a quiet snore in its place, and no two
/// Jellies within `hubGap` of each other. Pure: the hub feeds it the clock and a random source.
nonisolated struct SleepSoundScheduler: Sendable {
    static let interval: ClosedRange<Double> = 13...24          // (alternates with the snore scheduler: a snore or a coo about every 8-15 s per sleeper)
    static let firstDelay: ClosedRange<Double> = 3...8
    static let hubGap: Double = 3
    static let softSnoreChance: Double = 0
    static let softSnoreGain: Float = 0.6
    static let cooGain: Float = 0.55
    private(set) var next: [Double] = [0, 0, 0]
    private(set) var lastAny: Double = -100

    mutating func due(napping: [Bool], now: Double, random: (ClosedRange<Double>) -> Double) -> [(jelly: Int, sound: SleepSound)] {
        var out: [(jelly: Int, sound: SleepSound)] = []
        for i in napping.indices where i < next.count {
            guard napping[i] else { next[i] = 0; continue }
            if next[i] == 0 { next[i] = now + random(Self.firstDelay) + Double(i) * 0.9 }
            guard now >= next[i] else { continue }
            if now - lastAny < Self.hubGap { next[i] = lastAny + Self.hubGap + random(0.2...1.0); continue }
            next[i] = now + random(Self.interval)
            lastAny = now
            out.append((i, random(0...1) < Self.softSnoreChance ? .softSnore : .coo))
        }
        return out
    }
}

// MARK: - sleep murmurs (2026-11-06): quiet sleep-talk from the EXISTING hum / ooh (and, rarely, giggle) clips, ON TOP of the snores and coos

nonisolated enum SleepMurmurTuning {
    /// Off = exactly the snores + coos of before (a test turns it off for the "before" numbers).
    nonisolated(unsafe) static var enabled = true
    /// The snore pace of r1058 was x1.35; 2026-11-06 "a little more snoring": x1.08 more (applied in `SnoreScheduler.speedUp`; a test sets it back for the "before").
    /// Why not 1.3: the hub's 2.5 s sleep hush (not ours to change) drops a coo that lands within it of any snore, so more snores = fewer PLAYED coos. Measured over 60 simulated
    /// minutes x 3 sleepers (PLAYED per sleeper per minute): x1.0 snores 2.63 coos 1.88 | x1.1 2.88 (+9 %) 1.71 (91 %) | x1.2 3.10 (+18 %) 1.63 (87 %) | x1.3 3.31 (+26 %) 1.56 (83 %).
    /// "Add, never displace" (coos keep >= 90 %) caps the boost at about x1.1.
    static let snoreBoost: Double = 1.08
    /// One murmur per sleeper about every 30...60 s (the first 12...30 s after he falls asleep). Quiet: well under a voice's usual 0.7.
    static let interval: ClosedRange<Double> = 30...60, firstDelay: ClosedRange<Double> = 12...30
    static let gain: Float = 0.3
    /// A murmur never starts within this long BEFORE the same sleeper's next snore / coo (it would be a second voice), nor this long after one.
    static let clearBefore: Double = 3.5, clearAfter: Double = 3.0
    static let giggleChance: Double = 0.06
    /// hum / ooh (50 / 50 %), and now and then a tiny giggle. NEVER .hmm or .mmhmm (user 2026-11-06: the hmm clip "sounds like a ghost").
    static func pick(random: (ClosedRange<Double>) -> Double) -> JellyVoice {
        if random(0...1) < giggleChance { return .giggle }
        let r = random(0...1)
        return r < 0.5 ? .hum : .ooh
    }
}

/// When a napping Jelly murmurs. Pure like the other two: the hub feeds the clock, a random source and, per Jelly, when ITS OWN next snore / coo is due
/// (`nextOwn`, 0 = unknown) and when it last made one (`lastOwn`). A murmur waits (retries in 1...2.5 s) until it is clear of both, so it never lands in the same
/// Jelbie's snore or coo (one voice per Jelbie). (A global "clear of every sleeper's sound" was tried: three sleepers snore / coo so often it starved the murmurs.)
nonisolated struct SleepMurmurScheduler: Sendable {
    private(set) var next: [Double] = [0, 0, 0]

    mutating func due(napping: [Bool], now: Double, nextOwn: [Double], lastOwn: [Double], random: (ClosedRange<Double>) -> Double) -> [(jelly: Int, voice: JellyVoice)] {
        var out: [(jelly: Int, voice: JellyVoice)] = []
        for i in napping.indices where i < next.count {
            guard napping[i] else { next[i] = 0; continue }
            if next[i] == 0 { next[i] = now + random(SleepMurmurTuning.firstDelay) + Double(i) * 2.1 }
            guard now >= next[i] else { continue }
            let n = i < nextOwn.count ? nextOwn[i] : 0, l = i < lastOwn.count ? lastOwn[i] : -100
            if (n > 0 && n - now < SleepMurmurTuning.clearBefore) || now - l < SleepMurmurTuning.clearAfter { next[i] = now + random(1.0...2.5); continue }
            next[i] = now + random(SleepMurmurTuning.interval)
            out.append((i, SleepMurmurTuning.pick(random: random)))
        }
        return out
    }
}
