import Foundation

struct PersonalityMods: Equatable {
    var energy = 1.0
    var playfulness = 1.0
    var affectionGain = 1.0
    /// Multiplier on affection gain while affection is below `warmThreshold` (shy = slow start).
    var earlyAffection = 1.0
    /// Multiplier once affection >= `warmThreshold` (shy = bigger later).
    var lateAffection = 1.0
    var idle = IdleWeightMultipliers()

    static let warmThreshold = 0.6

    func affectionMultiplier(at affection: Double) -> Double {
        affectionGain * (affection < Self.warmThreshold ? earlyAffection : lateAffection)
    }
}

enum Personality: String, Codable, CaseIterable {
    case playful, shy, cuddly, curious, sleepy, cheeky

    var displayName: String { rawValue.capitalized }

    var blurb: String {
        switch self {
        case .playful: return "Bouncy and always up for a game."
        case .shy: return "Takes a while to warm up, but loves fiercely after."
        case .cuddly: return "Melts into every cuddle."
        case .curious: return "Wants to poke at everything."
        case .sleepy: return "Happiest in a warm little nap."
        case .cheeky: return "A little rascal who loves attention."
        }
    }

    var mods: PersonalityMods {
        switch self {
        case .playful:
            return PersonalityMods(energy: 1.2, playfulness: 1.3,
                                   idle: IdleWeightMultipliers(hop: 1.5, roll: 1.4, nap: 0.6))
        case .shy:
            return PersonalityMods(energy: 0.8, playfulness: 0.8, earlyAffection: 0.6, lateAffection: 1.5,
                                   idle: IdleWeightMultipliers(wander: 0.7, sit: 1.4, lookAtCamera: 0.5))
        case .cuddly:
            return PersonalityMods(affectionGain: 1.3, idle: IdleWeightMultipliers(sit: 1.3, lookAtCamera: 1.5))
        case .curious:
            return PersonalityMods(idle: IdleWeightMultipliers(wander: 1.3, lookAtCamera: 1.3))
        case .sleepy:
            return PersonalityMods(energy: 0.6, playfulness: 0.7,
                                   idle: IdleWeightMultipliers(wander: 0.6, hop: 0.5, sit: 1.3, nap: 2.5))
        case .cheeky:
            return PersonalityMods(energy: 1.1, playfulness: 1.2, affectionGain: 0.9,
                                   idle: IdleWeightMultipliers(hop: 1.3, roll: 1.5, lookAtCamera: 1.4))
        }
    }
}

enum Marking: String, Codable, CaseIterable {
    case none, spotOnHead, starOnHead, heartOnCheek, freckles, spotOnBack, whiteBelly
}

struct BlobLook: Codable, Hashable {
    static let maxLightnessShift: Float = 0.06   // +-6% L
    static let maxHueShiftDegrees: Float = 8     // +-8 degrees
    static let sizeRange: ClosedRange<Float> = 0.95...1.05

    var shade: Float = 0                 // -1...1
    var marking: Marking = .none
    var sizeScale: Float = 1
    /// Breed-feature variation (ignored by Berry): spike/antenna size multiplier.
    var featureScale: Float = 1
    /// Number of spikes (Mint 5...7) or antennae (Honey 1...2); 0 for Berry.
    var featureCount: Int = 0
    /// Seed for per-individual jitter (antenna curl, spike spacing).
    var featureSeed: UInt32 = 0

    static let featureScaleRange: ClosedRange<Float> = 0.8...1.25

    static func featureCountRange(for breed: BreedID) -> ClosedRange<Int> {
        switch breed {
        case .berry: return 0...0
        case .mint: return 5...7
        case .honey: return 1...2
        }
    }

    init(shade: Float = 0, marking: Marking = .none, sizeScale: Float = 1,
         featureScale: Float = 1, featureCount: Int = 0, featureSeed: UInt32 = 0) {
        self.shade = shade; self.marking = marking; self.sizeScale = sizeScale
        self.featureScale = featureScale; self.featureCount = featureCount; self.featureSeed = featureSeed
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        shade = try c.decodeIfPresent(Float.self, forKey: .shade) ?? 0
        marking = (try? c.decodeIfPresent(Marking.self, forKey: .marking)) ?? .none
        sizeScale = try c.decodeIfPresent(Float.self, forKey: .sizeScale) ?? 1
        featureScale = try c.decodeIfPresent(Float.self, forKey: .featureScale) ?? 1
        featureCount = try c.decodeIfPresent(Int.self, forKey: .featureCount) ?? 0
        featureSeed = try c.decodeIfPresent(UInt32.self, forKey: .featureSeed) ?? 0
    }

