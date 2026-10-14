import XCTest
@testable import BobV1

@MainActor
final class GameStateTests: XCTestCase {
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var url: URL!

    override func setUpWithError() throws {
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString).appending(path: "save.json")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func makeStore() -> GameStore { GameStore(fileURL: url, now: { [unowned self] in self.clock }) }
    func hours(_ h: Double) { clock = clock.addingTimeInterval(h * 3600) }

    func testSaveLoadRoundTrip() throws {
        let s = makeStore()
        try s.adopt(breed: .mint, name: "Mochi")
        s.feed(s.blobs[0].id)
        try s.persist()
        let s2 = makeStore()
        try s2.load()
        XCTAssertEqual(s2.blobs, s.blobs)
        XCTAssertEqual(s2.blobs[0].breed, .mint)
    }

    func testLoadMissingFileIsFreshGame() throws {
        let s = makeStore()
        try s.load()
        XCTAssertTrue(s.blobs.isEmpty)
    }

    func testAdoptLimitsAndNames() throws {
        let s = makeStore()
        XCTAssertThrowsError(try s.adopt(breed: .berry, name: "   ")) { XCTAssertEqual($0 as? AdoptError, .invalidName) }
        XCTAssertThrowsError(try s.adopt(breed: .berry, name: "ThirteenChars")) { XCTAssertEqual($0 as? AdoptError, .invalidName) }
        try s.adopt(breed: .berry, name: "  Bean  ")
        XCTAssertEqual(s.blobs[0].name, "Bean")
        XCTAssertThrowsError(try s.adopt(breed: .mint, name: "BEAN")) { XCTAssertEqual($0 as? AdoptError, .duplicateName) }
        try s.adopt(breed: .mint, name: "Pip")
        XCTAssertTrue(s.canAdopt)
        try s.adopt(breed: .honey, name: "Zippy")
        XCTAssertFalse(s.canAdopt)
        XCTAssertThrowsError(try s.adopt(breed: .honey, name: "Fourth")) { XCTAssertEqual($0 as? AdoptError, .tooManyBlobs) }
        XCTAssertEqual(s.blobs.count, 3)
    }

    func testOfflineDecay() throws {
        let s = makeStore()
        try s.adopt(breed: .berry, name: "A")
        s.feed(s.blobs[0].id, amount: 1); s.water(s.blobs[0].id, amount: 1)
        try s.persist()
        hours(9)
        s.applyElapsed(now: clock)
        XCTAssertEqual(s.blobs[0].hunger, 0.5, accuracy: 1e-9)          // 9/18
        XCTAssertEqual(s.blobs[0].thirst, 1 - 9.0 / 14, accuracy: 1e-9)
        XCTAssertEqual(s.blobs[0].clean, 0.75, accuracy: 1e-9)          // 9/36
    }

    func testBreedDecayMultiplier() throws {
        let s = makeStore()
        try s.adopt(breed: .honey, name: "H")
        s.feed(s.blobs[0].id, amount: 1)
        try s.persist()
        hours(5)
        s.applyElapsed(now: clock)
        XCTAssertEqual(s.blobs[0].hunger, 1 - 5.0 * 1.3 / 18, accuracy: 1e-9)
    }

    func testOfflineCapAt36Hours() throws {
        let s = makeStore()
        try s.adopt(breed: .berry, name: "A")
        try s.persist()
        hours(1000)
        s.applyElapsed(now: clock)
        XCTAssertEqual(s.blobs[0].hunger, 0)
        XCTAssertEqual(s.blobs[0].thirst, 0)
        XCTAssertEqual(s.blobs[0].clean, 0, accuracy: 1e-9)  // 1.0 - 36/36
    }

    func testBackwardsClockNoDecay() throws {
        let s = makeStore()
        try s.adopt(breed: .berry, name: "A")
        try s.persist()
        let before = s.blobs[0]
        hours(-5)
        s.applyElapsed(now: clock)
        XCTAssertEqual(s.blobs[0], before)
    }

