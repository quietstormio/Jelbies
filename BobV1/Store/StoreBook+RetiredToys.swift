//
//  StoreBook+RetiredToys.swift
//  2026-11-15 (the user's ask: "Remove rc car, scooter, frisbee, and bubble machine"): those four toys are retired (DecorKind+Retired.swift), so the Shop no
//  longer sells them. A save that owns one has it taken out of the bag and out of every room (current and stashed) and its price refunded to the wallet.
//  StoreBook+RetiredDecor.swift's pass runs ONCE per save (`Saved.retiredDecorRefunded`), so it never sees a kind that was retired after it ran. This pass has
//  no flag: the refund is paid from the counts it removes, so loading again finds nothing and pays nothing.
//  2026-11-16 (the user's ask: "The tunnel too small remove this toy"): the play tunnel joins them, cleared and refunded the same way.
//

import Foundation

extension StoreBook {
    /// The toys retired on 2026-11-15, and the play tunnel on 2026-11-16. The refund is the price each was sold at (`DecorKind.retiredPrices`).
    static let retiredToys: [DecorKind] = [.toycar, .kickscooter, .frisbee, .bubblemachine, .playtunnel]

    /// The save without the retired toys, the JellyCoins to refund, and whether anything was removed (false = the save comes back untouched).
    static func dropRetiredToys(_ s: Saved) -> (saved: Saved, refund: Int, changed: Bool) {
        var out = s
        var refund = 0
        var changed = false
        for k in retiredToys {
            guard let n = out.counts[k.storeID] else { continue }
            refund += max(n, 0) * (DecorKind.retiredPrices[k] ?? 0)
            out.counts[k.storeID] = nil
            changed = true
        }
        let gone = Set(retiredToys)
        if let placed = out.placedAt, placed.contains(where: { gone.contains($0.kind) }) {
            out.placedAt = placed.filter { !gone.contains($0.kind) }
            changed = true
        }
        if let st = out.stash, st.values.contains(where: { list in list.contains { gone.contains($0.kind) } }) {
            var kept: [String: [PlacedDecor]] = [:]
            for (room, list) in st { let l = list.filter { !gone.contains($0.kind) }; if !l.isEmpty { kept[room] = l } }
            out.stash = kept.isEmpty ? nil : kept
            changed = true
        }
        return (out, refund, changed)
    }
}
