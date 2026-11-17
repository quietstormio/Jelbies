//
//  WashQuality.swift
//  How well he was washed decides how long he stays clean, in ONE table.
//
//    plain home bath (Jelly soap, Lavender, Berry) < Mint soap bath < the Jelly Spa (Quick Splash < Bubble Spa < Royal Pamper)
//
//  A finished wash (home bath: BathFlow.enter(.finish); the Spa: GameCare+Groom) stamps `BlobGrime.washMul` with the tier's multiplier. Dirt then builds at
//  1 / washMul and the Glow (sparkle) fades at 1 / washMul, until he is dirty again (dirt reaches `GrimeTuning.cleanBelow`): then washMul is 1 again. The LATEST
//  wash replaces the earlier one. The timed perks (Tidy x0.5, Shiny) are separate and stack the same way at home and at the Spa (the strongest slowing perk wins;
//  the wash multiplier then applies on top), so with equal perks the Spa always lasts longer than any home bath.
//

import Foundation

nonisolated enum WashTier: Int, CaseIterable, Comparable, Sendable {
    case plain, fresh, spaQuick, spa, royal
    static func < (a: WashTier, b: WashTier) -> Bool { a.rawValue < b.rawValue }
    var cleanMul: Float { WashQuality.cleanMul[self] ?? 1 }
    var isSpa: Bool { self >= .spaQuick }
}

nonisolated enum WashQuality {
    /// THE table: how many times longer he stays clean after a wash of this tier (plain = today's behaviour).
    static let cleanMul: [WashTier: Float] = [.plain: 1.0, .fresh: 1.5, .spaQuick: 2.0, .spa: 2.5, .royal: 3.0]
    /// The best bath you can give at home (the Mint soap).
    static var bestHomeMul: Float { cleanMul[.fresh] ?? 1 }
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
