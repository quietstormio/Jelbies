//
//  Soaps.swift
//  The soaps (2026-11-17, the owner: "let them pick a certain soap before the bath starts ... different kinds and scents and power ups"). Each has a scent, a bar and
//  foam colour and ONE power-up chip. The Jelly soap is free and always there (today's plain wash); the others are bought in the Shop (store ids below) and one bar is
//  used up by a FINISHED bath (a cancelled bath uses nothing). The wash tier table is WashQuality.swift.
//
//    Jelly soap      free      plain wash (1x)
//    Lavender soap   20        purple   Shiny    the glow lasts longer (the Shiny perk, 12 h)
//    Mint soap       25        green    Fresh    stays clean 1.5x longer (wash tier .fresh)
//    Berry soap      18        pink     Bubbly   extra bubbles, a few hearts and a little love during the bath
//    Honey soap      22        gold     Snuggly  love (attention) falls at x0.5 for 6 h after the bath (a new timed perk)
//    Chamomile soap  22        cream    Cozy     the existing Cozy perk for 4 h: love falls x0.5, hunger and thirst x0.8
//

import Foundation

nonisolated enum Soap: Int, CaseIterable, Sendable {
    case jelly, lavender, mint, berry, honey, chamomile

    /// The Shop item (nil: the free Jelly soap).
    var storeID: String? { switch self { case .jelly: return nil; case .lavender: return "lavender"; case .mint: return "mintsoap"; case .berry: return "berrysoap"; case .honey: return "honeysoap"; case .chamomile: return "chamomilesoap" } }
    static func of(storeID id: String) -> Soap? { allCases.first { $0.storeID == id } }
    /// The bought soaps' store ids.
    static var boughtIDs: [String] { allCases.compactMap(\.storeID) }

    var name: String { switch self { case .jelly: return "Jelly soap"; case .lavender: return "Lavender soap"; case .mint: return "Mint soap"; case .berry: return "Berry soap"; case .honey: return "Honey soap"; case .chamomile: return "Chamomile soap" } }
    var scent: String { switch self { case .jelly: return "Plain"; case .lavender: return "Lavender"; case .mint: return "Mint"; case .berry: return "Berry"; case .honey: return "Honey"; case .chamomile: return "Chamomile" } }
    /// The power-up chip (nil for the plain Jelly soap).
    var chip: PerkKind? { switch self { case .jelly: return nil; case .lavender: return .shine; case .mint: return .fresh; case .berry: return .bubbly; case .honey: return .snuggly; case .chamomile: return .cozy } }
    /// The wash tier it gives.
    var tier: WashTier { self == .mint ? .fresh : .plain }
    /// Timed perks granted by a finished bath with it.
    var grants: [PerkKind] { switch self { case .lavender: return [.shine]; case .honey: return [.snuggly]; case .chamomile: return [.cozy]; default: return [] } }
    /// Berry: sud bubbles come this many times as often (the 48-bubble cap still holds), a heart floats up every `heartEvery` seconds and the bath ends with a little love.
    var bubbleRate: Float { self == .berry ? 2.2 : 1 }
    var heartEvery: Float { self == .berry ? 2.6 : 0 }
    var love: Float { self == .berry ? 0.04 : 0 }
    /// The bar's Blender model (Store/Resources/food_care_<mesh>.bin, tools/make_care1).
    var mesh: String { switch self { case .jelly: return "care_soap_jelly"; case .lavender: return "care_soap_lavender"; case .mint: return "care_soap_mint"; case .berry: return "care_soap_berry"; case .honey: return "care_soap_honey"; case .chamomile: return "care_soap_chamomile" } }
    /// The one-line "what it does" for the picker.
    var blurb: String {
        switch self {
        case .jelly: return "A plain, happy wash."
        case .lavender: return "The glow lasts longer."
        case .mint: return "Stays clean 1.5x longer."
        case .berry: return "Extra bubbles and a little love."
        case .honey: return "Love falls half as fast for 6 hours."
        case .chamomile: return "Love falls half as fast, and hunger and thirst a bit slower, for 4 hours."
        }
    }
}
