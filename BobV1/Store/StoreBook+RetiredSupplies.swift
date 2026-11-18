//
//  StoreBook+RetiredSupplies.swift
//  2026-11-17 (the owner: "when does lint guard get used I'm confused on that use"): the Lint-guard spray is no longer sold or used. Each spray a save owns became a Mint soap
//  bar, one for one (Mint soap makes him stay clean longer, the spray's job). Like the retired foods and toys this pass needs no flag: it MOVES the count
//  (replacement += old, old removed), so loading again finds nothing to move. The Tidy perk itself stays (the Spa's Royal Pamper grants it).
//

import Foundation

nonisolated enum RetiredSupplies {
    /// Retired supply id -> the soap that replaces it.
    static let map: [String: String] = ["lintguard": "mintsoap"]
}

extension StoreBook {
    /// The save with every owned retired supply turned into its replacement (same count, added to any the player already has), and whether anything moved.
    static func convertRetiredSupplies(_ s: Saved) -> (saved: Saved, changed: Bool) {
        var out = s
        var changed = false
        for (old, new) in RetiredSupplies.map {
            guard let n = out.counts[old] else { continue }
            if n > 0 { out.counts[new] = (out.counts[new] ?? 0) + n }
            out.counts[old] = nil
            changed = true
        }
        return (out, changed)
    }
}
