//
//  StoreBook+Toys.swift
//  Play toys (the bubble wand ...) are bought once with JellyCoins. Kept as a count under "toy-<id>" in the existing `counts`, so no save format changes.
//  (g-playtoss adds the shop's own item for the picker; at merge, make its item's id "bubbleWand" read/write the same key, or call these.)
//

import Foundation

extension StoreBook {
    static func toyKey(_ id: String) -> String { "toy-\(id)" }
    func ownsToy(_ id: String) -> Bool { count(Self.toyKey(id)) > 0 }
    /// Buy a toy: spends its price once; nothing when already owned or the wallet is short.
    @discardableResult
    func buyToy(_ id: String, price: Int) -> BuyResult {
        if ownsToy(id) { return .alreadyOwned }
        guard wallet.spend(price) else { return .notEnough }
        grantToy(id)
        return .bought
    }
    /// Test / capture hook: owned without paying.
    func grantToy(_ id: String) { addToyCount(Self.toyKey(id)) }
}
