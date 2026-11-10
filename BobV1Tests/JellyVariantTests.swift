import Testing
import Foundation
import simd
@testable import BobV1

@MainActor
struct JellyVariantTests {
    @Test func dailyOfferIsDeterministic() {
        for day in 700_000..<700_040 {
            for s in 0...3 { #expect(JellyVariantBook.offer(species: s, dayKey: day) == JellyVariantBook.offer(species: s, dayKey: day)) }
        }
        // The Spring shows the species' own colour: every non-nil offer is a rare exclusive, never a Park-table colour.
        for day in 700_000..<700_400 { for s in 0...3 { if let o = JellyVariantBook.offer(species: s, dayKey: day) { #expect(o.rare && JellyVariantBook.exclusives.contains(o)) } } }
        #expect(JellyVariantBook.offer(species: 4, dayKey: 1) == nil)          // Teddy / Pearl / Panda are never offered variants
    }

    @Test func rareRateWithinBounds() {
        var rare = 0, n = 0
        for day in 0..<5000 { for s in 0...3 { n += 1; if JellyVariantBook.offer(species: s, dayKey: day)?.rare == true { rare += 1 } } }
        let rate = Double(rare) / Double(n)
        #expect(rate > 0.025 && rate < 0.055, "rate \(rate)")
        #expect(VariantTuning.rareRate >= 0.03 && VariantTuning.rareRate <= 0.05)
    }

    @Test func exclusivesNeverAppearInThePark() {
        let pool = ParkPool.generate()
        for ex in JellyVariantBook.exclusives {
            #expect(ex.isExclusive)
            for v in pool { #expect(simd_distance(v.colour.flesh.0, ex.fleshV) > 0.05, "\(v.colour) ~ \(ex.title)") }
        }
        for c in ParkColour.allCases { #expect(JellyVariantBook.parkEligible(c)) }
        #expect(pool == ParkPool.generate())          // the pool itself is unchanged and deterministic
    }

    @Test func saveRoundTripAndOldSavesUnchanged() {
        let suite = "JellyVariantTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        #expect(JellyVariants.load(d).isEmpty)
        let v = JellyVariantBook.exclusives[1]
        JellyVariants.adopt(3, v, d)
        defer { JellyVariants.reload() }
        let back = JellyVariants.load(d)
        #expect(back[3] == v)
        #expect(JellyVariants.active(3) == v)
        #expect(JellyRoster.tint(3) == v.swatch)
        #expect(JellyRoster.palette(3)?.name == v.title)
        #expect(JellyRoster.feature(3) == .wings)          // species features follow the character, not the colour
        #expect(JellyRoster.palette(0) == nil)             // Bob (no variant) is the model's own palette
        JellyVariants.adopt(3, nil, d)
        #expect(JellyVariants.load(d)[3] == nil)
    }

    @Test func parkVisitorsAreClassicSpeciesWithRareMutations() {
        var mutants = 0, total = 0
        for k in 0..<400 {
            let pool = ParkPool.generate(seed: ParkTuning.poolSeed &+ UInt64(k) &* 7919)
            #expect(pool == ParkPool.generate(seed: ParkTuning.poolSeed &+ UInt64(k) &* 7919))
            for v in pool {
                total += 1
                if !v.colour.isClassic { mutants += 1 }
                #expect(JellyVariantBook.parkEligible(v.colour))
                #expect(v.signature == v.colour.speciesFeature)
            }
        }
        let rate = Double(mutants) / Double(total)
        #expect(rate > 0.025 && rate < 0.055, "mutation rate \(rate)")
        #expect(ParkTuning.mutationRate == VariantTuning.rareRate)
        // the real pool: names and ids unchanged in shape, every classic species present
        let pool = ParkPool.generate()
        #expect(pool.map(\.id) == Array(0..<ParkTuning.poolSize))
        #expect(Set(pool.filter { $0.colour.isClassic }.map(\.colour)) == Set(ParkColour.classics))
    }

    // MARK: one rare jewel tone per species

    @Test func everySpeciesOnlyGetsItsOwnRare() {
        #expect(JellyVariantBook.exclusives.map(\.title) == ["Sapphire", "Amber", "Emerald", "Amethyst"])
        var seen = [Int: Int]()
        for day in 0..<5000 { for s in 0...3 { if let o = JellyVariantBook.offer(species: s, dayKey: day) { #expect(o == JellyVariantBook.exclusives[s], "species \(s) day \(day)"); seen[s, default: 0] += 1 } } }
        for s in 0...3 { #expect((seen[s] ?? 0) > 100, "species \(s) has rare days") }
    }

    @Test func rareDaysAreTheSameDaysAsBefore() {
        // the old rule, verbatim (same seed, same first draws): only the colour changed
        for day in 0..<20000 {
            for s in 0...3 {
                var r = ParkRandom(VariantTuning.seed &+ UInt64(bitPattern: Int64(day)) &* 0x9E37_79B9 &+ UInt64(s) &* 0x1F3D)
                _ = r.next()
                let oldRare = Double(r.unit()) < VariantTuning.rareRate
                #expect((JellyVariantBook.offer(species: s, dayKey: day) != nil) == oldRare, "day \(day) species \(s)")
            }
        }
    }

    @Test func legacyExclusiveColoursStayExclusive() {
        let legacy: [(String, [Float], [Float])] = [("Sunbeam gold", [1.000, 0.835, 0.330], [0.900, 0.620, 0.090]), ("Midnight", [0.300, 0.340, 0.620], [0.140, 0.160, 0.400]),
            ("Moonstone", [0.880, 0.930, 1.000], [0.620, 0.700, 0.900]), ("Rose quartz", [1.000, 0.740, 0.860], [0.860, 0.440, 0.640]), ("Aurora", [0.560, 0.960, 0.800], [0.250, 0.700, 0.760])]
        #expect(JellyVariantBook.legacyExclusiveTitles == legacy.map(\.0))
        let suite = "JellyVariantTests.legacy.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite); JellyVariants.reload() }
        for (i, l) in legacy.enumerated() {
            let v = JellyVariant(title: l.0, flesh: SIMD3(l.1[0], l.1[1], l.1[2]), deep: SIMD3(l.2[0], l.2[1], l.2[2]), rare: true)
            #expect(v.isExclusive)
            JellyVariants.adopt(i % 4, v, d)          // saved by value: reads back with its own colour, still rare
            let back = JellyVariants.load(d)[i % 4]
            #expect(back == v && back?.isExclusive == true && back?.rare == true)
            #expect(JellyRoster.tint(i % 4) == v.swatch)
        }
        for c in ParkColour.allCases { #expect(JellyVariantBook.parkEligible(c)) }
        #expect(!ParkColour.allCases.map(\.rawValue).contains { r in JellyVariantBook.exclusives.contains { $0.title.lowercased() == r } })
    }
}
