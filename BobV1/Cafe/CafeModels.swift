//
//  CafeModels.swift
//  The café outing's data: the menu (six café-only treats, priced in Drops, each with a store perk), an order (a treat per Jelbie, or one for the table),
//  the tunables and the reasons an outing cannot start. Pure values, unit-tested (CafeTests). Nothing here is persisted: the Drops spent, the perks and the needs are
//  kept by the stores that already own them.
//

import Foundation
import Observation

nonisolated enum CafeTreatID: String, CaseIterable, Codable, Sendable { case swirl, fizzmac, pancakes, sundae, jellycup, latte, cocoa, juice }

/// Food fills hunger (and is only for the hungry); a drink never does (a tiny bit at most) and anybody can order one.
nonisolated enum CafeCategory: String, Sendable { case food, drink }

nonisolated struct CafeTreat: Sendable, Identifiable {
    let id: CafeTreatID
    var category: CafeCategory { id == .latte || id == .cocoa || id == .juice ? .drink : .food }
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
        .init(id: .sundae, name: "Mini sundae", price: 18, perk: .bouncy, blurb: "Cold and silly. Extra bouncy for a while.", condition: [.sweet: 0.12, .cool: 0.06]),
        .init(id: .jellycup, name: "Jelly Cup", price: 8, perk: .cozy, blurb: "A tiny cup of whipped cream, just for Jelbies.", condition: [.sweet: 0.08, .cute: 0.08]),
        .init(id: .latte, name: "Baby latte", price: 12, perk: .zoomies, blurb: "Warm and foamy. Zoomies right here, and again at home!", condition: [.sporty: 0.06, .cool: 0.08]),
        .init(id: .cocoa, name: "Warm cocoa", price: 11, perk: .cozy, blurb: "Marshmallows on top. Stays happy longer.", condition: [.sweet: 0.08, .cute: 0.06]),
        .init(id: .juice, name: "Berry juice", price: 10, perk: .bouncy, blurb: "Pink and fizzy. Extra bouncy for a while.", condition: [.sparkle: 0.10, .cute: 0.04])]
    static var foods: [CafeTreat] { treats.filter { $0.category == .food } }
    static var drinks: [CafeTreat] { treats.filter { $0.category == .drink } }
    static var cheapest: Int { treats.map(\.price).min() ?? 0 }
    static func treat(_ id: CafeTreatID) -> CafeTreat { treats.first { $0.id == id } ?? treats[0] }

    /// The Daily special: -20 %. Chosen from the day's Jelly Show theme: the item that raises the theme's MAIN stat the most (the same stat the Show's Diet bar reads;
    /// a tie is broken by the day, so it changes with the day). Deterministic: same theme + same day = same special.
    static func special(theme: ShowTheme, dayKey: Int = 0) -> CafeTreatID {
        let key = theme.main.condition
        let top = treats.map { $0.condition[key] ?? 0 }.max() ?? 0
        let best = treats.filter { ($0.condition[key] ?? 0) >= top - 1e-6 }
        return best[((dayKey % best.count) + best.count) % best.count].id
    }
    static let specialOff = 0.20
    /// The price of one treat today (the special is -20 %).
    static func price(_ id: CafeTreatID, special: CafeTreatID?) -> Int {
        let p = treat(id).price
        return id == special ? Int((Double(p) * (1 - specialOff)).rounded()) : p
    }
}

/// Who may order food: only a Jelbie who is not full (the tier the game already uses: Full refuses food at home too). Drinks are for everybody.
nonisolated enum CafeRules {
    static func canEatFood(_ tier: NeedTier) -> Bool { tier != .full }
    static func canOrder(_ t: CafeTreatID, tier: NeedTier) -> Bool { CafeMenu.treat(t).category == .drink || canEatFood(tier) }
    /// A drink fills hunger only a tiny bit per piece.
    static let drinkFillPerPiece: Float = 0.01
}

/// The stamp card: 8 slots, one stamp per visit with an order; with a full card the next order is free and the card starts again.
nonisolated struct CafeStamps: Equatable, Sendable {
    /// 8 slots: seven paid, stamped visits, then the 8th order is free (and the card starts again).
    static let slots = 8, paidVisits = 7
    static let key = "CafeStamps.v1"
    var count = 0
    var isFull: Bool { count >= Self.paidVisits }
    /// An order was placed: a free one (full card) resets the card, any other earns a stamp.
    mutating func recordOrder() { if isFull { count = 0 } else { count += 1 } }
}

