import Foundation

enum BreedID: String, Codable, CaseIterable, Identifiable {
    case berry, mint, honey
    var id: String { rawValue }
    var spec: BreedSpec { BreedSpec.table[self]! }
}

struct BreedProportions: Equatable {
    var heightScale: Float
    var widthScale: Float
    var armScale: Float
    var footScale: Float
}

struct IdleWeights: Equatable {
    var wander: Double
    var hop: Double
    var roll: Double
    var sit: Double
    var lookAtCamera: Double
    var nap: Double
}

struct DecayMultipliers: Equatable {
    var hunger: Double
    var thirst: Double
    var clean: Double
    var affection: Double
}

enum BreedFeature: String, Codable {
    case none
    case dorsalSpikes   // soft gummy spikes down the centre of the head to the back
    case curlyAntenna    // springy curly antenna with a bobble on top of the head
}

struct IdleWeightMultipliers: Equatable {
    var wander = 1.0, hop = 1.0, roll = 1.0, sit = 1.0, lookAtCamera = 1.0, nap = 1.0
}

extension IdleWeights {
    func scaled(by m: IdleWeightMultipliers) -> IdleWeights {
        IdleWeights(wander: wander * m.wander, hop: hop * m.hop, roll: roll * m.roll,
                    sit: sit * m.sit, lookAtCamera: lookAtCamera * m.lookAtCamera, nap: nap * m.nap)
    }
}

/// Data-only description of a breed.
struct BreedSpec: Equatable {
    var id: BreedID
    var displayName: String
    var blurb: String
    var colorHexCore: String
    var colorHexLight: String
    var colorHexDeep: String
    var proportions: BreedProportions
    var energy: Double
    var playfulness: Double
    var affectionGain: Double
    var decay: DecayMultipliers
    var idleWeights: IdleWeights
    var feature: BreedFeature

    static let berry = BreedSpec(
        id: .berry, displayName: "Berry",
        blurb: "The classic Blob: raspberry-sweet and always up for cuddles.",
        colorHexCore: "#D3155A", colorHexLight: "#F2679A", colorHexDeep: "#8A0B3A",
        proportions: BreedProportions(heightScale: 1.0, widthScale: 1.0, armScale: 1.0, footScale: 1.0),
        energy: 0.6, playfulness: 0.6, affectionGain: 1.4,
        decay: DecayMultipliers(hunger: 1.0, thirst: 1.0, clean: 1.0, affection: 1.0),
        idleWeights: IdleWeights(wander: 1.0, hop: 1.0, roll: 0.6, sit: 1.0, lookAtCamera: 1.6, nap: 0.6),
        feature: .none)

    static let mint = BreedSpec(
        id: .mint, displayName: "Mint",
        blurb: "Round, calm and cool as a minty breeze.",
        colorHexCore: "#2FB8A0", colorHexLight: "#8BE6D3", colorHexDeep: "#177564",
        proportions: BreedProportions(heightScale: 0.88, widthScale: 1.15, armScale: 0.9, footScale: 1.1),
        energy: 0.3, playfulness: 0.4, affectionGain: 1.0,
        decay: DecayMultipliers(hunger: 0.8, thirst: 1.0, clean: 1.0, affection: 1.0),
        idleWeights: IdleWeights(wander: 0.6, hop: 0.4, roll: 0.5, sit: 1.8, lookAtCamera: 1.0, nap: 1.8),
        feature: .dorsalSpikes)

    static let honey = BreedSpec(
        id: .honey, displayName: "Honey",
        blurb: "Slim, sunny and bouncing off the walls.",
        colorHexCore: "#F2A325", colorHexLight: "#FFD27A", colorHexDeep: "#B86F0A",
        proportions: BreedProportions(heightScale: 1.15, widthScale: 0.88, armScale: 1.1, footScale: 0.92),
        energy: 0.9, playfulness: 0.9, affectionGain: 0.9,
        decay: DecayMultipliers(hunger: 1.3, thirst: 1.0, clean: 1.0, affection: 1.0),
        idleWeights: IdleWeights(wander: 1.6, hop: 2.0, roll: 1.4, sit: 0.4, lookAtCamera: 0.8, nap: 0.3),
        feature: .curlyAntenna)

    static let table: [BreedID: BreedSpec] = [.berry: berry, .mint: mint, .honey: honey]
}

enum NameSuggester {
    static let names: [String] = [
        "Bobby", "Jelly", "Pudding", "Wobble", "Gumdrop", "Mochi", "Bean", "Squish", "Biscuit", "Noodle",
        "Pebble", "Sprinkle", "Muffin", "Boba", "Jiggles", "Pip", "Waffles", "Truffle", "Marshmallow", "Dumpling",
        "Button", "Cupcake", "Doodle", "Fizz", "Gizmo", "Honeydew", "Nibbles", "Pickle", "Taffy", "Zippy"
    ]

    static func shuffled<G: RandomNumberGenerator>(using g: inout G) -> [String] { names.shuffled(using: &g) }

    static func random() -> String { names.randomElement()! }

    /// Picks a name not already used (case-insensitive) when possible.
    static func random(excluding used: [String]) -> String {
        let lower = Set(used.map { $0.lowercased() })
        return names.filter { !lower.contains($0.lowercased()) }.randomElement() ?? random()
    }
}
