//
//  FavouriteFood.swift
//  A Jelmiko's favourite food (the snack picked with them, JellyTraits.snack; the roster card says "loves ..."): its power-up lasts twice as long.
//  The power-up is the food's own (Consumable.perk). A favourite food without one gives none, only the extra heart it always gave.
//  Pure numbers and the Shop's one line. The one caller is `ate` in GameCare+Store.swift (food eaten at home); the Café and the Groomer keep their own times.
//

import Foundation

nonisolated enum FavouriteFood {
    /// A favourite food's power-up lasts this many times a plain serving's (PerkKind.duration).
    static let perkTimeMul: Double = 2

    /// The Shop's line under the Food tab. It states `perkTimeMul` in words: keep it, the Help page (Settings/SupportPage.swift) and docs/SUPPORT.md in step.
    static let shopLine = "Some foods give a power-up. A favourite food makes it last twice as long."

    /// The love (attention need, the heart bar) a Jelmiko gains, once per serving, on his own first bite of his favourite food (capped at 1).
    static let loveGain: Float = 0.15
    /// After the first heart, this many more float up, `heartGap` seconds apart.
    static let extraHearts = 2
    static let heartGap: Float = 0.45

    /// Seconds one serving of a food with `perk` gives.
    static func perkDuration(_ perk: PerkKind, favourite: Bool) -> TimeInterval { perk.duration * (favourite ? perkTimeMul : 1) }

    /// Seconds to grant when a Jelmiko who still has `left` seconds of `perk` eats a serving: the serving's time, and never less than `left`,
    /// so a plain serving after a favourite one (or after a longer time from the Café) does not cut the power-up short.
    static func grantSeconds(_ perk: PerkKind, favourite: Bool, left: TimeInterval) -> TimeInterval { max(perkDuration(perk, favourite: favourite), left) }
}
