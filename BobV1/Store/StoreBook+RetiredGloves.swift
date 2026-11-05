//
//  StoreBook+RetiredGloves.swift
//  The Pink / Sky mittens and the Boxing mitts are gone from the game (2026-11-05: "they don't look good"). The looks, their art and their shop rows no longer exist, so the
//  retired ids live here as raw strings. A save that owns or wears one has it taken off every Jelbie, removed from the bag and its price (35 / 35 / 45)
//  refunded to the wallet ONCE (guarded by `Saved.glovesRefunded`, so loading again never pays twice).
//

import Foundation

extension StoreBook {
    /// WearLook raw value -> the price it was sold at.
    static let retiredGlovePrices: [String: Int] = ["glovePink": 35, "gloveSky": 35, "boxingMitts": 45]

    /// The save without the retired mittens, and the JellyCoins to refund (0 when nothing was owned or it was already done).
    static func dropRetiredGloves(_ s: Saved) -> (saved: Saved, refund: Int) {
        guard s.glovesRefunded != true else { return (s, 0) }
        var out = s
        var refund = 0
        for (id, price) in retiredGlovePrices {
            if out.wearables.contains(id) { refund += price }
            out.wearables.removeAll { $0 == id }
            out.awarded?.removeAll { $0 == id }
            for k in out.worn.keys { out.worn[k] = out.worn[k]?.filter { $0.value != id } }
        }
        out.glovesRefunded = true
        return (out, refund)
    }
}
