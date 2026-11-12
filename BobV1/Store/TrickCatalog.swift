//
//  TrickCatalog.swift
//  Tricks are bought in the Shop. A trick is owned PER JELBIE (one Jelbie learns it) or for EVERYONE (bought once, every Jelbie has it, adopted ones too).
//  The defaults (sit, spin, hop, jacks, and the walks come / run) are known from the start and never sold. To add a trick later: add its case to
//  VoiceTrick (never rename a rawValue: it is the save key), its stars/icon/tags to ShowTrickInfo, and one `Def` row to `forSale` below.
//

import Foundation

nonisolated enum TrickScope: String, Codable, Sendable {
    case perJelbie, everyone
    /// The tag on the Shop card and the show's trick menu.
    var tag: String { self == .everyone ? "For all your Jelbies" : "Only one Jelbie" }
}

nonisolated enum TrickCatalog {
    struct Def: Identifiable, Sendable {
        let trick: VoiceTrick
        let scope: TrickScope
        let price: Int
        var id: String { "trick-\(trick.rawValue)" }
        var name: String { trick.title }
        var icon: String { ShowTrickInfo.symbol(trick) }
        var stars: Int { ShowTrickInfo.difficulty(trick) }
    }

    /// Suggested price by stars (a race pays 75 to 250): 1 star 40, 2 stars 70, 3 stars 110.
    static func price(stars: Int) -> Int { switch stars { case ...1: return 40; case 2: return 70; default: return 110 } }

    /// Known by every Jelbie from the start; never sold. (`come` is innate too; `run` is a walk, not a stage trick.)
    static let defaults: [VoiceTrick] = ShowTrickInfo.defaults + [.run, .come]
    static func isDefault(_ t: VoiceTrick) -> Bool { defaults.contains(t) }

    /// The tricks for sale, in Shop order.
    static let forSale: [Def] = [
        Def(trick: .look, scope: .everyone, price: price(stars: 1)),
        Def(trick: .flip, scope: .perJelbie, price: price(stars: 3)),
        Def(trick: .showOff, scope: .perJelbie, price: price(stars: 3)),
        Def(trick: .strut, scope: .everyone, price: price(stars: 1)),
        Def(trick: .sing, scope: .everyone, price: price(stars: 1)),
    ]
    static func def(_ t: VoiceTrick) -> Def? { forSale.first { $0.trick == t } }

    /// The store id of Music Ears (the Ears feature, a skill bought once for everyone).
    static let earsID = "music-ears"
}
