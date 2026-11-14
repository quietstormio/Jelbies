//
//  StoreBook+RetiredHeadbands.swift
//  The Honeybee antennae and the Bunny-ear headbands are gone from the game (2026-11-14, owner: the green Jelmiko's own antennas replace them; "they poke through hats").
//  The looks, their art and their shop rows no longer exist, so the retired ids live here as raw strings. A save that owns or wears one has it taken off every Jelbie,
//  removed from the bag and its price (40 / 45) refunded to the wallet ONCE (guarded by `Saved.headbandsRefunded`, so loading again never pays twice).
//

import Foundation

extension StoreBook {
    /// WearLook raw value -> the price it was sold at (the shop's store id is "wear-" + the art id).
    static let retiredHeadbandPrices: [String: Int] = ["beeAntennae": 40, "bunnyEars": 45]
    private static let retiredHeadbandIDs: [String: String] = ["beeAntennae": "wear-bee_antennae", "bunnyEars": "wear-bunny_ears"]

    /// The save without the retired headbands, and the JellyCoins to refund (0 when nothing was owned or it was already done).
    static func dropRetiredHeadbands(_ s: Saved) -> (saved: Saved, refund: Int) {
        guard s.headbandsRefunded != true else { return (s, 0) }
        var out = s
        var refund = 0
        for (id, price) in retiredHeadbandPrices {
            let ids: Set<String> = [id, retiredHeadbandIDs[id] ?? id]
            if out.wearables.contains(where: { ids.contains($0) }) { refund += price }
            out.wearables.removeAll { ids.contains($0) }
            out.awarded?.removeAll { ids.contains($0) }
            for k in out.worn.keys { out.worn[k] = out.worn[k]?.filter { !ids.contains($0.value) } }
        }
        out.headbandsRefunded = true
        return (out, refund)
    }
}