    func testAffectionDriftsTowardHalfNotZero() throws {
        let s = makeStore()
        try s.adopt(breed: .berry, name: "Hi")
        try s.adopt(breed: .berry, name: "Lo")
        for _ in 0..<60 { s.pet(s.blobs[0].id) }   // push up
        let lo = s.blobs[1].id
        s.dirty(lo, amount: 0) // no-op
        try s.persist()
        let hiStart = s.blobs[0].affection
        XCTAssertGreaterThan(hiStart, 0.5)
        hours(36)
        s.applyElapsed(now: clock)
        XCTAssertLessThan(s.blobs[0].affection, hiStart)
        XCTAssertGreaterThanOrEqual(s.blobs[0].affection, 0.5)
        // Long absence repeatedly: stays at 0.5, never 0
        for _ in 0..<10 { hours(36); s.applyElapsed(now: clock) }
        XCTAssertEqual(s.blobs[0].affection, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.blobs[1].affection, 0.5, accuracy: 1e-9)
    }

    func testWordThresholds() {
        XCTAssertEqual(HungerLevel(0.75), .full)
        XCTAssertEqual(HungerLevel(0.74), .normal)
        XCTAssertEqual(HungerLevel(0.45), .normal)
        XCTAssertEqual(HungerLevel(0.44), .hungry)
        XCTAssertEqual(HungerLevel(0.2), .hungry)
        XCTAssertEqual(HungerLevel(0.19), .famished)
        XCTAssertEqual(ThirstLevel(1), .quenched)
        XCTAssertEqual(ThirstLevel(0.1), .parched)
        XCTAssertEqual(CleanLevel(0.8), .sparkling)
        XCTAssertEqual(CleanLevel(0.3), .grubby)
        XCTAssertEqual(CleanLevel(0), .filthy)
    }

    func testMood() {
        XCTAssertEqual(Mood.compute(hunger: 1, thirst: 1, clean: 1, affection: 1), .ecstatic)
        XCTAssertEqual(Mood.compute(hunger: 0.7, thirst: 0.7, clean: 0.7, affection: 0.5), .happy)
        XCTAssertEqual(Mood.compute(hunger: 0.4, thirst: 0.4, clean: 0.4, affection: 0.5), .content)
        XCTAssertEqual(Mood.compute(hunger: 0, thirst: 0, clean: 0, affection: 0.5), .glum)
        XCTAssertEqual(Mood.score(hunger: 1, thirst: 0.4, clean: 1, affection: 0.5), 0.6 * 0.4 + 0.4 * 0.8, accuracy: 1e-9)
    }

    func testPettingDiminishingReturns() throws {
        let s = makeStore()
        try s.adopt(breed: .berry, name: "A")
        let id = s.blobs[0].id
        let full = 0.02 * 1.4
        for _ in 0..<10 { XCTAssertEqual(s.pet(id), full, accuracy: 1e-9) }
        XCTAssertEqual(s.pet(id), full / 2, accuracy: 1e-9)
        // New window after 5 minutes restores full gain.
        clock = clock.addingTimeInterval(301)
        XCTAssertEqual(s.pet(id), full, accuracy: 1e-9)
    }

    func testBreedTableComplete() {
        for b in BreedID.allCases { XCTAssertEqual(b.spec.id, b) }
        XCTAssertEqual(NameSuggester.names.count, 30)
        XCTAssertEqual(Set(NameSuggester.names).count, 30)
        XCTAssertTrue(NameSuggester.names.allSatisfy { (1...12).contains($0.count) })
    }

    func testCandidatesDistinctAndDeterministic() {
        for breed in BreedID.allCases {
            for seed in [1, 2, 99, 12345] as [UInt64] {
                let c = KennelGenerator.candidates(for: breed, seed: seed)
                XCTAssertEqual(c.count, 3)
                XCTAssertEqual(Set(c.map(\.personality)).count, 3)
                XCTAssertEqual(Set(c.map(\.look)).count, 3)
                XCTAssertEqual(Set(c.map(\.suggestedName)).count, 3)
                XCTAssertEqual(Set(c.map(\.id)).count, 3)
                XCTAssertEqual(Set(c.map(\.look.marking)).count, 3)
                XCTAssertTrue(c.allSatisfy { $0.breed == breed })
                XCTAssertEqual(c, KennelGenerator.candidates(for: breed, seed: seed))
            }
        }
        XCTAssertNotEqual(KennelGenerator.candidates(for: .berry, seed: 1).map(\.look),
                          KennelGenerator.candidates(for: .berry, seed: 2).map(\.look))
    }