    struct Colors: Equatable { var core: String; var light: String; var deep: String }

    /// Final hex colours for this breed with the shade applied.
    func colors(for breed: BreedID) -> Colors {
        let s = breed.spec
        let sh = max(-1, min(1, shade))
        return Colors(core: Self.shift(s.colorHexCore, sh),
                      light: Self.shift(s.colorHexLight, sh),
                      deep: Self.shift(s.colorHexDeep, sh))
    }

    static func shift(_ hex: String, _ shade: Float) -> String {
        var (h, s, l) = hexToHSL(hex)
        h = (h + Double(shade * maxHueShiftDegrees)).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        l = min(1, max(0, l + Double(shade * maxLightnessShift)))
        s = min(1, max(0, s))
        return hslToHex(h, s, l)
    }

    /// Returns (hue degrees, saturation 0...1, lightness 0...1).
    static func hexToHSL(_ hex: String) -> (Double, Double, Double) {
        let str = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt32(str, radix: 16) ?? 0
        let r = Double((v >> 16) & 255) / 255, g = Double((v >> 8) & 255) / 255, b = Double(v & 255) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        if d == 0 { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h *= 60
        if h < 0 { h += 360 }
        return (h, s, l)
    }

    static func hslToHex(_ h: Double, _ s: Double, _ l: Double) -> String {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        func byte(_ f: Double) -> Int { Int(((f + m) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

struct AdoptionCandidate: Identifiable, Equatable {
    var id: UUID
    var breed: BreedID
    var personality: Personality
    var look: BlobLook
    var suggestedName: String
}

/// Deterministic SplitMix64.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum KennelGenerator {
    /// Three distinct candidates; deterministic for a given seed (including ids).
    static func candidates(for breed: BreedID, seed: UInt64) -> [AdoptionCandidate] {
        var rng = SeededGenerator(seed: seed ^ 0xB10B_B10B)
        let personalities = Array(Personality.allCases.shuffled(using: &rng).prefix(3))
        // One shade per band so the trio is visibly different.
        let bands: [ClosedRange<Float>] = [-1 ... -0.5, -0.25 ... 0.25, 0.5 ... 1]
        let shades = bands.map { Float.random(in: $0, using: &rng) }.shuffled(using: &rng)
        // Size bands likewise.
        let sizeBands: [ClosedRange<Float>] = [0.95 ... 0.97, 0.99 ... 1.01, 1.03 ... 1.05]
        let sizes = sizeBands.map { Float.random(in: $0, using: &rng) }.shuffled(using: &rng)
        // Three distinct markings, at most one `.none`.
        var markings = Marking.allCases.filter { $0 != .none }.shuffled(using: &rng)
        markings = Array(markings.prefix(3))
        if Bool.random(using: &rng) { markings[Int.random(in: 0..<3, using: &rng)] = .none }
        let fScaleBands: [ClosedRange<Float>] = [0.8 ... 0.93, 0.97 ... 1.08, 1.14 ... 1.25]
        let fScales = fScaleBands.map { Float.random(in: $0, using: &rng) }.shuffled(using: &rng)
        let cr = BlobLook.featureCountRange(for: breed)
        let fCounts = Array(cr).shuffled(using: &rng)   // 3 values for Mint/Honey, [0] for Berry
        let fSeeds = (0..<3).map { _ in UInt32.random(in: .min ... .max, using: &rng) }
        let names = Array(NameSuggester.shuffled(using: &rng).prefix(3))

        let ids: [UUID] = (0..<3).map { _ in
            let a = rng.next(), b = rng.next()
            var u = [UInt8](repeating: 0, count: 16)
            for k in 0..<8 { u[k] = UInt8((a >> (8 * UInt64(k))) & 255); u[8 + k] = UInt8((b >> (8 * UInt64(k))) & 255) }
            return UUID(uuid: (u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7], u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]))
        }
        return (0..<3).map { i in
            AdoptionCandidate(
                id: ids[i],
                breed: breed, personality: personalities[i],
                look: BlobLook(shade: shades[i], marking: markings[i], sizeScale: sizes[i],
                               featureScale: breed == .berry ? 1 : fScales[i],
                               featureCount: fCounts[i % fCounts.count],
                               featureSeed: fSeeds[i]),
                suggestedName: names[i])
        }
    }
}
