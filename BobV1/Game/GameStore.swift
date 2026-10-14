import Foundation
import Observation

enum AdoptError: Error, Equatable {
    case tooManyBlobs
    case invalidName
    case duplicateName
}

@Observable
nonisolated final class GameStore {
    static let maxBlobs = 3
    static let maxOfflineSeconds: TimeInterval = 36 * 3600
    static let baseHungerSeconds: TimeInterval = 18 * 3600
    static let baseThirstSeconds: TimeInterval = 14 * 3600
    static let baseCleanSeconds: TimeInterval = 36 * 3600
    static let affectionDriftSeconds: TimeInterval = 72 * 3600
    static let affectionNeutral = 0.5
    static let petWindow: TimeInterval = 5 * 60
    static let petFreeStrokes = 10
    static let petBaseGain = 0.02

    private(set) var blobs: [BlobState] = []
    private(set) var lastSaved: Date

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = GameStore.defaultFileURL(), now: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.now = now
        self.lastSaved = now()
    }

    static func defaultFileURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "BobSave.json")
    }

    var canAdopt: Bool { blobs.count < Self.maxBlobs }

    func blob(_ id: UUID) -> BlobState? { blobs.first { $0.id == id } }

    // MARK: Persistence

    /// Loads the save if present (missing file = fresh game). Throws on unreadable/corrupt data.
    func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let save = try dec.decode(GameSave.self, from: data)
        blobs = save.blobs
        lastSaved = save.lastSaved
    }

    func persist() throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lastSaved = now()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(GameSave(blobs: blobs, lastSaved: lastSaved))
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: Decay

    /// Applies offline/elapsed decay since `lastSaved` (capped at 36h; backwards clock = none).
    func applyElapsed(now current: Date? = nil) {
        let t = current ?? now()
        let elapsed = min(max(0, t.timeIntervalSince(lastSaved)), Self.maxOfflineSeconds)
        if elapsed > 0 {
            for i in blobs.indices {
                let d = blobs[i].breed.spec.decay
                blobs[i].hunger = clamp(blobs[i].hunger - elapsed / (Self.baseHungerSeconds / d.hunger))
                blobs[i].thirst = clamp(blobs[i].thirst - elapsed / (Self.baseThirstSeconds / d.thirst))
                blobs[i].clean = clamp(blobs[i].clean - elapsed / (Self.baseCleanSeconds / d.clean))
                // Drift toward 0.5 without overshooting.
                let step = elapsed / (Self.affectionDriftSeconds / d.affection) * Self.affectionNeutral
                let a = blobs[i].affection
                blobs[i].affection = a > Self.affectionNeutral
                    ? max(Self.affectionNeutral, a - step)
                    : min(Self.affectionNeutral, a + step)
            }
        }
        // Re-anchor (also handles a backwards clock).
        lastSaved = t
    }

    // MARK: Actions

    func adopt(breed: BreedID, name: String,
               personality: Personality = .curious, look: BlobLook = BlobLook()) throws {
        guard canAdopt else { throw AdoptError.tooManyBlobs }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...12).contains(trimmed.count) else { throw AdoptError.invalidName }
        guard !blobs.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw AdoptError.duplicateName
        }
        blobs.append(BlobState(id: UUID(), name: trimmed, breed: breed,
                               hunger: 0.8, thirst: 0.8, clean: 1.0, affection: 0.5,
                               adoptedAt: now(), personality: personality, look: look))
    }

    func adopt(candidate: AdoptionCandidate, name: String) throws {
        try adopt(breed: candidate.breed, name: name, personality: candidate.personality, look: candidate.look)
    }

    func feed(_ id: UUID, amount: Double = 0.5) { mutate(id) { $0.hunger = clamp($0.hunger + amount) } }
    func water(_ id: UUID, amount: Double = 0.5) { mutate(id) { $0.thirst = clamp($0.thirst + amount) } }
    func bathe(_ id: UUID, amount: Double) { mutate(id) { $0.clean = clamp($0.clean + amount) } }
    func dirty(_ id: UUID, amount: Double) { mutate(id) { $0.clean = clamp($0.clean - amount) } }

    /// One stroke. Returns the affection gained (0 if unknown id).
    @discardableResult
    func pet(_ id: UUID) -> Double {
        var gained = 0.0
        let t = now()
        mutate(id) { b in
            if let start = b.petWindowStart, t.timeIntervalSince(start) >= 0, t.timeIntervalSince(start) < Self.petWindow {
                b.petWindowStrokes += 1
            } else {
                b.petWindowStart = t
                b.petWindowStrokes = 1
            }
            var gain = Self.petBaseGain * b.breed.spec.affectionGain
                * b.personality.mods.affectionMultiplier(at: b.affection)
            if b.petWindowStrokes > Self.petFreeStrokes { gain *= 0.5 }
            let before = b.affection
            b.affection = clamp(b.affection + gain)
            b.lastPetAt = t
            gained = b.affection - before
        }
        return gained
    }

    // MARK: Helpers

    private func mutate(_ id: UUID, _ f: (inout BlobState) -> Void) {
        guard let i = blobs.firstIndex(where: { $0.id == id }) else { return }
        f(&blobs[i])
    }
}

private func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
