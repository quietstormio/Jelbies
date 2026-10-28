//
//  StoreCatalog+Food4.swift
//  Store sweep 4 (2026-10-27): eight new foods and treats and the new Drinks tab (boba milk tea, berry smoothie, pink lemonade, hot cocoa).
//  Prices follow the JellyCoins economy (a race pays 12 / 7 / 4): foods 13-18, treats 11-14, drinks 11-14. Every perk is an existing PerkKind.
//  The Consumable each one feeds is in Dining/StoreFoods+Food4.swift and Dining/StoreDrinks.swift.
//

import Foundation

extension StoreCatalog {
    static let food4Items: [StoreItem] = [
        // food
        StoreItem(id: "cheeseburger", name: "Cheeseburger", kind: .food, price: 16, perk: .fullBelly, description: "Big and hearty. Hunger falls slower for 4 hours.", symbol: "fork.knife", food: "cheeseburger"),
        StoreItem(id: "ramen", name: "Ramen bowl", kind: .food, price: 18, perk: .cozy, description: "Warm and slurpy. Stays happy longer for 4 hours.", symbol: "fork.knife", food: "ramen"),
        StoreItem(id: "macncheese", name: "Mac & cheese", kind: .food, price: 13, perk: .social, description: "A bowl to share. Plays with the others more for an hour.", symbol: "fork.knife", food: "macncheese"),
        StoreItem(id: "dumplings", name: "Dumplings", kind: .food, price: 15, perk: .focus, description: "Lucky little bites. Fewer stumbles in the next race.", symbol: "fork.knife", food: "dumplings"),
        StoreItem(id: "pancakestack", name: "Pancake stack", kind: .food, price: 14, perk: .zoomies, description: "Syrupy! Zoomies now and a quicker next race.", symbol: "fork.knife", food: "pancakestack"),
        // treats
        StoreItem(id: "fruitcup", name: "Fruit cup", kind: .treat, price: 11, perk: .shine, description: "Fresh and glowy. The shine after a Clean lasts longer (12 hours).", symbol: "birthday.cake.fill", food: "fruitcup"),
        StoreItem(id: "cakeslice", name: "Strawberry cake", kind: .treat, price: 14, perk: .cozy, description: "Sweet and soft. Stays happy longer for 4 hours.", symbol: "birthday.cake.fill", food: "cakeslice"),
        StoreItem(id: "cupcake", name: "Frosted cupcake", kind: .treat, price: 12, perk: .bouncy, description: "Sprinkles! More bouncing for an hour.", symbol: "birthday.cake.fill", food: "cupcake"),
        // drinks (sipped through a straw: thirst, like water, plus a perk)
        StoreItem(id: "boba", name: "Boba milk tea", kind: .drink, price: 14, perk: .social, description: "Chewy pearls and a big sip. Plays with the others more for an hour.", symbol: "cup.and.saucer.fill", food: "boba"),
        StoreItem(id: "smoothie", name: "Berry smoothie", kind: .drink, price: 12, perk: .fullBelly, description: "Thick and fruity. Hunger falls slower for 4 hours.", symbol: "cup.and.saucer.fill", food: "smoothie"),
        StoreItem(id: "lemonade", name: "Pink lemonade", kind: .drink, price: 11, perk: .bouncy, description: "Fizzy-fresh and zingy. More bouncing for an hour.", symbol: "cup.and.saucer.fill", food: "lemonade"),
        StoreItem(id: "cocoa", name: "Hot cocoa", kind: .drink, price: 12, perk: .bedtime, description: "Warm and sleepy, with marshmallows. Falls asleep fast and sleeps deep for 8 hours.", symbol: "mug.fill", food: "cocoa"),
    ]
}
