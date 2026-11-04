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
        let distinct = Set((700_000..<700_060).map { JellyVariantBook.offer(species: 0, dayKey: $0)?.title ?? "classic" })
        #expect(distinct.count > 3)
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
}
