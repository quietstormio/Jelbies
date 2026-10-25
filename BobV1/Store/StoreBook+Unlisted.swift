//
//  StoreBook+Unlisted.swift
//  Looks pulled from the shop (`WearLook.unlisted`): a save that owns one has it taken off every Jelbie, removed from the bag and its price
//  refunded to the Drops wallet ONCE (guarded by `Saved.unlistedRefunded`, so loading again never pays twice).
//

import Foundation

extension StoreBook {
    /// The save without the unlisted looks, and the Drops to refund (0 when nothing was owned or it was already done).
    static func dropUnlisted(_ s: Saved) -> (saved: Saved, refund: Int) {
        guard s.unlistedRefunded != true else { return (s, 0) }
        var out = s
        var refund = 0
        for l in WearLook.unlisted {
            if out.wearables.contains(l.rawValue) { refund += l.row.price }
            out.wearables.removeAll { $0 == l.rawValue }
            for k in out.worn.keys { out.worn[k] = out.worn[k]?.filter { $0.value != l.rawValue } }
        }
        out.unlistedRefunded = true
        return (out, refund)
    }
}
