//
//  StoreCatalog+Batch4.swift
//  The fourth batch of shop decor (2026-10-27): 6 toys (Room/DecorKind+Batch4.swift has their prices and symbols). Prices fit the earn-only JellyCoins economy.
//

import Foundation

extension StoreCatalog {
    static let batch4: [StoreItem] = DecorKind.batch4Shop.map { k, price, symbol in
        StoreItem(id: k.storeID, name: k.title, kind: .decor, price: price, perk: nil, description: k.use, symbol: symbol, roomUnits: k.spec.units)
    }
}
