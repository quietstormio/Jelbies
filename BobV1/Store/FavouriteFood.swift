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

    /// Where the favourite hearts are drawn (world): over the eater's own standing crown (`stand` = his centroid standing upright at his place, not the leaning
    /// body that hangs over the tray), a quarter of his height above it, a little to one side (`side` -1 / 1) so the three do not stack. Above every face on the table.
    static func heartWorld(stand c: SIMD3<Float>, side: Float) -> SIMD3<Float> {
        let H = BlobShape.H
        return SIMD3(c.x + side * 0.22, c.y + 0.5 * H + 0.25 * H, c.z)
    }
    /// The standing centroid of a diner at `stand` (floor point of his place): the body's middle is half his height above the floor.
    static func standCentroid(_ stand: SIMD2<Float>) -> SIMD3<Float> { SIMD3(stand.x, 0.5 * BlobShape.H, stand.y) }
    /// Longest a cheer waits for him to straighten up from the first lean (seconds).
    static let straightenWaitMax: Float = 1.6

    /// Seconds one serving of a food with `perk` gives.
    static func perkDuration(_ perk: PerkKind, favourite: Bool) -> TimeInterval { perk.duration * (favourite ? perkTimeMul : 1) }

    /// Seconds to grant when a Jelmiko who still has `left` seconds of `perk` eats a serving: the serving's time, and never less than `left`,
    /// so a plain serving after a favourite one (or after a longer time from the Café) does not cut the power-up short.
    static func grantSeconds(_ perk: PerkKind, favourite: Bool, left: TimeInterval) -> TimeInterval { max(perkDuration(perk, favourite: favourite), left) }
}
