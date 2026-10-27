//
//  ParkModels.swift
//  The Park's data: the visitor Jelbies (the same body in new colour x signature x worn-item combinations, generated on the device from a fixed seed), their
//  personalities, the friendship ladder (Stranger, Pal, Friend, Best friend) and the tunables. Pure values; nothing here touches the network or the sim.
//  Names, one-line personalities and greetings come from the hand-written lists below; the on-device model (ParkText.swift) may rewrite them, never required.
//

import Foundation
import simd

/// How a visitor behaves: borrows the idle / social weights of a starter (VarietyTuning.personality is keyed by the feature the starter grows).
nonisolated enum ParkStyle: String, Codable, CaseIterable, Sendable {
    case energetic, calm, playful, balanced
    var variety: JellyFeature {
        switch self { case .energetic: return .spines; case .calm: return .daisy; case .playful: return .wings; case .balanced: return .none }
    }
    var word: String {
        switch self { case .energetic: return "Zippy"; case .calm: return "Mellow"; case .playful: return "Silly"; case .balanced: return "Easygoing" }
    }
}

/// Body colours beyond the four starters (blue, yellow, green, lavender).
nonisolated enum ParkColour: String, Codable, CaseIterable, Sendable {
    case pink, orange, mint, teal, cream, grey, red, peach, lime, plum, coral, cocoa

    var title: String { rawValue.capitalized }
    /// (flesh, deep) in the same units the starters' palettes use.
    var flesh: (SIMD3<Float>, SIMD3<Float>) {
        switch self {
        case .pink: return ([0.950, 0.700, 0.780], [0.800, 0.420, 0.560])
        case .orange: return ([0.980, 0.740, 0.460], [0.840, 0.500, 0.200])
        case .mint: return ([0.620, 0.900, 0.780], [0.300, 0.680, 0.550])
        case .teal: return ([0.450, 0.800, 0.820], [0.200, 0.580, 0.620])
        case .cream: return ([0.980, 0.930, 0.800], [0.850, 0.750, 0.550])
        case .grey: return ([0.800, 0.820, 0.860], [0.520, 0.550, 0.620])
        case .red: return ([0.940, 0.500, 0.480], [0.760, 0.240, 0.240])
        case .peach: return ([0.990, 0.800, 0.680], [0.860, 0.560, 0.420])
        case .lime: return ([0.820, 0.920, 0.480], [0.580, 0.740, 0.200])
        case .plum: return ([0.720, 0.520, 0.780], [0.520, 0.300, 0.600])
        case .coral: return ([0.990, 0.620, 0.580], [0.840, 0.380, 0.360])
        case .cocoa: return ([0.780, 0.620, 0.520], [0.550, 0.380, 0.300])
        }
    }
    /// sRGB 0...1 swatch for the little dots and the card.
    var swatch: SIMD3<Float> { flesh.0 }
}

extension JellyPalettes {
    /// A visitor's body colours: the same soft matte treatment as Moss's green and Lavender.
    static func park(_ c: ParkColour) -> Palette {
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        let (f, d) = c.flesh
        return matte(Palette(name: c.title, flesh: f, fleshDeep: d, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                             shadowTint: d * 0.5 + f * 0.5, uiFlesh: f * 0.93))
    }
}

/// The friendship ladder of one visitor with one of the player's Jelbies (0...100 points).
nonisolated enum ParkFriendLevel: Int, Comparable, Sendable {
    case stranger, pal, friend, best
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    static func of(_ points: Float) -> Self {
        points >= ParkTuning.bestAt ? .best : points >= ParkTuning.friendAt ? .friend : points >= ParkTuning.palAt ? .pal : .stranger
    }
    var title: String { switch self { case .stranger: return "Stranger"; case .pal: return "Pal"; case .friend: return "Friend"; case .best: return "Best friend" } }
    var hearts: Int { rawValue }
}

