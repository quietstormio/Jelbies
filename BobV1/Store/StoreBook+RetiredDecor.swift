//
//  StoreBook+RetiredDecor.swift
//  The retired sit-on furniture (DecorKind.retired): a save that owns any has it taken out of the bag and out of every room (current and stashed) and its
//  price refunded to the wallet ONCE (guarded by `Saved.retiredDecorRefunded`, so loading again never pays twice).
//

import Foundation

extension StoreBook {
    /// The save without retired decor, and the JellyCoins to refund (0 when nothing was owned or it was already done).
    static func dropRetiredDecor(_ s: Saved) -> (saved: Saved, refund: Int) {
        guard s.retiredDecorRefunded != true else { return (s, 0) }
        var out = s
        var refund = 0
        for (k, price) in DecorKind.retiredPrices {
            refund += max(out.counts[k.storeID] ?? 0, 0) * price
            out.counts[k.storeID] = nil
        }
        out.placedAt = out.placedAt?.filter { !$0.kind.isRetired }
        if let st = out.stash {
            var kept: [String: [PlacedDecor]] = [:]
            for (room, list) in st { let l = list.filter { !$0.kind.isRetired }; if !l.isEmpty { kept[room] = l } }
            out.stash = kept.isEmpty ? nil : kept
        }
        out.retiredDecorRefunded = true
        return (out, refund)
    }
}
