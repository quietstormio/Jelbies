//
//  WashQuality.swift
//  How well he was washed decides how long he stays clean, in ONE table, and what each Care item does in the bath.
//
//    plain home bath < gentle shampoo < deluxe shampoo < the Jelly Spa (Quick Splash < Bubble Spa < Royal Pamper)
//
//  A finished wash (home bath: BathFlow.enter(.finish); the Spa: GameCare+Groom) stamps `BlobGrime.washMul` with the tier's multiplier. Dirt then builds at
//  1 / washMul and the Glow (sparkle) fades at 1 / washMul, until he is dirty again (dirt reaches `GrimeTuning.cleanBelow`): then washMul is 1 again. The LATEST
//  wash replaces the earlier one. The timed perks (Tidy x0.5, Brushed x0.8, Shiny) are separate and stack the same way at home and at the Spa (the strongest
//  slowing perk wins; the wash multiplier then applies on top), so with equal perks the Spa always lasts longer than any home bath.
//

import Foundation

nonisolated enum WashTier: Int, CaseIterable, Comparable, Sendable {
    case plain, gentle, deluxe, spaQuick, spa, royal
    static func < (a: WashTier, b: WashTier) -> Bool { a.rawValue < b.rawValue }
    var cleanMul: Float { WashQuality.cleanMul[self] ?? 1 }
    var isSpa: Bool { self >= .spaQuick }
}

nonisolated enum WashQuality {
    /// THE table: how many times longer he stays clean after a wash of this tier (plain = today's behaviour).
    static let cleanMul: [WashTier: Float] = [.plain: 1.0, .gentle: 1.25, .deluxe: 1.5, .spaQuick: 2.0, .spa: 2.5, .royal: 3.0]
    /// The strongest bath you can give at home: the deluxe shampoo plus the soft brush's slower lint (Tidy is a spray both places can have).
    static var bestHomeMul: Float { (cleanMul[.deluxe] ?? 1) / PerkTuning.brushedDirt }
    /// The weakest Spa visit.
    static var weakestSpaMul: Float { cleanMul[.spaQuick] ?? 1 }

    /// The Spa's tier for a Groomer package.
    static func tier(_ g: GroomTier) -> WashTier { switch g { case .quick: return .spaQuick; case .spa: return .spa; case .royal: return .royal } }

    /// Seconds of normal roaming until the first smudge (dirt 0.05) after a wash of `tier` (the real minutes figure: plain is about 21).
    static func roamSeconds(tier: WashTier, perkMul: Float = 1) -> Float {
        let perSecond = GrimeTuning.dirtPer5Min / 300 * perkMul / tier.cleanMul
        return GrimeTuning.cleanBelow / perSecond
    }
}

/// The Care items and what they do. Ids are the Store catalog ids.
nonisolated enum CareItems {
    static let lavender = "lavender", lintguard = "lintguard", bubblebath = "bubblebath", gentle = "gentleshampoo", deluxe = "deluxeshampoo"
    static let brush = "softbrush", sponge = "seasponge", duck = "rubberduck"
    static let all = [lavender, lintguard, bubblebath, gentle, deluxe, brush, sponge, duck]
    static let shampoos: Set<String> = [gentle, deluxe]
    /// The 3D model (Store/Resources/food_care_<mesh>.bin, tools/make_care1) of a Care item.
    static func mesh(_ id: String) -> String? {
        switch id {
        case lavender: return "care_lavender"; case lintguard: return "care_lintguard"; case bubblebath: return "care_bubblebath"; case gentle: return "care_shampoo"
        case deluxe: return "care_deluxe"; case brush: return "care_brush"; case sponge: return "care_sponge"; case duck: return "care_duck"
        default: return nil
        }
    }
    /// The short name on a bath tile (the Shop keeps the full names).
    static func shortName(_ id: String) -> String {
        switch id {
        case lavender: return "Lavender"; case lintguard: return "Lint-guard"; case bubblebath: return "Bubbles"; case gentle: return "Gentle"
        case deluxe: return "Deluxe"; case brush: return "Brush"; case sponge: return "Sponge"; case duck: return "Duck"
        default: return StoreCatalog.item(id)?.name ?? id
        }
    }
    /// Timed perks granted when the wash finishes (the bath-only ones are not: they act inside the wash).
    static func grants(_ id: String) -> [PerkKind] {
        switch id {
        case lavender: return [.shine]; case lintguard: return [.tidy]; case deluxe: return [.shine]; case brush: return [.brushed]
        default: return []
        }
    }
    /// Love (attention, 0...1) a finished wash adds, on top of the hearts: bubble bath and duck.
    static func love(_ id: String) -> Float { id == bubblebath ? 0.04 : id == duck ? 0.06 : 0 }
}

/// What the player picked for ONE wash: the wash tier, the scrub speed, the bubble rate, the love and the props. Value type: the picker builds it, the flow reads it.
nonisolated struct BathKit: Equatable, Sendable {
    var ids: [String] = []
    static let none = BathKit()
    init(ids: [String] = []) { self.ids = ids }
    func has(_ id: String) -> Bool { ids.contains(id) }
    var isEmpty: Bool { ids.isEmpty }

    /// Plain unless a shampoo is picked; the better shampoo wins when both are.
    var tier: WashTier { has(CareItems.deluxe) ? .deluxe : has(CareItems.gentle) ? .gentle : .plain }
    /// Sea sponge: every scrub / rinse / polish gain x1.5 (a quicker wash).
    var scrubMul: Float { has(CareItems.sponge) ? WashKit.spongeScrub : 1 }
    /// Bubble bath: bubbles come this many times as often (the 48-bubble cap still holds).
    var bubbleRate: Float { has(CareItems.bubblebath) ? WashKit.bubbleRate : 1 }
    /// Hearts floating up during the wash (bubble bath, duck): one every `heartEvery` seconds; 0 = none.
    var heartEvery: Float { has(CareItems.duck) ? WashKit.duckHeartEvery : has(CareItems.bubblebath) ? WashKit.bubbleHeartEvery : 0 }
    var love: Float { ids.reduce(0) { $0 + CareItems.love($1) } }
    var brushes: Bool { has(CareItems.brush) }
    var hasDuck: Bool { has(CareItems.duck) }
    var grants: [PerkKind] { var out: [PerkKind] = []; for i in ids { for p in CareItems.grants(i) where !out.contains(p) { out.append(p) } }; return out }

    /// `id` picked / unpicked. The two shampoos are alternatives (picking one drops the other).
    func toggled(_ id: String) -> BathKit {
        var k = self
        if let i = k.ids.firstIndex(of: id) { k.ids.remove(at: i); return k }
        if CareItems.shampoos.contains(id) { k.ids.removeAll { CareItems.shampoos.contains($0) } }
        k.ids.append(id)
        return k
    }
    func adding(_ id: String) -> BathKit { has(id) ? self : toggled(id) }
}

nonisolated enum WashKit {
    static let spongeScrub: Float = 1.5
    static let bubbleRate: Float = 2.2
    static let bubbleHeartEvery: Float = 2.6, duckHeartEvery: Float = 2.2
    /// The soft brush's moment: a scripted sweep (the same scrub motion as the Help button) before the polish, this long.
    static let brushSeconds: Float = 1.8
}
