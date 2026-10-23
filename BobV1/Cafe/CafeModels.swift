//
//  CafeModels.swift
//  The café outing's data: the menu (four café-only treats, priced in Drops, each with a store perk), an order (a treat per Jelbie, or one for the table),
//  the tunables and the reasons an outing cannot start. Pure values, unit-tested (CafeTests). Nothing here is persisted: the Drops spent, the perks and the needs are
//  kept by the stores that already own them.
//

import Foundation

nonisolated enum CafeTreatID: String, CaseIterable, Codable, Sendable { case swirl, fizzmac, pancakes, sundae }

nonisolated struct CafeTreat: Sendable, Identifiable {
    let id: CafeTreatID
    let name: String
    let price: Int
    let perk: PerkKind
    let blurb: String
    let condition: [ConditionKey: Float]
}

nonisolated enum CafeMenu {
    static let treats: [CafeTreat] = [
        .init(id: .swirl, name: "Cinnamon swirl", price: 14, perk: .cozy, blurb: "Warm and sticky. Stays happy longer.", condition: [.sweet: 0.10, .cute: 0.06]),
        .init(id: .fizzmac, name: "Fizz macaron", price: 15, perk: .zoomies, blurb: "It pops! Zoomies at home, quicker next race.", condition: [.sporty: 0.08, .sparkle: 0.08]),
        .init(id: .pancakes, name: "Pancake stack", price: 16, perk: .fullBelly, blurb: "Fluffy and filling. Hungry much later.", condition: [.sporty: 0.08, .cute: 0.06]),
        .init(id: .sundae, name: "Mini sundae", price: 18, perk: .bouncy, blurb: "Cold and silly. Extra bouncy for a while.", condition: [.sweet: 0.12, .cool: 0.06])]
    static var cheapest: Int { treats.map(\.price).min() ?? 0 }
    static func treat(_ id: CafeTreatID) -> CafeTreat { treats.first { $0.id == id } ?? treats[0] }
}

/// What the table orders: a treat for each Jelbie (by roster id), or one treat for everybody ("Same for everyone", a little cheaper).
nonisolated struct CafeOrder: Equatable, Sendable {
    var picks: [Int: CafeTreatID] = [:]
    var forTable: CafeTreatID?

    init(picks: [Int: CafeTreatID] = [:], forTable: CafeTreatID? = nil) { self.picks = picks; self.forTable = forTable }

    func treat(for id: Int) -> CafeTreatID? { forTable ?? picks[id] }
    func isComplete(jellies: [Int]) -> Bool { !jellies.isEmpty && jellies.allSatisfy { treat(for: $0) != nil } }
    func total(jellies: [Int]) -> Int {
        if let t = forTable { return Int((Double(CafeMenu.treat(t).price * jellies.count) * CafeTuning.tableDiscount).rounded(.down)) }
        return jellies.reduce(0) { $0 + (picks[$1].map { CafeMenu.treat($0).price } ?? 0) }
    }
    /// nil = affordable; else the friendly line.
    static func refusal(total: Int, wallet: Int) -> String? {
        total <= wallet ? nil : "You need \(total - wallet) more Drops. Races pay Drops!"
    }
}

nonisolated enum CafeTuning {
    /// The same feel as the bath's and the room switch's fade.
    static let fadeOut: Float = 0.4, fadeIn: Float = 0.5, holdSteps = 3
    /// Café treats are never refused: everybody eats the whole treat.
    static let piecesPerTreat = 3
    /// Café perks last this much longer than the store's (not for the race-only kinds).
    static let perkDurationMul: Double = 1.5
    /// Once per Jelbie who ate: an outing is love (the "bigger mood boost" than home food).
    static let attentionBonus: Float = 0.35
    static let tableDiscount: Double = 0.85
    static let arriveHopStagger: Float = 0.25
    static let cheerSeconds: Float = 2.8, cheerStagger: Float = 0.3
    static let toastSeconds: Float = 2.5
    /// A given-up serving where nobody ate a piece gives the Drops back.
    static let refundIfNothingEaten = true
    /// The café plays the shop's loop (a dedicated track belongs to the music branch).
    static let music: MusicScene = .shop
}

/// Why the café cannot be entered right now (a friendly line for the toast).
nonisolated enum CafeBlock: String, Sendable {
    case night, sleeping, competition, bath, focus, meal, arranging, moving, listening, noDrops, busy

    var message: String {
        switch self {
        case .night: return "The café is closed at night. Come back in the morning!"
        case .sleeping: return "Shh, someone is napping."
        case .competition: return "Wait until the competition is over."
        case .bath: return "Finish the Clean first."
        case .focus: return "Let go of the close-up first."
        case .meal: return "Finish the meal first."
        case .arranging: return "Finish arranging first."
        case .moving: return "One moment, moving rooms."
        case .listening: return "They are listening to you."
        case .noDrops: return "Café treats start at \(CafeMenu.cheapest) Drops. Win a race first!"
        case .busy: return "Already out!"
        }
    }
}