nonisolated struct ParkVisitor: Codable, Identifiable, Equatable, Sendable {
    /// Index in the pool (stable).
    let id: Int
    var name: String
    var colour: ParkColour
    var signature: JellyFeature
    /// A worn item (a hat, glasses, a bow ...), sometimes.
    var wear: WearLook?
    var style: ParkStyle
    /// One short line about them, and what they say hello with.
    var blurb: String
    var greeting: String
    /// The line they say when the friendship reaches Pal / Friend / Best friend, by level raw value ("1", "2", "3"). Cached once.
    var levelLines: [String: String] = [:]
    /// Friendship points (0...100) with each of the player's characters, by character id ("0"...).
    var friendship: [String: Float] = [:]
    /// Seconds since 1970 of the last visit (0 = never seen).
    var lastSeen: Double = 0
    /// The on-device model has written the text (name stays as shown once the visitor has been introduced).
    var written = false
    var introduced = false

    func points(with character: Int) -> Float { friendship[String(character)] ?? 0 }
    func level(with character: Int) -> ParkFriendLevel { .of(points(with: character)) }
    /// The best friendship over some characters (to weigh who comes back).
    func bestLevel(among characters: [Int]) -> ParkFriendLevel { characters.map { level(with: $0) }.max() ?? .stranger }
}

nonisolated enum ParkTuning {
    // The trip (the same feel as the café's fade)
    static let fadeOut: Float = 0.4, fadeIn: Float = 0.5, holdSteps = 3
    static let toastSeconds: Float = 3.2
    // The cast: at most five Jelbies in the park, the player's plus 1...4 visitors (ParkVisit.visitorCount)
    static let maxTotal = 5, minVisitors = 1, maxVisitors = 4
    static let poolSize = 16
    static let poolSeed: UInt64 = 0x9A2B_17C3_5D41
    // Friendship (points per second near each other; a social together is faster). Doubled on 2026-10-25 (friends come in a couple of visits, not ages):
    // a visit of ~5 minutes among the visitors is now worth ~20...40 points with each one met, the friendly socials a good deal more.
    static let nearRadius: Float = 3.2
    static let pointsPerSecond: Float = 0.36
    static let socialMul: Float = 4.0
    /// While the two do one of the friendly socials (chest bump, high five, hum, cheek squish, twirl, hop along): the rate multiplier (instead of `socialMul`) and a lump when one starts.
    static let friendlyMul: Float = 8.0
    static let friendlyStartBonus: Float = 2.5
    static let palAt: Float = 20, friendAt: Float = 45, bestAt: Float = 75
    /// A home visit (a guest over to play): friendship points per second near a housemate, and the same friendly-social boost.
    static let homeMul: Float = 0.7
    // Love (the Love / attention need that petting fills at NeedsTuning.petRate per second): twice that while playing with a friend, a daily cap
    static let loveMul: [Float] = [0.5, 1.0, 2.0, 2.0]          // stranger, pal, friend, best friend (times petRate)
    static let loveDailyCap: Float = 0.8
    static let loveChunk: Float = 0.02
    // Gifts (ParkGifts.swift): a friend walks over on about every other visit, after this many seconds of play
    static let giftWait: ClosedRange<Float> = 12...30
    static let giftWalkTimeout: Float = 9
    static let giftCardSeconds: Float = 3.6
    // Saves
    static let saveEvery: Float = 20
    static let music: MusicScene = .park
}

/// The hand-written text: names, personalities, greetings, level-up lines. Everything works with these alone.
nonisolated enum ParkWords {
    static let names = ["Poppy", "Biscuit", "Tango", "Mochi", "Pickle", "Juniper", "Waffles", "Clover", "Nimbus", "Pebble", "Sprout", "Marlo",
                        "Tilly", "Bean", "Dot", "Fig", "Olive", "Rumble", "Pudge", "Zinnia", "Taffy", "Bumble", "Noodle", "Sunny"]

    static func blurb(_ s: ParkStyle, _ r: inout ParkRandom) -> String {
        let l: [String]
        switch s {
        case .energetic: l = ["Never stops bouncing.", "Races everyone to the pond.", "Always the first to zoom."]
        case .calm: l = ["Loves a quiet sit in the sun.", "Takes everything nice and slow.", "Hums softly to the flowers."]
        case .playful: l = ["Giggles at everything.", "Always up for a silly game.", "Dances when nobody is looking."]
        case .balanced: l = ["Friendly with everyone.", "Happy to play or to rest.", "Likes a bit of everything."]
        }
        return r.pick(l)
    }
    static func greeting(_ name: String, _ s: ParkStyle, _ r: inout ParkRandom) -> String {
        let l: [String]
        switch s {
        case .energetic: l = ["Hi hi hi! Catch me!", "Race you to the bench!", "Ooh, play with me!"]
        case .calm: l = ["Hello, nice to see you.", "What a lovely day.", "Hi. Come sit with me."]
        case .playful: l = ["Hee hee, hello!", "Want to be silly together?", "Boop! Hi there!"]
        case .balanced: l = ["Hello, friend!", "Hi! Good to see you.", "Hey, nice day, isn't it?"]
        }
        return r.pick(l)
    }
    static func levelLine(_ name: String, _ level: ParkFriendLevel) -> String {
        switch level {
        case .stranger: return "Hello!"
        case .pal: return "We are pals now!"
        case .friend: return "You are my friend!"
        case .best: return "Best friends forever!"
        }
    }
}

