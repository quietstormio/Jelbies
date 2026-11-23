//
//  StoreBook+RetiredTutu.swift
//  2026-11-22 (the owner: "Remove the tutu it looks stupid"): the Ballet tutu (60 JellyCoins) is retired (`WearLook.retired`): not sold, not in the Dress up, not in the bag.
//  A save that owns copies has them taken off every Jelmiko (the remembered show outfit `showHome` too), removed from the bag and each copy refunded at its price.
//  2026-11-23 (the owner: "Remove all necklaces besides the diamond chain"): the same pass now runs over a LIST (`refundedLooks`): the tutu, the Pearl necklace, the Flower lei and
//  the Coach whistle. The tutu's behaviour is exactly as before (`dropRetiredTutu` is the one-look call).
//  Like the retired-toys and retired-foods passes this one needs no flag: the copies it pays for are the copies it removes, so loading again finds nothing to pay.
//  Runs before `dropRetiredLooks`, which would otherwise unown them without paying. The enum cases, rows, meshes and Pip variants stay so old saves decode.
//

import Foundation

extension StoreBook {
    /// The retired looks that are refunded per copy (the owner's rule: the tutu, then the three necklaces).
    static let refundedLooks: [WearLook] = [.tutuPink, .pearls, .lei, .whistleCoach]

    /// The save without `looks` (bag, awards, worn outfits, remembered show outfits), the JellyCoins to refund (each copy at its Shop price), and whether anything changed.
    static func dropRetiredWear(_ s: Saved, _ looks: [WearLook]) -> (saved: Saved, refund: Int, changed: Bool) {
        var out = s
        var refund = 0, changed = false
        for l in looks {
            let ids: Set<String> = [l.rawValue, l.row.storeID]
            let copies = out.wearables.filter { ids.contains($0) }.count
            out.wearables.removeAll { ids.contains($0) }
            out.awarded?.removeAll { ids.contains($0) }
            let had = out.worn.values.contains { $0.values.contains { ids.contains($0) } }
                || (out.showHome ?? [:]).values.contains { $0.values.contains { ids.contains($0) } }
            for k in out.worn.keys { out.worn[k] = out.worn[k]?.filter { !ids.contains($0.value) } }
            if var home = out.showHome {
                for k in home.keys { home[k] = home[k]?.filter { !ids.contains($0.value) } }
                out.showHome = home
            }
            refund += copies * l.row.price
            if copies > 0 || had { changed = true }
        }
        return (out, refund, changed)
    }

    /// The save without the tutu (as before).
    static func dropRetiredTutu(_ s: Saved) -> (saved: Saved, refund: Int, changed: Bool) { dropRetiredWear(s, [.tutuPink]) }

    /// The save without every refunded retired look (the tutu and the three necklaces).
    static func dropRetiredRefunded(_ s: Saved) -> (saved: Saved, refund: Int, changed: Bool) { dropRetiredWear(s, refundedLooks) }
}
