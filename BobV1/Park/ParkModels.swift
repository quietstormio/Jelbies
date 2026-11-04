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
    /// The four classic species colours (Bob blue, Pip yellow, Moss green, Lavender purple): what a visitor normally is. Declared last so `mutations` keeps the old order.
    case blue, yellow, green, lavender

    var isClassic: Bool { switch self { case .blue, .yellow, .green, .lavender: return true; default: return false } }
    static let classics: [ParkColour] = [.blue, .yellow, .green, .lavender]
    /// The variant colours a rare mutation visitor may have (the original twelve).
    static var mutations: [ParkColour] { allCases.filter { !$0.isClassic } }

    var title: String { rawValue.capitalized }
    /// The species signature for this colour. A signature belongs to a colour SPECIES, never to one character, and never appears on another colour
    /// (user decision 2026-10-26; see docs/Species.md): purple -> wings, green -> head daisy, yellow -> pointed tail + 7 spikes (`.spines`), all else none.
    /// No visitor colour is yellow today (cream / peach / orange stay plain), so the yellow case is reserved.
    var speciesFeature: JellyFeature {
        switch self {
        case .plum, .lavender: return .wings
        case .mint, .lime, .green: return .daisy
        case .yellow: return .spines
        default: return .none
        }
    }
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
        // swatches of the real starters (JellyRoster.tint); their bodies use the starters' own palettes (JellyPalettes.park)
        case .blue: return ([0.70, 0.83, 0.945], [0.45, 0.64, 0.88])
        case .yellow: return ([0.99, 0.90, 0.62], [0.90, 0.72, 0.30])
        case .green: return ([0.70, 0.90, 0.66], [0.290, 0.650, 0.350])
        case .lavender: return ([0.80, 0.72, 0.93], [0.520, 0.410, 0.780])
        }
    }
    /// sRGB 0...1 swatch for the little dots and the card.
    var swatch: SIMD3<Float> { flesh.0 }
}

extension JellyPalettes {
    /// A visitor's body colours: the same soft matte treatment as Moss's green and Lavender.
    static func park(_ c: ParkColour) -> Palette {
        switch c {
        case .blue: return PaletteKey.blue.palette
        case .yellow: return PaletteKey.yellow.palette
        case .green: return green
        case .lavender: return lavender
        default: break
        }
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
    /// A visitor's body solves with fewer substeps than a Jelbie's 10 (the same XPBD, a touch softer): the park runs up to 5 soft bodies, and the solver is ~all of its CPU.
    nonisolated(unsafe) static var visitorSubsteps: Int = { let k = UserDefaults.standard.integer(forKey: "ParkVisitorSubsteps"); return k > 0 ? k : 6 }()
    static let poolSize = 16
    /// Chance that a visitor is a MUTATION (one of the variant colours) instead of its species' classic colour; the Jelly Spring's rare rate.
    static let mutationRate: Double = VariantTuning.rareRate
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

    /// A visitor's colour: normally its species' classic colour (blue / yellow / green / lavender, balanced round the pool), rarely (`ParkTuning.mutationRate`) the
    /// mutation colour drawn for it. Own seeded stream, so names, styles and wear are untouched.
    static func visitorColour(index i: Int, mutation: ParkColour, seed: UInt64) -> ParkColour {
        var c = ParkRandom(seed ^ 0xC0_1042 &+ UInt64(i) &* 0x9E37_79B9)
        _ = c.next()
        if Double(c.unit()) < ParkTuning.mutationRate { return mutation }
        return ParkColour.classics[(i + Int(seed % 4)) % 4]
    }

    /// The whole pool: `ParkTuning.poolSize` visitors, every colour used, signatures and items mixed. The same on every device.
    static func generate(count: Int = ParkTuning.poolSize, seed: UInt64 = ParkTuning.poolSeed) -> [ParkVisitor] {
        var r = ParkRandom(seed)
        var colours = ParkColour.mutations.filter { JellyVariantBook.parkEligible($0) }          // the Spring's exclusive variants never appear here
        for i in stride(from: colours.count - 1, to: 0, by: -1) { colours.swapAt(i, Int(r.next() % UInt64(i + 1))) }
        var names = ParkWords.names
        for i in stride(from: names.count - 1, to: 0, by: -1) { names.swapAt(i, Int(r.next() % UInt64(i + 1))) }
        // The signature follows the colour species (ParkColour.speciesFeature). The old random draw is still consumed so names, colours and wear stay identical.
        let signatures: [JellyFeature] = [.none, .none, .none, .spines, .daisy, .wings]
        var out: [ParkVisitor] = []
        for i in 0..<count {
            let style = ParkStyle.allCases[Int(r.next() % UInt64(ParkStyle.allCases.count))]
            _ = r.pick(signatures)
            let colour = visitorColour(index: i, mutation: colours[i % colours.count], seed: seed)
            let sig = colour.speciesFeature
            let wear: WearLook? = r.unit() < 0.45 ? r.pick(wearables) : nil
            let name = names[i % names.count]
            out.append(ParkVisitor(id: i, name: name, colour: colour, signature: sig, wear: wear, style: style,
                                   blurb: ParkWords.blurb(style, &r), greeting: ParkWords.greeting(name, style, &r)))
        }
        return out
    }

    /// The Park friend who plays beside a lone Jelbie at the beach: ONE visitor per calendar day (`dayKey`), so the lobby and the match agree. Only a visitor with no signature feature
    /// (no wings, daisy or spikes) is picked: the lobby draws him on the Jelbie's body in his colour and item, and that is then exactly what plays.
    static func dailyFriend(dayKey: Int, pool: [ParkVisitor] = generate()) -> ParkVisitor {
        var r = ParkRandom(UInt64(bitPattern: Int64(dayKey)) &* 0x9E37_79B9 &+ 0x51ED)
        let plain = pool.filter { $0.signature == .none }
        let from = plain.isEmpty ? pool : plain
        return from[Int(r.next() % UInt64(max(from.count, 1)))]
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
