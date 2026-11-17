//
//  StoreBook+RetiredBodies.swift
//  2026-11-16 (the owner: "remove the puffer vest and cardigan"): the Puffer vest (65) and the Cable cardigan (60) are retired (`WearLook.retired`). A save that owns
//  copies has them taken off every Jelmiko, removed from the bag and each copy refunded at its price ONCE (guarded by `Saved.bodiesRefunded`, so loading again never
//  pays twice). Runs before `dropRetiredLooks`, which would otherwise unown them without paying.
//

import Foundation

extension StoreBook {
    /// WearLook -> the price it was sold at (the same rows the Shop used).
    static let retiredBodies: [WearLook] = [.vestPuffer, .cardiganCable]

    /// The save without the retired bodies, and the JellyCoins to refund (0 when nothing was owned or it was already done).
    static func dropRetiredBodies(_ s: Saved) -> (saved: Saved, refund: Int) {
        guard s.bodiesRefunded != true else { return (s, 0) }
        var out = s
        var refund = 0
        for l in retiredBodies {
            let ids: Set<String> = [l.rawValue, l.row.storeID]
            refund += out.wearables.filter { ids.contains($0) }.count * l.row.price
            out.wearables.removeAll { ids.contains($0) }
            out.awarded?.removeAll { ids.contains($0) }
            for k in out.worn.keys { out.worn[k] = out.worn[k]?.filter { !ids.contains($0.value) } }
        }
        out.bodiesRefunded = true
        return (out, refund)
    }
}
