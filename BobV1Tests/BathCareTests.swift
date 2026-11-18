//
//  BathCareTests.swift
//  Soaps (2026-11-17): the wash-quality table (plain < Mint < the Spa), how long each keeps him clean (time until dirty from the same start), each soap's power-up
//  (Shiny, Fresh, Bubbly, Snuggly, Cozy), the Shop rows and the Blender bars, the pick card's choices and the persisted wash. Pure model: no room, no sim.
//

import XCTest
@testable import BobV1

@MainActor
final class BathCareTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    final class Clock { var t = Date(timeIntervalSince1970: 1_800_000_000); func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) } }
    private func suite(_ n: String) -> UserDefaults { let d = UserDefaults(suiteName: "BathCareTests.\(n)")!; d.removePersistentDomain(forName: "BathCareTests.\(n)"); return d }

    /// Seconds of normal roaming (0.198 u/s, the measured average) until the first smudge, after a wash of `tier`, from sparkle 1 and dirt 0.
    private func secondsUntilDirty(_ tier: WashTier) -> Float {
        let g = BlobGrime(persists: false); Self.keep.append(g)
        g.sparkle = 1; g.dirt = 0; g.stampWash(tier)
        var t: Float = 0
        while g.coat != .normal && t < 40_000 { g.step(dt: 1, travelled: 0.198); t += 1 }
        return t
    }

    // MARK: the table

    func testTheTableIsOrderedAndEverySpaTierBeatsTheBestSoap() {
        let muls = WashTier.allCases.map(\.cleanMul)
        XCTAssertEqual(muls.first, 1, "a plain wash is today's behaviour")
        XCTAssertEqual(muls, muls.sorted()); XCTAssertEqual(Set(muls).count, muls.count, "strictly ordered")
        XCTAssertEqual(WashTier.fresh.cleanMul, 1.5)
        for g in GroomTier.allCases { XCTAssertTrue(WashQuality.tier(g).isSpa); XCTAssertGreaterThan(WashQuality.tier(g).cleanMul, WashQuality.bestHomeMul, "\(g) beats the best soap") }
        XCTAssertEqual(Soap.allCases.map(\.tier.cleanMul).max(), WashQuality.bestHomeMul)
    }

    func testTimeUntilDirtyGrowsWithTheWashAndTheSpaIsBest() {
        let secs = WashTier.allCases.map { secondsUntilDirty($0) }
        for i in 1..<secs.count { XCTAssertGreaterThan(secs[i], secs[i - 1], "\(WashTier.allCases[i]): \(secs)") }
        for (i, tier) in WashTier.allCases.enumerated() { XCTAssertEqual(secs[i] / secs[0], tier.cleanMul, accuracy: tier.cleanMul * 0.03, "\(tier)") }
        XCTAssertEqual(secs[0], WashQuality.roamSeconds(tier: .plain), accuracy: 30, "plain: about 21 minutes of roaming, as before")
        XCTAssertGreaterThan(secondsUntilDirty(.spaQuick), secondsUntilDirty(Soap.mint.tier), "Quick Splash beats the Mint soap")
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
        g.stampWash(.fresh); XCTAssertEqual(g.washMul, 1.5)
        g.addDirt(0.06); XCTAssertEqual(g.washMul, 1, "dirty again: the wash is spent")
    }

    func testTimeAwayKeepsHimCleanLongerAfterABetterWash() {
        func dirtAfter(_ tier: WashTier, hours: Double) -> Float { let g = BlobGrime(persists: false); Self.keep.append(g); g.stampWash(tier); g.applyAway(seconds: hours * 3600); return g.dirt }
        XCTAssertGreaterThanOrEqual(dirtAfter(.plain, hours: 2.1), GrimeTuning.cleanBelow)
        XCTAssertLessThan(dirtAfter(.fresh, hours: 2.5), GrimeTuning.cleanBelow)
        XCTAssertLessThan(dirtAfter(.spaQuick, hours: 3.5), GrimeTuning.cleanBelow)
        let d = WashTier.allCases.map { dirtAfter($0, hours: 2.4) }
        for i in 1..<d.count { XCTAssertLessThanOrEqual(d[i], d[i - 1]) }
    }

    func testTheWashSurvivesARelaunch() {
        let d = suite("persist"), c = Clock(), key = GrimeTuning.defaultsKey + ".care"
        let g = BlobGrime(persists: true, defaults: d, key: key, now: { c.t })
        g.sparkle = 1; g.dirt = 0; g.stampWash(.fresh)
        let g2 = BlobGrime(persists: true, defaults: d, key: key, now: { c.t })
        XCTAssertEqual(g2.washMul, 1.5); Self.keep += [g, g2]
        d.set(try! JSONEncoder().encode(["sparkle": Float(0.5), "distance": Float(0), "at": Float(c.t.timeIntervalSince1970)]), forKey: key + ".old")
        XCTAssertEqual(BlobGrime(persists: true, defaults: d, key: key + ".old", now: { c.t }).washMul, 1, "an older save reads as a plain wash")
    }

    // MARK: the soaps

    func testEachSoapHasItsPowerUp() {
        XCTAssertEqual(Soap.allCases.count, 6); XCTAssertNil(Soap.jelly.storeID); XCTAssertNil(Soap.jelly.chip); XCTAssertEqual(Soap.jelly.tier, .plain); XCTAssertEqual(Soap.jelly.bubbleRate, 1)
        XCTAssertEqual(Soap.lavender.chip, .shine); XCTAssertEqual(Soap.lavender.grants, [.shine]); XCTAssertEqual(Soap.lavender.tier, .plain)
        XCTAssertEqual(Soap.mint.chip, .fresh); XCTAssertEqual(Soap.mint.tier, .fresh); XCTAssertEqual(Soap.mint.grants, [])
        XCTAssertEqual(Soap.berry.chip, .bubbly); XCTAssertGreaterThan(Soap.berry.bubbleRate, 2); XCTAssertGreaterThan(Soap.berry.heartEvery, 0); XCTAssertGreaterThan(Soap.berry.love, 0)
        XCTAssertEqual(Soap.honey.chip, .snuggly); XCTAssertEqual(Soap.honey.grants, [.snuggly])
        XCTAssertEqual(Soap.chamomile.chip, .cozy); XCTAssertEqual(Soap.chamomile.grants, [.cozy])
        for s in Soap.allCases where s != .jelly { XCTAssertEqual(Soap.of(storeID: s.storeID!), s) }
        XCTAssertEqual(Set(Soap.allCases.map(\.mesh)).count, 6, "a bar model per soap")
    }

    func testHoneySnugglyHalvesTheLoveDrainForSixHoursAndNothingElse() {
        let c = Clock(), p = JellyPerks(persists: false, now: { c.t }); Self.keep.append(p)
        XCTAssertEqual(p.needDrain, [1, 1, 1])
        p.grant(.snuggly)
        XCTAssertEqual(p.needDrain, [1, 1, PerkTuning.snugglyAttention], "love only")
        XCTAssertEqual(PerkTuning.snugglyAttention, 0.5); XCTAssertEqual(PerkKind.snuggly.duration, 6 * 3600)
        XCTAssertFalse(PerkKind.snuggly.bathOnly)
        p.grant(.cozy); XCTAssertEqual(p.needDrain[2], 0.5, "the strongest wins, they do not multiply"); XCTAssertEqual(p.needDrain[0], PerkTuning.cozyDrain[0])
        p.clear(.cozy)
        c.advance(6 * 3600 + 1); p.prune(); XCTAssertFalse(p.isActive(.snuggly), "it ends after six hours")
        // the real drain
        func level(_ perk: PerkKind?) -> Float {
            let n = BlobNeeds(persists: false); Self.keep.append(n); n.set(.attention, 1)
            let pp = JellyPerks(persists: false, now: { c.t }); if let perk { pp.grant(perk) }; Self.keep.append(pp)
            for _ in 0..<1800 { n.step(dt: 1, perkDrain: pp.needDrain) }
            return n.level(.attention)
        }
        let plain = level(nil), snug = level(.snuggly)
        XCTAssertLessThan(plain, 1); XCTAssertGreaterThan(1 - snug, 0); XCTAssertEqual(1 - snug, (1 - plain) * 0.5, accuracy: (1 - plain) * 0.06, "love fell half as fast")
    }

    func testHoneyAndChamomileWorkWhileAwayToo() {
        let d = suite("away"), c = Clock(), key = NeedsTuning.defaultsKey + ".soapaway", pk = PerkTuning.key(forNeeds: key)!
        func run(_ perk: PerkKind?) -> Float {
            d.removeObject(forKey: key); d.removeObject(forKey: pk)
            let n = BlobNeeds(defaults: d, key: key, now: { c.t }, persists: true); Self.keep.append(n)
            n.set(.attention, 1)
            if let perk { let p = JellyPerks(persists: true, defaults: d, key: pk, now: { c.t }); p.grant(perk); Self.keep.append(p) }
            let t0 = c.t; n.leaveActive(at: t0); n.returnActive(at: t0.addingTimeInterval(3 * 3600))
            return n.level(.attention)
        }
        let plain = run(nil), honey = run(.snuggly), cozy = run(.cozy)
        XCTAssertLessThan(plain, 1); XCTAssertGreaterThan(honey, plain + 0.02, "love fell less while away"); XCTAssertGreaterThan(cozy, plain + 0.02)
    }

    func testTheShopRowsAndTheBars() {
        let ids = ["lavender", "mintsoap", "berrysoap", "honeysoap", "chamomilesoap"]
        let price = ["lavender": 20, "mintsoap": 25, "berrysoap": 18, "honeysoap": 22, "chamomilesoap": 22]
        for id in ids {
            let item = StoreCatalog.item(id)
            XCTAssertEqual(item?.kind, .supply, id); XCTAssertEqual(item?.price, price[id], id); XCTAssertNotNil(item?.perk, "\(id) has a power-up chip")
            XCTAssertNotNil(CareMeshes.mesh(id), "\(id): its Blender bar is in the bundle"); XCTAssertGreaterThan(CareMeshes.mesh(id)?.triangles ?? 0, 1000, "\(id) is a real model")
            XCTAssertNotNil(StoreThumb.mesh(for: item!), "\(id): the Shop draws the 3D bar")
            XCTAssertEqual(item?.perk, Soap.of(storeID: id)?.chip)
        }
        XCTAssertNotNil(CareMeshes.mesh(soap: .jelly)); XCTAssertEqual(CareMeshes.loadedCount, 6)
        XCTAssertNil(StoreCatalog.item("lintguard"), "the Lint-guard spray is retired: not sold, not in the Care tab")
        XCTAssertEqual(StoreCatalog.items(.supply).map(\.id).sorted(), ids.sorted(), "the Care tab is just the five soaps")
        XCTAssertEqual(Set(StoreCatalog.items.map(\.id)).count, StoreCatalog.items.count)
        XCTAssertTrue(PerkKind.allCases.allSatisfy { !$0.title.isEmpty && !$0.blurb.isEmpty && !$0.symbol.isEmpty && $0.duration > 0 })
        XCTAssertEqual(PerkKind.allCases.filter(\.bathOnly), [.fresh, .bubbly])
    }

    func testAnOwnedLintGuardSprayBecomesAMintSoapBarOneForOneAndTheNextLoadFindsNothing() {
        var saved = StoreBook.Saved()
        saved.counts["lintguard"] = 3; saved.counts["mintsoap"] = 1; saved.counts["berrysoap"] = 2
        let (out, changed) = StoreBook.convertRetiredSupplies(saved)
        XCTAssertTrue(changed); XCTAssertEqual(out.counts["mintsoap"], 4, "3 sprays + the 1 Mint soap already owned"); XCTAssertNil(out.counts["lintguard"]); XCTAssertEqual(out.counts["berrysoap"], 2)
        let again = StoreBook.convertRetiredSupplies(out)
        XCTAssertFalse(again.changed, "no flag: loading again moves nothing"); XCTAssertEqual(again.saved.counts["mintsoap"], 4)
        XCTAssertFalse(StoreBook.convertRetiredSupplies(StoreBook.Saved()).changed)
        // a zero count just disappears
        var z = StoreBook.Saved(); z.counts["lintguard"] = 0
        XCTAssertNil(StoreBook.convertRetiredSupplies(z).saved.counts["lintguard"]); XCTAssertNil(StoreBook.convertRetiredSupplies(z).saved.counts["mintsoap"])
        XCTAssertGreaterThan(PerkKind.tidy.duration, 0, "the Tidy perk stays (the Royal Pamper grants it)")
        XCTAssertTrue(GroomTier.royal.perks.contains { $0.0 == .tidy })
    }

    func testThePropDrawsTheSoapBarInHandOnlyForABoughtSoap() {
        let o = BathOverlay()
        var l = BathLook(); l.visible = true; l.tool = .soap; l.toolAt = SIMD3(0, 0.6, 1.5)
        o.compose(look: l, time: 1); let plain = o.soup.v.count
        for s in Soap.allCases where s != .jelly { l.soap = s.rawValue; o.compose(look: l, time: 1); XCTAssertGreaterThan(o.soup.v.count, 3000, "\(s): the Blender bar in his hand") }
        XCTAssertLessThan(plain, 3000, "the Jelly soap keeps today's bar")
        XCTAssertLessThanOrEqual(BathLook.maxBubbles, BathOverlay.maxBubbles)
    }
}
