//
//  StoreBook+RetiredFoods.swift
//  2026-11-16 (the user's ask: "Remove foods in bowls it looks weird because they eat with hands. Replace them with something else like hand held food"):
//  the Ramen bowl, Mac & cheese and Fruit cup are no longer sold. Each became a hand-held food with the same perk and price (see `retiredFoods`).
//  A save that owns one gets the same count of its replacement, and a favourite food that was one becomes the replacement (JellyTraitsBook.load).
//  Like the retired-toys pass this one needs no flag: it MOVES the count (replacement += old, old removed), so loading again finds nothing to move.
//

import Foundation

/// The retired foods and what replaced them. Nonisolated: the Consumable lookup and the saved favourites (JellyTraitsBook) read it off the main actor.
nonisolated enum RetiredFoods {
    /// Retired food id -> the hand-held food that replaces it.
    static let map: [String: String] = ["ramen": "cinnamonroll", "macncheese": "softpretzel", "fruitcup": "fruitskewer"]
    /// The replacement for `id` when it is a retired food, else `id` itself.
    static func current(_ id: String) -> String { map[id] ?? id }
}

extension StoreBook {

    /// The save with every owned retired food turned into its replacement (same count, added to any the player already has), and whether anything moved.
    static func convertRetiredFoods(_ s: Saved) -> (saved: Saved, changed: Bool) {
        var out = s
        var changed = false
        for (old, new) in RetiredFoods.map {
            guard let n = out.counts[old] else { continue }
            if n > 0 { out.counts[new] = (out.counts[new] ?? 0) + n }
            out.counts[old] = nil
            changed = true
        }
        return (out, changed)
    }
}