    func testColourShiftWithinBounds() {
        for breed in BreedID.allCases {
            let spec = breed.spec
            for shade in stride(from: Float(-1), through: 1, by: 0.25) {
                let look = BlobLook(shade: shade)
                let cols = look.colors(for: breed)
                for (base, out) in [(spec.colorHexCore, cols.core), (spec.colorHexLight, cols.light), (spec.colorHexDeep, cols.deep)] {
                    let (h0, _, l0) = BlobLook.hexToHSL(base)
                    let (h1, _, l1) = BlobLook.hexToHSL(out)
                    var dh = abs(h1 - h0); if dh > 180 { dh = 360 - dh }
                    XCTAssertLessThanOrEqual(dh, 8 + 1.5)      // 8-bit quantisation slack
                    XCTAssertLessThanOrEqual(abs(l1 - l0), 0.06 + 0.01)
                }
            }
            XCTAssertEqual(BlobLook().colors(for: breed).core, spec.colorHexCore)
        }
    }

    func testAdoptCandidateAndPersonalityRoundTrip() throws {
        let s = makeStore()
        let cand = KennelGenerator.candidates(for: .honey, seed: 7)[1]
        try s.adopt(candidate: cand, name: cand.suggestedName)
        try s.persist()
        let s2 = makeStore(); try s2.load()
        XCTAssertEqual(s2.blobs[0].personality, cand.personality)
        XCTAssertEqual(s2.blobs[0].look, cand.look)
        XCTAssertEqual(BreedID.honey.spec.feature, .curlyAntenna)
        XCTAssertEqual(BreedID.mint.spec.feature, .dorsalSpikes)
    }

    func testDecodeV1SaveWithoutNewFields() throws {
        let json = """
        {"version":1,"lastSaved":"2026-10-13T10:00:00Z","blobs":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
        "name":"Old","breed":"berry","hunger":0.5,"thirst":0.5,"clean":0.5,"affection":0.5,
        "adoptedAt":"2026-10-12T10:00:00Z"}]}
        """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: url, atomically: true, encoding: .utf8)
        let s = makeStore()
        try s.load()
        XCTAssertEqual(s.blobs.count, 1)
        XCTAssertEqual(s.blobs[0].personality, .curious)
        XCTAssertEqual(s.blobs[0].look, BlobLook())
    }

    func testShyWarmsSlowlyThenFaster() throws {
        let s = makeStore()
        try s.adopt(breed: .berry, name: "S", personality: .shy)
        let id = s.blobs[0].id
        let early = s.pet(id)
        XCTAssertEqual(early, 0.02 * 1.4 * 0.6, accuracy: 1e-9)
    }

    func testCandidatesDifferInMultipleLookAttributes() {
        for breed in BreedID.allCases {
            for seed in [3, 4, 5] as [UInt64] {
                let looks = KennelGenerator.candidates(for: breed, seed: seed).map(\.look)
                var differing = 0
                if Set(looks.map(\.shade)).count == 3 { differing += 1 }
                if Set(looks.map(\.marking)).count == 3 { differing += 1 }
                if Set(looks.map(\.sizeScale)).count == 3 { differing += 1 }
                if Set(looks.map(\.featureScale)).count == 3 { differing += 1 }
                if Set(looks.map(\.featureCount)).count == 3 { differing += 1 }
                XCTAssertGreaterThanOrEqual(differing, 2)
                for l in looks {
                    XCTAssertTrue(BlobLook.featureCountRange(for: breed).contains(l.featureCount))
                    XCTAssertTrue(BlobLook.featureScaleRange.contains(l.featureScale))
                    XCTAssertTrue(BlobLook.sizeRange.contains(l.sizeScale))
                }
            }
        }
        // Mint: one clearly larger-spiked candidate.
        let mint = KennelGenerator.candidates(for: .mint, seed: 3).map(\.look.featureScale)
        XCTAssertGreaterThan(mint.max()! - mint.min()!, 0.2)
    }
}