@MainActor
@Observable
final class CafeStampBook {
    private(set) var card = CafeStamps()
    /// Bumped when a stamp lands (the menu's stamp animation).
    private(set) var landed = 0
    private let persists: Bool
    init(persists: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil) {
        self.persists = persists
        if persists { card.count = min(max(UserDefaults.standard.integer(forKey: CafeStamps.key), 0), CafeStamps.paidVisits) }
    }
    var isFull: Bool { card.isFull }
    func recordOrder() {
        let wasFull = card.isFull
        card.recordOrder()
        if !wasFull { landed += 1 }
        if persists { UserDefaults.standard.set(card.count, forKey: CafeStamps.key) }
    }
    func set(_ n: Int) { card.count = min(max(n, 0), CafeStamps.paidVisits); if persists { UserDefaults.standard.set(card.count, forKey: CafeStamps.key) } }
}

/// What the table orders: a treat for each Jelbie (by roster id), or one treat for everybody ("Same for everyone", a little cheaper).
nonisolated struct CafeOrder: Equatable, Sendable {
    var picks: [Int: CafeTreatID] = [:]
    var forTable: CafeTreatID?

    init(picks: [Int: CafeTreatID] = [:], forTable: CafeTreatID? = nil) { self.picks = picks; self.forTable = forTable }

    func treat(for id: Int) -> CafeTreatID? { forTable ?? picks[id] }
    func isComplete(jellies: [Int]) -> Bool { !jellies.isEmpty && jellies.allSatisfy { treat(for: $0) != nil } }
    func total(jellies: [Int], special: CafeTreatID? = nil) -> Int {
        if let t = forTable { return Int((Double(CafeMenu.price(t, special: special) * jellies.count) * CafeTuning.tableDiscount).rounded(.down)) }
        return jellies.reduce(0) { $0 + (treat(for: $1).map { CafeMenu.price($0, special: special) } ?? 0) }
    }
    /// What the full price would be (to show the discounts).
    func fullPrice(jellies: [Int]) -> Int { jellies.reduce(0) { $0 + (treat(for: $1).map { CafeMenu.treat($0).price } ?? 0) } }
    /// nil = affordable; else the friendly line.
    static func refusal(total: Int, wallet: Int) -> String? {
        total <= wallet ? nil : "You need \(total - wallet) more JellyCoins. Races pay JellyCoins!"
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
    /// The baby latte's café zoomies: a burst of laps on the café floor this long (seconds, picked per Jelbie), then he sits back.
    static let zoomSeconds: ClosedRange<Float> = 6...10
    static let arriveHopStagger: Float = 0.25
    static let cheerSeconds: Float = 2.8, cheerStagger: Float = 0.3
    static let toastSeconds: Float = 2.5
    /// After the cheer: they stay at the table, sip, chat and think until Go home or this long.
    static let loungeSeconds: Float = 30
    /// The cosy lounge's mood boost (stronger and longer than at home): attention + a cozy perk that lasts this much longer than a café treat's.
    static let loungeAttention: Float = 0.2
    /// Chatter and thought bubbles at the table.
    static let chatEvery: ClosedRange<Float> = 2.5...5, thoughtEvery: ClosedRange<Float> = 4...8, thoughtSeconds: ClosedRange<Float> = 3...5
    /// A given-up serving where nobody ate a piece gives the Drops back.
    static let refundIfNothingEaten = true
    /// The café plays its own smooth-jazz tracks.
    static let music: MusicScene = .cafe
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
        case .noDrops: return "Café treats start at \(CafeMenu.cheapest) JellyCoins. Win a race first!"
        case .busy: return "Already out!"
        }
    }
}

/// One thought bubble over a Jelbie at the table: an icon (no words), shown for a few seconds.
nonisolated struct CafeThought: Equatable, Sendable {
    enum Icon: Equatable, Sendable { case symbol(String), friend(Int) }
    var who: Int
    var icon: Icon
    var total: Float
    var left: Float
    /// 0...1 through its life (for the pop in and out).
    var age: Float { total > 0 ? 1 - left / total : 1 }

    /// The café-themed icons: coffee cup, cocoa, cake slice, heart, music note, sparkle, a friend's face, the stamp card.
    static func pick(who: Int, friends: [Int], using rng: inout some RandomNumberGenerator, seconds: ClosedRange<Float>) -> CafeThought {
        var icons: [Icon] = [.symbol("cup.and.saucer.fill"), .symbol("mug.fill"), .symbol("birthday.cake.fill"), .symbol("heart.fill"), .symbol("music.note"), .symbol("sparkles"), .symbol("seal.fill")]
        for f in friends where f != who { icons.append(.friend(f)) }
        let t = Float.random(in: seconds, using: &rng)
        return CafeThought(who: who, icon: icons.randomElement(using: &rng) ?? .symbol("heart.fill"), total: t, left: t)
    }
}
