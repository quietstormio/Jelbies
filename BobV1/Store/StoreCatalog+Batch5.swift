//
//  StoreCatalog+Batch5.swift
//  The fifth batch of shop decor (2026-11-04): 4 sport toys (Room/DecorKind+Batch5.swift has their prices and symbols).
//

import Foundation

extension StoreCatalog {
    static let batch5: [StoreItem] = DecorKind.batch5Shop.map { k, price, symbol in
        StoreItem(id: k.storeID, name: k.title, kind: .decor, price: price, perk: nil, description: k.use, symbol: symbol, roomUnits: k.spec.units)
    }
}
