//
//  StoreCatalog+Batch3.swift
//  The third batch of shop decor (2026-10-24): 7 furniture pieces and 6 toys (Room/DecorKind+Batch3.swift has their prices and symbols; the 8 new wearables are rows in
//  Wear/WearGenerated.swift and join the shop through `wearItems`). Prices fit the earn-only Drops economy: a race pays 12 / 7 / 4, a Wave win 22.
//

import Foundation

extension StoreCatalog {
    static let batch3: [StoreItem] = DecorKind.batch3Shop.map { k, price, symbol in
        StoreItem(id: k.storeID, name: k.title, kind: .decor, price: price, perk: nil, description: k.use, symbol: symbol, roomUnits: k.spec.units)
    }
}
