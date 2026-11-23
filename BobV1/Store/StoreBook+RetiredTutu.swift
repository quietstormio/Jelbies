//
//  StoreBook+RetiredTutu.swift
//  2026-11-22 (the owner: "Remove the tutu it looks stupid"): the Ballet tutu (60 JellyCoins) is retired (`WearLook.retired`): not sold, not in the Dress up, not in the bag.
//  A save that owns copies has them taken off every Jelmiko (the remembered show outfit `showHome` too), removed from the bag and each copy refunded at its price.
//  Like the retired-toys and retired-foods passes this one needs no flag: the copies it pays for are the copies it removes, so loading again finds nothing to pay.
//  Runs before `dropRetiredLooks`, which would otherwise unown it without paying. The enum case, row, mesh and Pip variant stay so old saves decode.
//

import Foundation

extension StoreBook {
    /// The save without the tutu (bag, awards, worn outfits, remembered show outfits), the JellyCoins to refund, and whether anything changed.
    static func dropRetiredTutu(_ s: Saved) -> (saved: Saved, refund: Int, changed: Bool) {
        let l = WearLook.tutuPink
        let ids: Set<String> = [l.rawValue, l.row.storeID]
        var out = s
        let copies = out.wearables.filter { ids.contains($0) }.count
        out.wearables.removeAll { ids.contains($0) }
        out.awarded?.removeAll { ids.contains($0) }
        for k in out.worn.keys { out.worn[k] = out.worn[k]?.filter { !ids.contains($0.value) } }
        if var home = out.showHome {
            for k in home.keys { home[k] = home[k]?.filter { !ids.contains($0.value) } }
            out.showHome = home
        }
        let had = s.worn.values.contains { $0.values.contains { ids.contains($0) } }
            || (s.showHome ?? [:]).values.contains { $0.values.contains { ids.contains($0) } }
        return (out, copies * l.row.price, copies > 0 || had)
    }
}
