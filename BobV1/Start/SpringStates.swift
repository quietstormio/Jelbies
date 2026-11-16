//
//  SpringStates.swift
//  What the Jelly Spring and its Town square say and allow, as pure functions of how many creatures are at home and at Jelmiko Camp, the wallet and the price.
//  (AdoptionCenter and TownUI only draw what these return.)
//
//    home has room (< 3)            today's flow: "n/3 at home", "This one! <coin> price", "Bring <name> home"
//    home full, Camp has room       "3/3 at home · new one goes to Camp", same pick button at the Camp price, "Send <name> to Camp"; the Town square is open
//    home full AND Camp full        "Home and Camp are full": pick button disabled, nothing can be bought, the Town square is dimmed
//    not enough coins               "Need N more JellyCoins" (disabled), whatever the state
//

import Foundation

nonisolated enum SpringStates {
    enum Pick: Equatable {
        case choose                  // nothing picked yet
        case free                    // the free first gift
        case price(Int)              // affordable: "This one!" + coin + price
        case needMore(Int)           // the coins still missing
        case full                    // home and Camp are both full
    }

    static func homeFull(_ home: Int) -> Bool { home >= JellyRoster.maxCount }
    /// A new one would go to Camp (home is full, Camp has room).
    static func goesToCamp(home: Int, camp: Int) -> Bool { JellyCamp.destination(home: home, camp: camp) == .camp }
    static func bothFull(home: Int, camp: Int) -> Bool { JellyCamp.destination(home: home, camp: camp) == .full }

    /// The status line under the species dots.
    static func roomText(home: Int, camp: Int) -> String {
        let cap = JellyRoster.maxCount, n = min(home, cap)
        switch JellyCamp.destination(home: home, camp: camp) {
        case .home: return "\(n)/\(cap) at home"
        case .camp: return "\(n)/\(cap) at home \u{00B7} new one goes to Camp"
        case .full: return "Home and Camp are full"
        }
    }

    /// The pick page's button state. `price` is `AdoptionPrice.next(home:camp:...)` (nil = nowhere to put it).
    static func pick(first: Bool, hasPick: Bool, home: Int, camp: Int, wallet: Int, price: Int?) -> Pick {
        guard hasPick else { return .choose }
        if first { return .free }
        guard let p = price, !bothFull(home: home, camp: camp) else { return .full }
        return p > wallet ? .needMore(p - wallet) : .price(p)
    }
    static func enabled(_ p: Pick) -> Bool { switch p { case .free, .price: return true; default: return false } }
    /// The words (the affordable one is drawn with a coin and the price instead of text).
    static func pickText(_ p: Pick) -> String {
        switch p {
        case .choose: return "Pick one of the three"
        case .free, .price: return "This one!"
        case .needMore(let n): return "Need \(n) more JellyCoins"
        case .full: return "Home and Camp are full"
        }
    }

    /// The naming page's button.
    static func namingText(name: String, home: Int, camp: Int) -> String {
        goesToCamp(home: home, camp: camp) ? "Send \(name) to Camp" : "Bring \(name) home"
    }
    /// What the Spring's moment says over the creature.
    static func celebrationText(name: String, toCamp: Bool) -> String { toCamp ? "\(name) is off to Jelmiko Camp!" : "\(name) is coming home!" }
    /// The one short line in the room afterwards.
    static func roomNote(name: String) -> String { "\(name) is at Jelmiko Camp" }

    /// The Town square: closed only when home and Camp are both full.
    static func townEnabled(home: Int, camp: Int) -> Bool { !bothFull(home: home, camp: camp) }
    static func townSub(home: Int, camp: Int) -> String {
        let cap = JellyRoster.maxCount
        return bothFull(home: home, camp: camp) ? "Home and Camp are full" : "\(min(home, cap))/\(cap) at home"
    }
}
