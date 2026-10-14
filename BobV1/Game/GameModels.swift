import Foundation

struct BlobState: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var breed: BreedID
    var hunger: Double      // 1 = full
    var thirst: Double      // 1 = quenched
    var clean: Double       // 1 = sparkling
    var affection: Double
    var adoptedAt: Date
    var lastPetAt: Date?
    /// Start of the current petting window and strokes within it (for diminishing returns).
    var petWindowStart: Date?
    var petWindowStrokes: Int = 0
    var personality: Personality = .curious
    var look: BlobLook = BlobLook()

    init(id: UUID, name: String, breed: BreedID, hunger: Double, thirst: Double, clean: Double,
         affection: Double, adoptedAt: Date, lastPetAt: Date? = nil, petWindowStart: Date? = nil,
         petWindowStrokes: Int = 0, personality: Personality = .curious, look: BlobLook = BlobLook()) {
        self.id = id; self.name = name; self.breed = breed
        self.hunger = hunger; self.thirst = thirst; self.clean = clean; self.affection = affection
        self.adoptedAt = adoptedAt; self.lastPetAt = lastPetAt
        self.petWindowStart = petWindowStart; self.petWindowStrokes = petWindowStrokes
        self.personality = personality; self.look = look
    }

    /// Tolerant decoding: fields added after v1 fall back to defaults.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        breed = try c.decode(BreedID.self, forKey: .breed)
        hunger = try c.decode(Double.self, forKey: .hunger)
        thirst = try c.decode(Double.self, forKey: .thirst)
        clean = try c.decode(Double.self, forKey: .clean)
        affection = try c.decode(Double.self, forKey: .affection)
        adoptedAt = try c.decode(Date.self, forKey: .adoptedAt)
        lastPetAt = try c.decodeIfPresent(Date.self, forKey: .lastPetAt)
        petWindowStart = try c.decodeIfPresent(Date.self, forKey: .petWindowStart)
        petWindowStrokes = try c.decodeIfPresent(Int.self, forKey: .petWindowStrokes) ?? 0
        personality = (try? c.decodeIfPresent(Personality.self, forKey: .personality)) ?? .curious
        look = (try? c.decodeIfPresent(BlobLook.self, forKey: .look)) ?? BlobLook()
    }

    // Effective traits (breed x personality).
    var energy: Double { min(1, breed.spec.energy * personality.mods.energy) }
    var playfulness: Double { min(1, breed.spec.playfulness * personality.mods.playfulness) }
    var idleWeights: IdleWeights { breed.spec.idleWeights.scaled(by: personality.mods.idle) }

    var hungerLevel: HungerLevel { HungerLevel(hunger) }
    var thirstLevel: ThirstLevel { ThirstLevel(thirst) }
    var cleanLevel: CleanLevel { CleanLevel(clean) }
    var mood: Mood { Mood.compute(hunger: hunger, thirst: thirst, clean: clean, affection: affection) }
}

struct GameSave: Codable {
    static let currentVersion = 2
    var version = GameSave.currentVersion
    var blobs: [BlobState]
    var lastSaved: Date

    init(blobs: [BlobState], lastSaved: Date) { self.blobs = blobs; self.lastSaved = lastSaved }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        blobs = try c.decode([BlobState].self, forKey: .blobs)
        lastSaved = try c.decode(Date.self, forKey: .lastSaved)
    }
}

private func level4(_ v: Double) -> Int { v >= 0.75 ? 0 : v >= 0.45 ? 1 : v >= 0.2 ? 2 : 3 }

enum HungerLevel: String, CaseIterable {
    case full = "Full", normal = "Normal", hungry = "Hungry", famished = "Famished"
    init(_ v: Double) { self = Self.allCases[level4(v)] }
}
enum ThirstLevel: String, CaseIterable {
    case quenched = "Quenched", normal = "Normal", thirsty = "Thirsty", parched = "Parched"
    init(_ v: Double) { self = Self.allCases[level4(v)] }
}
enum CleanLevel: String, CaseIterable {
    case sparkling = "Sparkling", clean = "Clean", grubby = "Grubby", filthy = "Filthy"
    init(_ v: Double) { self = Self.allCases[level4(v)] }
}

enum Mood: String, CaseIterable {
    case ecstatic = "Ecstatic", happy = "Happy", content = "Content", glum = "Glum"

    static func score(hunger h: Double, thirst t: Double, clean c: Double, affection a: Double) -> Double {
        0.6 * min(h, t, c) + 0.4 * ((h + t + c) / 3) + 0.3 * (a - 0.5)
    }
    static func compute(hunger: Double, thirst: Double, clean: Double, affection: Double) -> Mood {
        let s = score(hunger: hunger, thirst: thirst, clean: clean, affection: affection)
        return s >= 0.75 ? .ecstatic : s >= 0.5 ? .happy : s >= 0.25 ? .content : .glum
    }
}
