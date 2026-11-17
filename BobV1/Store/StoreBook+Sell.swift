//
//  StoreBook+Sell.swift
//  2026-11-17 (the owner: "a way to sell items back for when they want to clean up their inventory"): the Bag's Sell button.
//  The price is half the Shop price (rounded down, at least 1), so selling never pays more than buying. Food, drinks and care goods sell one at a time;
//  a toy / decor piece sells only when it is NOT in a room; a wearable sells only a FREE copy (not on a Jelmiko). Tricks, upgrades, rooms, play toys
//  and the earned medal are never sold.
//

import Foundation

enum SellState: Equatable {
    case sellable(Int)          // JellyCoins you get
    case worn                   // every copy is on a Jelmiko
    case inRoom                 // every piece stands in a room
    case no                     // never sold (or none owned)
}

extension StoreBook {
    /// Half the catalogue price, rounded down, at least 1 (0 for a free item: nothing to pay back).
    static func sellPrice(_ item: StoreItem) -> Int { item.price <= 0 ? 0 : max(item.price / 2, 1) }

    func sellState(_ item: StoreItem) -> SellState {
        guard !item.awarded, Self.sellPrice(item) > 0 else { return .no }
        let pay = Self.sellPrice(item)
        switch item.kind {
        case .food, .treat, .drink, .supply:
            return count(item.id) > 0 ? .sellable(pay) : .no
        case .decor:
            guard count(item.id) > 0 else { return .no }
            return unplaced(item.id) > 0 ? .sellable(pay) : .inRoom
        case .shoes, .wear:
            guard let w = item.wear, copies(w) > 0 else { return .no }
            return freeCopies(w) > 0 ? .sellable(pay) : .worn
        default:
            return .no
        }
    }

    /// Sells one of `id` for its price; the JellyCoins paid, or nil when it cannot be sold now (nothing changes).
    @discardableResult
    func sell(_ id: String) -> Int? {
        guard let item = StoreCatalog.item(id), case .sellable(let pay) = sellState(item) else { return nil }
        switch item.kind {
        case .shoes, .wear:
            guard let w = item.wear, let i = saved.wearables.lastIndex(of: w.rawValue) else { return nil }
            saved.wearables.remove(at: i)
        default:
            saved.counts[id, default: 1] -= 1
            if (saved.counts[id] ?? 0) <= 0 { saved.counts[id] = nil }
        }
        wallet.add(pay, silent: true)
        AudioHub.shared.play(.coin)
        save()
        return pay
    }
}
