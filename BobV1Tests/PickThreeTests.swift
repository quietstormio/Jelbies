//
//  PickThreeTests.swift
//  "Pick one of three" in the Adoption Center: the three candidates of a species are a pure function of (species, day, classic, owned); the picker's scratch ids stay out of every
//  save; the picked jars seed the starting stats (and survive a reset); the row geometry lines up. Fast and pure: own UserDefaults suites; the process-wide book is put back.
//

import XCTest
@testable import BobV1

@MainActor
final class PickThreeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when a GameCare is released (see MelonModel)

    private var suites: [String] = []
    private var savedCurrent: [Int] = []

    override func setUp() { savedCurrent = JellyRoster.current }
    override func tearDown() {
        JellyRoster.current = savedCurrent
        JellyTraitsBook.reload()
        JellyVariants.reload()
        JellyVariants.clearPreviews()
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
    }
    private func suite(_ name: String = "x") -> UserDefaults {
        let n = "PickThreeTests.\(name).\(UUID().uuidString)"
        suites.append(n)
        return UserDefaults(suiteName: n)!
    }

    // MARK: candidates

    func testCandidatesAreDeterministicAndKeyedByDayOwnedAndClassic() {
        let a = JellyCandidates.make(species: 1, dayKey: 800_000, classic: false, owned: 0)
        XCTAssertEqual(a, JellyCandidates.make(species: 1, dayKey: 800_000, classic: false, owned: 0))
        XCTAssertEqual(a.count, 3)
        var orders = Set<[JellyPersonality]>()
        for d in 800_000..<800_030 { orders.insert(JellyCandidates.make(species: 0, dayKey: d, classic: false, owned: 0).map(\.traits.personality)) }
        XCTAssertGreaterThanOrEqual(orders.count, 20, "a different day mostly shows a different three")
        XCTAssertNotEqual(a.map(\.traits), JellyCandidates.make(species: 1, dayKey: 800_000, classic: false, owned: 1).map(\.traits), "owning one changes the set")
        XCTAssertNotEqual(a.map(\.traits), JellyCandidates.make(species: 1, dayKey: 800_000, classic: true, owned: 0).map(\.traits), "classic changes the set")
        XCTAssertTrue(JellyCandidates.make(species: 1, dayKey: 800_000, classic: true, owned: 0).allSatisfy { $0.variant == nil })
    }

    func testThreeDistinctWordsAndSnacksWithSaneJarsForEverySpecies() {
        for s in 0..<JellyRoster.knownCount {
            for d in 800_000..<800_060 {
                let c = JellyCandidates.make(species: s, dayKey: d, classic: s >= 4, owned: d % 3)
                XCTAssertEqual(Set(c.map(\.traits.personality)).count, 3, "species \(s) day \(d)")
                XCTAssertEqual(Set(c.map(\.traits.snack)).count, 3, "species \(s) day \(d)")
                for x in c {
                    XCTAssertNotNil(Consumables.with(id: x.traits.snack), x.traits.snack)
                    XCTAssertEqual(x.traits.jars.count, 5)
                    XCTAssertTrue(x.traits.jars.allSatisfy { JellyTraitsTuning.jarRange.contains($0) })
                    XCTAssertEqual(JellyRoster.species(x.previewID), s)
                    XCTAssertTrue(x.personality_blurbFits)
                }
                XCTAssertEqual(Set(c.map(\.previewID)).count, 3, "three distinct scratch ids")
            }
        }
    }

    func testShadesAreThreeSlotsWithTheRareOneAtMostOnce() {
        for s in 0...3 {
            for d in 800_000..<800_200 {
                let sh = JellyVariantBook.shades(species: s, dayKey: d, owned: 0)
                XCTAssertEqual(sh.count, 3)
                XCTAssertNil(sh[0], "slot 0 is the classic colour")
                XCTAssertLessThanOrEqual(sh.filter { $0?.rare == true }.count, 1)
                for v in sh.compactMap({ $0 }) where !v.rare { XCTAssertTrue(v.title == "Soft" || v.title == "Deep", "non-rare slots are the species' own Soft / Deep shades") }
                if let o = JellyVariantBook.offer(species: s, dayKey: d) { XCTAssertTrue(sh.contains { $0 == o }, "the rare mutation is in a slot unchanged") }
                else { XCTAssertNotEqual(sh[1]?.flesh, sh[2]?.flesh, "two different tones on a classic day") }
            }
        }
        for s in 4...6 { XCTAssertEqual(JellyVariantBook.shades(species: s, dayKey: 800_000, owned: 0).compactMap { $0 }.count, 0) }
    }

    func testOnlyTheRareCandidateCostsMore() {
        XCTAssertEqual(AdoptionPrice.next(home: 1, rare: true), AdoptionPrice.second + AdoptionPrice.rareSurcharge)
        XCTAssertEqual(AdoptionPrice.next(home: 1, rare: false), AdoptionPrice.second)
        XCTAssertEqual(AdoptionPrice.next(home: 1, special: true), AdoptionPrice.special)
        for d in 800_000..<800_400 {
            let c = AdoptionCenter.makeCandidates(mode: .more, species: 0, dayKey: d, home: [1])
            XCTAssertLessThanOrEqual(c.filter { $0.variant?.rare == true }.count, 1)
        }
        XCTAssertTrue(AdoptionCenter.makeCandidates(mode: .more, species: JellyRoster.teddyID, dayKey: 800_000, home: [0]).allSatisfy { $0.variant == nil }, "specials: classic for all three")
    }

    // MARK: ids

    func testEveryPreviewIDRoundTripsAndOnlyAPreviewGameCareKeepsThem() {
        var seen = Set<Int>()
        for s in 0..<JellyRoster.knownCount {
            for k in 0..<JellyRoster.previewSlots {
                let id = JellyRoster.previewID(species: s, slot: k)
                XCTAssertTrue(seen.insert(id).inserted, "unique")
                XCTAssertEqual(JellyRoster.species(id), s)
                XCTAssertEqual(JellyRoster.previewSlot(id), k)
                XCTAssertTrue(JellyRoster.isValid(id))
                XCTAssertTrue(JellyRoster.isPreview(id))
            }
            XCTAssertEqual(JellyRoster.previewID(s), JellyRoster.previewID(species: s, slot: 0), "slot 0 is the single page's id")
        }
        XCTAssertFalse(JellyRoster.isValid(1007))
        XCTAssertFalse(JellyRoster.isValid(1000 + 3 * 10))
    }

    func testSanitisedDropsPreviewIDsFromSavesButAPreviewGameCareKeepsThem() {
        let p = (0..<3).map { JellyRoster.previewID(species: 2, slot: $0) }
        XCTAssertEqual(JellyRoster.sanitised(p), JellyRoster.defaultIDs, "nothing survives: the default roster")
        XCTAssertEqual(JellyRoster.sanitised(p, allowPreview: true), p)
        XCTAssertEqual(JellyRoster.sanitised([1, p[0], 2]), [1, 2])
        let d = suite()
        JellyRoster.save([0, p[1], p[2]], to: d)
        XCTAssertEqual(JellyRoster.savedIDs(d), [0])
        d.set(p, forKey: JellyRoster.rosterKey)
        XCTAssertEqual(JellyRoster.savedIDs(d), JellyRoster.defaultIDs)
        JellyTraitsBook.adopt(p[0], JellyTraits(personality: .brave, jars: [50, 50, 50, 50, 50], snack: "taco"), d)
        XCTAssertNil(JellyTraitsBook.record(p[0]), "a scratch id never gets a record")
    }

    func testAPreviewGameCareStandsThreeOfOneSpeciesWithTheirOwnNames() {
        let ids = (0..<3).map { JellyRoster.previewID(species: 1, slot: $0) }
        JellyRoster.current = ids
        let care = GameCare(roster: ids, persistent: false, preview: true)
        Self.keep.append(care)
        XCTAssertEqual(care.jellies.map(\.character), ids)
        XCTAssertEqual(care.jellies.map(\.name), ["Pip", "Pip", "Pip"])
        XCTAssertEqual(care.jellies.map(\.species), [1, 1, 1])
    }

    // MARK: seeds

    func testSeedBoundsFollowTheJars() {
        for jars in [[15, 15, 15, 15, 15], [98, 98, 98, 98, 98], [50, 45, 30, 85, 55]] {
            let s = StatTuning.seed(jars: jars)
            XCTAssertTrue((0.30...0.65).contains(s.waddle), "\(s.waddle)")
            XCTAssertTrue((0.35...0.70).contains(s.focus), "\(s.focus)")
            XCTAssertTrue(s.cond.allSatisfy { $0 <= StatTuning.condSeedScale + 1e-6 })
        }
        let s = StatTuning.seed(jars: [50, 45, 30, 85, 55])         // Cute, Sweet, Sparkly, Cool, Sporty
        XCTAssertEqual(s.cond[ConditionKey.cool.rawValue], 0.85 * 0.25, accuracy: 1e-5)
        XCTAssertEqual(s.cond[ConditionKey.sweet.rawValue], 0.45 * 0.25, accuracy: 1e-5, "the jar order is not the enum order")
        XCTAssertEqual(s.floor[ConditionKey.cool.rawValue], 0.85 * 0.25 * 0.5, accuracy: 1e-5)
    }

    func testTheJarsSeedAJelbiesStartingStatsOnceAndKeepAnInnateFloor() {
        let d = suite()
        let key = "BlobStats.v1.jelly77"
        let jars = [50, 45, 30, 85, 55]
        let seed = StatTuning.seed(jars: jars)
        var t = Date(timeIntervalSince1970: 1_000_000)
        let a = JellyStats(persists: true, defaults: d, key: key, seedWaddle: 0.5, traitSeed: seed, now: { t })
        XCTAssertEqual(a.waddle, seed.waddle, accuracy: 1e-5)
        XCTAssertEqual(a.focus, seed.focus, accuracy: 1e-5)
        XCTAssertEqual(a.condition(.cool), 0.85 * 0.25, accuracy: 1e-5)
        a.set(waddle: 0.9)
        let b = JellyStats(persists: true, defaults: d, key: key, seedWaddle: 0.5, traitSeed: seed, now: { t })
        XCTAssertEqual(b.waddle, 0.9, accuracy: 1e-5, "built again: not re-seeded")
        t = t.addingTimeInterval(30 * 24 * 3600)          // a month: the plain decay would be zero
        XCTAssertEqual(b.condition(.cool), 0.85 * 0.25 * 0.5, accuracy: 1e-5, "never below half the seed")
        let plain = JellyStats(persists: false, key: key, now: { t })
        plain.setCondition(.cool, 0.2)
        t = t.addingTimeInterval(30 * 24 * 3600)
        XCTAssertEqual(plain.condition(.cool), 0, accuracy: 1e-6, "a Jelbie with no record decays to zero as before")
    }

    func testAStaleCondKeyIsOverwrittenOnFirstSeed() {
        let d = suite()
        let key = "BlobStats.v1.jelly78"
        d.set([0.9, 0.9, 0.9, 0.9, 0.9, Date().timeIntervalSince1970], forKey: key + ".cond")
        let seed = StatTuning.seed(jars: [20, 20, 20, 20, 20])
        let s = JellyStats(persists: true, defaults: d, key: key, traitSeed: seed)
        XCTAssertEqual(s.condition(.cute), 0.2 * 0.25, accuracy: 1e-4)
    }

    func testResetKeepsTheTraitsRecordSoTheSecondResetOfFinishFirstDayReseeds() {
        let d = suite()
        let id = 79
        let t = JellyTraits(personality: .brave, jars: [40, 40, 40, 90, 70], snack: "taco")
        JellyTraitsBook.adopt(id, t, d)
        let key = JellyKeys.stats(id)
        let seed = { JellyTraitsBook.record(id).map { StatTuning.seed(jars: $0.jars) } }
        let a = JellyStats(persists: true, defaults: d, key: key, traitSeed: seed())
        a.nudge([.cool: 0.1], food: "Taco")
        StartFlow.resetCharacterState(id, d)
        for suffix in ["", ".cond", ".meals", ".dances"] { XCTAssertNil(d.object(forKey: key + suffix), "reset clears \(suffix)") }
        XCTAssertEqual(JellyTraitsBook.record(id), t, "the traits record survives a reset")
        let b = JellyStats(persists: true, defaults: d, key: key, traitSeed: seed())
        XCTAssertEqual(b.condition(.cool), 0.9 * 0.25, accuracy: 1e-5, "seeded again from the surviving record")
        JellyTraitsBook.reload(d)
        XCTAssertEqual(JellyTraitsBook.record(id), t, "round trip through the save")
        let empty = suite()
        JellyTraitsBook.reload(empty)
        XCTAssertNil(JellyTraitsBook.record(id), "a wipe-style reload empties it")
        let old = JellyStats(persists: false, seedWaddle: StatTuning.seedWaddle(careLevels: [1, 1, 1]), traitSeed: nil)
        XCTAssertEqual(old.waddle, 0.65, accuracy: 1e-5, "no record: the care seed as before")
    }

    // MARK: row geometry

    func testThePreviewRowIsWhatTheFocusGroupLinesUpOn() {
        let row = GameCamera.pickRowSpots(count: 3)
        XCTAssertEqual(row.count, 3)
        let g = FocusGroup()
        g.rowSpacing = GameCamera.pickRowSpacing
        g.begin(ids: [0, 1, 2])
        XCTAssertEqual(g.slots, row)
        XCTAssertEqual(GameCamera.previewRowSpots(count: 1), [FreeFloor.nearest(to: GameCamera.callSpot)])
    }

    func testTheRowProjectsLeftToRightInsideTheStageWithAMargin() {
        PhotoCam.active = true
        defer { PhotoCam.active = false; PhotoCam.reset() }
        for species in 0..<JellyRoster.knownCount {
            PhotoCam.reset(); PhotoCam.zoom = PickerCamera.rowZoom; PhotoCam.yaw = PickerCamera.rowYaw(species); PhotoCam.active = true
            let p = GameCamera.projectRow(spots: GameCamera.pickRowSpots(count: 3))
            let order = PickerRow.slotOfCandidate.map { p[$0] }          // candidate 0, 1, 2 left to right
            XCTAssertLessThan(order[0].foot.x, order[1].foot.x)
            XCTAssertLessThan(order[1].foot.x, order[2].foot.x)
            for q in p {
                XCTAssertGreaterThan(q.foot.x - q.bodyW / 2, 0.04, "species \(species)")
                XCTAssertLessThan(q.foot.x + q.bodyW / 2, 0.96, "species \(species)")
                XCTAssertGreaterThan(q.top.y, 0.02)
                XCTAssertLessThan(q.foot.y, 0.98)
            }
        }
    }
}

private extension JellyCandidate {
    /// The personality's one-line blurb fits its 34-character rule.
    var personality_blurbFits: Bool { traits.personality.blurb.count <= 34 }
}