/// A tiny seeded generator (splitmix64) so the pool is the same on every launch.
nonisolated struct ParkRandom: Sendable {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
}

nonisolated enum ParkPool {
    /// Items a visitor may wear (none covers the mouth).
    static let wearables: [WearLook] = [.beanieHoney, .beaniePink, .bucketHat, .bucketHatPink, .partyHat, .catEars, .bunnyEars, .frogEars, .flowerClip,
                                        .sweatband, .bowtiePink, .bowtieSky, .bandanaCoral, .bandanaMint, .scarfSky, .glassesRound, .sunglassesStar]

    /// The whole pool: `ParkTuning.poolSize` visitors, every colour used, signatures and items mixed. The same on every device.
    static func generate(count: Int = ParkTuning.poolSize, seed: UInt64 = ParkTuning.poolSeed) -> [ParkVisitor] {
        var r = ParkRandom(seed)
        var colours = ParkColour.allCases
        for i in stride(from: colours.count - 1, to: 0, by: -1) { colours.swapAt(i, Int(r.next() % UInt64(i + 1))) }
        var names = ParkWords.names
        for i in stride(from: names.count - 1, to: 0, by: -1) { names.swapAt(i, Int(r.next() % UInt64(i + 1))) }
        // Signatures belong only to the player's starters; visitors are plain. The draw is still consumed so the rest of the pool stays identical.
        let signatures: [JellyFeature] = [.none, .none, .none, .spines, .daisy, .wings]
        var out: [ParkVisitor] = []
        for i in 0..<count {
            let style = ParkStyle.allCases[Int(r.next() % UInt64(ParkStyle.allCases.count))]
            _ = r.pick(signatures)
            let sig: JellyFeature = .none
            let wear: WearLook? = r.unit() < 0.45 ? r.pick(wearables) : nil
            let name = names[i % names.count]
            out.append(ParkVisitor(id: i, name: name, colour: colours[i % colours.count], signature: sig, wear: wear, style: style,
                                   blurb: ParkWords.blurb(style, &r), greeting: ParkWords.greeting(name, style, &r)))
        }
        return out
    }

    /// Who comes this time: `count` visitors drawn without repeats, weighted towards friends of the Jelbies that are coming and towards ones not seen for a while.
    static func pickCast(from pool: [ParkVisitor], count: Int, characters: [Int], now: Double, using rng: inout some RandomNumberGenerator) -> [ParkVisitor] {
        var left = pool
        var out: [ParkVisitor] = []
        while out.count < count, !left.isEmpty {
            let weights = left.map { weight($0, characters: characters, now: now) }
            let total = weights.reduce(0, +)
            var x = Double.random(in: 0..<max(total, 0.0001), using: &rng)
            var k = left.count - 1
            for (i, w) in weights.enumerated() { if x < w { k = i; break }; x -= w }
            out.append(left.remove(at: k))
        }
        return out
    }
    static func weight(_ v: ParkVisitor, characters: [Int], now: Double) -> Double {
        let days = v.lastSeen <= 0 ? 14.0 : min(max((now - v.lastSeen) / 86_400, 0), 14)
        var w = 1.0 + days * 0.25
        switch v.bestLevel(among: characters) { case .stranger: break; case .pal: w += 0.5; case .friend: w += 1.0; case .best: w += 1.5 }
        return w
    }

    /// A line made safe to show: one short line of plain text.
    static func clean(_ raw: String, limit: Int) -> String? {
        var t = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*"))
        t = t.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        guard !t.isEmpty, t.count <= limit, !t.lowercased().contains("http") else { return nil }
        return t
    }
}
