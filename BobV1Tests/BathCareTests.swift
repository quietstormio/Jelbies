//
//  BathCareTests.swift
//  Bath-time care (2026-11-16): the wash-quality table (plain < gentle < deluxe < the Spa), how long each keeps him clean (time until dirty from the same start),
//  every Care item's perk, the Shop catalog entries and their Blender models, and the persisted wash. Pure model: no room, no sim.
//

import XCTest
@testable import BobV1

@MainActor
final class BathCareTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    final class Clock { var t = Date(timeIntervalSince1970: 1_800_000_000); func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) } }
    private func suite(_ n: String) -> UserDefaults { let d = UserDefaults(suiteName: "BathCareTests.\(n)")!; d.removePersistentDomain(forName: "BathCareTests.\(n)"); return d }

    /// Seconds of normal roaming (0.198 u/s, the measured average) until the first smudge, after a wash of `tier`, from sparkle 1 and dirt 0.
    private func secondsUntilDirty(_ tier: WashTier, perks: JellyPerks? = nil) -> Float {
        let g = BlobGrime(persists: false)
        Self.keep.append(g)
        g.perks = perks
        g.sparkle = 1; g.dirt = 0; g.stampWash(tier)
        var t: Float = 0
        while g.coat != .normal && t < 40_000 { g.step(dt: 1, travelled: 0.198); t += 1 }
        return t
    }

    // MARK: the table

    func testTheTableIsOrderedAndEverySpaTierBeatsTheBestHomeBath() {
        let muls = WashTier.allCases.map(\.cleanMul)
        XCTAssertEqual(muls.first, 1, "a plain home bath is today's behaviour")
        XCTAssertEqual(muls, muls.sorted(), "plain <= gentle <= deluxe <= quick <= spa <= royal")
        XCTAssertEqual(Set(muls).count, muls.count, "strictly ordered, no ties")
        XCTAssertEqual(WashTier.gentle.cleanMul, 1.25); XCTAssertEqual(WashTier.deluxe.cleanMul, 1.5)
        for g in GroomTier.allCases { XCTAssertTrue(WashQuality.tier(g).isSpa); XCTAssertGreaterThan(WashQuality.tier(g).cleanMul, WashQuality.bestHomeMul, "\(g) beats the best home bath (deluxe + brush)") }
        XCTAssertGreaterThan(WashQuality.weakestSpaMul, WashTier.deluxe.cleanMul)
        XCTAssertEqual(WashQuality.tier(.quick), .spaQuick); XCTAssertEqual(WashQuality.tier(.spa), .spa); XCTAssertEqual(WashQuality.tier(.royal), .royal)
    }

    func testTimeUntilDirtyGrowsWithTheWashAndTheSpaIsBest() {
        let secs = WashTier.allCases.map { secondsUntilDirty($0) }
        for i in 1..<secs.count { XCTAssertGreaterThan(secs[i], secs[i - 1], "\(WashTier.allCases[i]) lasts longer than \(WashTier.allCases[i - 1]): \(secs)") }
        for (i, tier) in WashTier.allCases.enumerated() {
            XCTAssertEqual(secs[i] / secs[0], tier.cleanMul, accuracy: tier.cleanMul * 0.03, "\(tier): the ratio is the table's number")
        }
        XCTAssertEqual(secs[0], WashQuality.roamSeconds(tier: .plain), accuracy: 30, "the plain bath: about 21 minutes of roaming, as before")
        // the same with the best home stack (deluxe + soft brush) against the weakest Spa visit
        let c = Clock(), brushed = JellyPerks(persists: false, now: { c.t }); brushed.grant(.brushed)
        Self.keep.append(brushed)
        XCTAssertGreaterThan(secondsUntilDirty(.spaQuick), secondsUntilDirty(.deluxe, perks: brushed), "Quick Splash beats deluxe + brush")
        // and with the SAME perks on both sides the Spa still wins
        let tidy = JellyPerks(persists: false, now: { c.t }); tidy.grant(.tidy)
        Self.keep.append(tidy)
        XCTAssertGreaterThan(secondsUntilDirty(.spaQuick, perks: tidy), secondsUntilDirty(.deluxe, perks: tidy))
    }

    func testTheGlowFadesSlowerWithABetterWash() {
        func glowAfter(_ tier: WashTier) -> Float { let g = BlobGrime(persists: false); Self.keep.append(g); g.sparkle = 1; g.stampWash(tier); for _ in 0..<300 { g.step(dt: 1, travelled: 0) }; return g.sparkle }
        let v = WashTier.allCases.map(glowAfter)
        for i in 1..<v.count { XCTAssertGreaterThan(v[i], v[i - 1]) }
        XCTAssertEqual(v[0], 0.5, accuracy: 0.01, "plain: half the glow gone in 5 minutes, as before")
    }

    func testTheLatestWashReplacesAndTheBonusIsSpentWhenDirty() {
        let g = BlobGrime(persists: false); Self.keep.append(g)
        g.stampWash(.royal); XCTAssertEqual(g.washMul, 3)
        g.stampWash(.plain); XCTAssertEqual(g.washMul, 1, "a plain bath after a Spa visit is a plain bath")
        g.stampWash(.deluxe); XCTAssertEqual(g.washMul, 1.5)
        g.addDirt(0.06)
        XCTAssertEqual(g.washMul, 1, "dirty again: the wash is spent")
        g.stampWash(.gentle); XCTAssertEqual(g.washMul, 1.25)
    }

    func testTimeAwayKeepsHimCleanLongerAfterABetterWash() {
        func dirtAfter(_ tier: WashTier, hours: Double) -> Float { let g = BlobGrime(persists: false); Self.keep.append(g); g.stampWash(tier); g.applyAway(seconds: hours * 3600); return g.dirt }
        // plain: +0.05 per 2 h -> dirty at 2 h; deluxe is still clean at 2.5 h; the Spa at 3.5 h
        XCTAssertGreaterThanOrEqual(dirtAfter(.plain, hours: 2.1), GrimeTuning.cleanBelow)
        XCTAssertLessThan(dirtAfter(.deluxe, hours: 2.5), GrimeTuning.cleanBelow)
        XCTAssertLessThan(dirtAfter(.spaQuick, hours: 3.5), GrimeTuning.cleanBelow)
        XCTAssertGreaterThanOrEqual(dirtAfter(.gentle, hours: 3), GrimeTuning.cleanBelow)
        let d = WashTier.allCases.map { dirtAfter($0, hours: 2.4) }
        for i in 1..<d.count { XCTAssertLessThanOrEqual(d[i], d[i - 1]) }
    }

    func testTheWashSurvivesARelaunchAndTheSparkleToo() {
        let d = suite("persist"), c = Clock(), key = GrimeTuning.defaultsKey + ".care"
        let g = BlobGrime(persists: true, defaults: d, key: key, now: { c.t })
        g.sparkle = 1; g.dirt = 0; g.stampWash(.deluxe)
        let g2 = BlobGrime(persists: true, defaults: d, key: key, now: { c.t })
        XCTAssertEqual(g2.washMul, 1.5); Self.keep += [g, g2]
        // a save with no wash field (every old save) reads as a plain wash
        d.set(try! JSONEncoder().encode(["sparkle": Float(0.5), "distance": Float(0), "at": Float(c.t.timeIntervalSince1970)]), forKey: key + ".old")
        XCTAssertEqual(BlobGrime(persists: true, defaults: d, key: key + ".old", now: { c.t }).washMul, 1)
    }

    // MARK: the perks

    func testSoftBrushSlowsDirtTwentyPercentAndTidyStaysStrongerWithoutStacking() {
        let c = Clock(), p = JellyPerks(persists: false, now: { c.t }); Self.keep.append(p)
        XCTAssertEqual(p.dirtMul, 1)
        p.grant(.brushed); XCTAssertEqual(p.cache.dirt, 0.8)
        p.grant(.tidy); XCTAssertEqual(p.cache.dirt, 0.5, "the strongest wins; they do not multiply")
        p.clear(.tidy); XCTAssertEqual(p.cache.dirt, 0.8)
        XCTAssertEqual(PerkKind.brushed.duration, 6 * 3600)
        c.advance(6 * 3600 + 1); p.prune(); XCTAssertFalse(p.isActive(.brushed), "it ends after the while")
        // really builds dirt 20% slower
        let plain = BlobGrime(persists: false), soft = BlobGrime(persists: false); Self.keep += [plain, soft]
        let pb = JellyPerks(persists: false, now: { c.t }); pb.grant(.brushed); Self.keep.append(pb); soft.perks = pb
        for _ in 0..<600 { plain.step(dt: 1, travelled: 0.198); soft.step(dt: 1, travelled: 0.198) }
        XCTAssertEqual(soft.dirt, plain.dirt * 0.8, accuracy: plain.dirt * 0.02)
    }

    func testSoftBrushAlsoSlowsTheLintWhileAway() {
        let d = suite("away"), c = Clock()
        let key = GrimeTuning.defaultsKey + ".brushaway", pk = PerkTuning.key(forGrime: key)!
        func run(brush: Bool) -> Float {
            d.removeObject(forKey: key); d.removeObject(forKey: pk)
            let g = BlobGrime(persists: true, defaults: d, key: key, now: { c.t }); Self.keep.append(g)
            if brush { let p = JellyPerks(persists: true, defaults: d, key: pk, now: { c.t }); p.grant(.brushed); Self.keep.append(p) }
            let t0 = c.t
            g.leaveActive(at: t0); g.returnActive(at: t0.addingTimeInterval(3 * 3600))
            return g.dirt
        }
        let a = run(brush: false), b = run(brush: true)
        XCTAssertEqual(b, a * 0.8, accuracy: 0.004, "20% less lint after 3 hours away")
    }

    func testEveryCareItemIsInTheShopWithAPerkChipAndAModel() {
        XCTAssertEqual(CareItems.all.count, 8)
        for id in CareItems.all {
            let item = StoreCatalog.item(id)
            XCTAssertNotNil(item, id); XCTAssertEqual(item?.kind, .supply, id)
            XCTAssertNotNil(item?.perk, "\(id) has a perk chip like Shiny / Tidy")
            XCTAssertFalse(item?.description.isEmpty ?? true)
            XCTAssertNotNil(CareMeshes.mesh(id), "\(id): the Blender model is in the bundle (food_\(CareItems.mesh(id) ?? "?").bin)")
            XCTAssertNotNil(CareMeshes.roomMesh(id)); XCTAssertGreaterThan(CareMeshes.mesh(id)?.triangles ?? 0, 300, "\(id) is a real model, not a primitive")
            XCTAssertNotNil(StoreThumb.mesh(for: item!), "\(id): the Shop draws the 3D model")
        }
        XCTAssertEqual(CareMeshes.loadedCount, 8)
        let prices = Dictionary(uniqueKeysWithValues: CareItems.all.map { ($0, StoreCatalog.item($0)!.price) })
        XCTAssertEqual(prices[CareItems.bubblebath], 16); XCTAssertEqual(prices[CareItems.gentle], 18); XCTAssertEqual(prices[CareItems.deluxe], 32)
        XCTAssertEqual(prices[CareItems.brush], 22); XCTAssertEqual(prices[CareItems.sponge], 14); XCTAssertEqual(prices[CareItems.duck], 12)
        XCTAssertEqual(prices[CareItems.lavender], 20); XCTAssertEqual(prices[CareItems.lintguard], 18)
        XCTAssertGreaterThan(prices[CareItems.deluxe]!, prices[CareItems.gentle]!, "the better shampoo costs more")
        XCTAssertEqual(Set(StoreCatalog.items.map(\.id)).count, StoreCatalog.items.count, "no duplicate store ids")
        XCTAssertTrue(PerkKind.allCases.allSatisfy { !$0.title.isEmpty && !$0.blurb.isEmpty && !$0.symbol.isEmpty && $0.duration > 0 })
        XCTAssertTrue(PerkKind.allCases.filter(\.bathOnly).allSatisfy { StoreCatalog.items.contains(item: $0) })
        XCTAssertFalse(PerkKind.brushed.bathOnly); XCTAssertFalse(PerkKind.shine.bathOnly)
    }

    // MARK: what each item does (the kit)

    func testEachItemsEffect() {
        func kit(_ ids: String...) -> BathKit { BathKit(ids: ids) }
        XCTAssertEqual(BathKit.none.tier, .plain); XCTAssertEqual(BathKit.none.scrubMul, 1); XCTAssertEqual(BathKit.none.bubbleRate, 1); XCTAssertEqual(BathKit.none.heartEvery, 0)
        // bubble bath: extra bubbles and love
        XCTAssertGreaterThan(kit(CareItems.bubblebath).bubbleRate, 2); XCTAssertGreaterThan(kit(CareItems.bubblebath).heartEvery, 0); XCTAssertGreaterThan(kit(CareItems.bubblebath).love, 0)
        XCTAssertEqual(kit(CareItems.bubblebath).tier, .plain, "it does not change how long he stays clean")
        // gentle / deluxe shampoo: the tiers (25% / 50% longer) and deluxe adds shine
        XCTAssertEqual(kit(CareItems.gentle).tier.cleanMul, 1.25); XCTAssertEqual(kit(CareItems.deluxe).tier.cleanMul, 1.5)
        XCTAssertEqual(kit(CareItems.deluxe).grants, [.shine]); XCTAssertEqual(kit(CareItems.gentle).grants, [])
        XCTAssertEqual(kit(CareItems.gentle, CareItems.deluxe).tier, .deluxe, "the better shampoo wins")
        // soft brush: the brushed perk and the moment
        XCTAssertEqual(kit(CareItems.brush).grants, [.brushed]); XCTAssertTrue(kit(CareItems.brush).brushes)
        // sea sponge: a quicker scrub
        XCTAssertEqual(kit(CareItems.sponge).scrubMul, WashKit.spongeScrub); XCTAssertGreaterThan(WashKit.spongeScrub, 1.3)
        // rubber duck: love and the duck
        XCTAssertTrue(kit(CareItems.duck).hasDuck); XCTAssertGreaterThan(kit(CareItems.duck).heartEvery, 0); XCTAssertGreaterThan(kit(CareItems.duck).love, 0)
        // the two existing ones keep their perks
        XCTAssertEqual(kit(CareItems.lavender).grants, [.shine]); XCTAssertEqual(kit(CareItems.lintguard).grants, [.tidy])
        // the picker's toggle: the shampoos are alternatives, everything else combines, and a second tap unpicks
        var k = BathKit.none.toggled(CareItems.gentle).toggled(CareItems.duck)
        XCTAssertEqual(k.ids, [CareItems.gentle, CareItems.duck])
        k = k.toggled(CareItems.deluxe); XCTAssertEqual(k.ids, [CareItems.duck, CareItems.deluxe], "picking deluxe drops gentle")
        k = k.toggled(CareItems.duck); XCTAssertEqual(k.ids, [CareItems.deluxe])
        XCTAssertEqual(k.adding(CareItems.deluxe), k)
    }

    func testBubblesStayUnderTheRenderersCap() {
        XCTAssertLessThanOrEqual(BathLook.maxBubbles, BathOverlay.maxBubbles)
        XCTAssertEqual(BathLook.maxBubbles, 48)
    }

    func testPropsDrawTheModelsAndNothingWhenNoneArePicked() {
        let o = BathOverlay()
        var look = BathLook(); look.visible = true
        o.compose(look: look, time: 1); XCTAssertTrue(o.isEmpty, "no items, no props")
        for id in CareItems.all {
            var l = look; l.kit = BathKit(ids: [id])
            if id == CareItems.sponge { l.tool = .soap; l.toolAt = SIMD3(0, 0.6, 1.5) }
            if id == CareItems.brush { l.tool = .shine; l.toolAt = SIMD3(0, 0.6, 1.5) }
            o.compose(look: l, time: 1)
            XCTAssertGreaterThan(o.soup.v.count, 300, "\(id) draws its model")
        }
        var hidden = look; hidden.visible = false; hidden.kit = BathKit(ids: [CareItems.duck])
        o.compose(look: hidden, time: 1); XCTAssertTrue(o.isEmpty, "nothing in the room view")
    }
}

private extension Array where Element == StoreItem {
    func contains(item k: PerkKind) -> Bool { contains { $0.perk == k } }
}
