//
//  GroomModels.swift
//  The Groomer ("Jelly Spa") as data and a pure state machine (CafeTrip style): three tiers priced per Jelbie, the picker's state, the cut-scene's clock
//  (fade out to the shop front, ~7.6 s at the shop, fade back home, the cheer). It owns no bodies: GameCare+Groom.swift does the swap and the reveal.
//  Nothing here is persisted: the Drops spent, the grime (dirt = lint, sparkle) and the perks are kept by the stores that already own them.
//

import Foundation
import Observation

nonisolated enum GroomTier: String, CaseIterable, Identifiable, Sendable {
    case quick, spa, royal
    var id: String { rawValue }
    var name: String { switch self { case .quick: return "Quick Splash"; case .spa: return "Bubble Spa"; case .royal: return "Royal Pamper" } }
    /// Drops PER JELBIE. Races pay 4...28 and a café treat is 8...18, so a groom is a premium shortcut for the Clean flow.
    var price: Int { switch self { case .quick: return 20; case .spa: return 40; case .royal: return 70 } }
    var symbol: String { switch self { case .quick: return "drop.fill"; case .spa: return "bubbles.and.sparkles.fill"; case .royal: return "crown.fill" } }
    var blurb: String {
        switch self {
        case .quick: return "Squeaky clean, lint gone."
        case .spa: return "Clean, full shine and sparkle that lasts much longer."
        case .royal: return "The longest shine, cozy and tidy too: a Jelly Show glow."
        }
    }
    /// Perks granted (seconds). A home Clean gives none; the spa's shine perk slows the sparkle's fade (and so keeps the Show glow up).
    var perks: [(PerkKind, TimeInterval)] {
        switch self {
        case .quick: return []
        case .spa: return [(.shine, 12 * 3600)]
        case .royal: return [(.shine, 24 * 3600), (.tidy, 12 * 3600), (.cozy, 6 * 3600)]
        }
    }
    var banner: String {
        switch self { case .quick: return "So fresh! \u{2728}"; case .spa: return "So fresh and sparkly! \u{2728}"; case .royal: return "Fit for royalty! \u{2728}" }
    }
    static var cheapest: Int { GroomTier.quick.price }
    func total(count: Int) -> Int { price * max(count, 0) }
    /// nil = affordable; else the friendly line (the café's pattern).
    static func refusal(total: Int, wallet: Int) -> String? { total <= wallet ? nil : "You need \(total - wallet) more Drops. Races pay Drops!" }
}

nonisolated enum GroomTuning {
    static let fadeOut: Float = 0.5, fadeIn: Float = 0.7
    /// Seconds at the shop front (the ambience clip is 8.5 s; the reveal cuts it).
    static let shopSeconds: Float = 7.6
    /// The dryer (steam puffs, "Hair dryer humming") runs from here.
    static let dryerAt: Float = 4.2
    static let cheerSeconds: Float = 4.2, cheerStagger: Float = 0.25, twirlAt: Float = 1.9
    static let toastSeconds: Float = 2.5
    static let lineSpacing: Float = 1.5
    static let clipBell = "groom_bell", clipAmbience = "groom_ambience", clipReveal = "groom_reveal"
}

@MainActor
@Observable
final class GroomTrip {
    enum Phase { case off, picking, fadeOut, shop, reveal, cheer }

    private(set) var phase: Phase = .off
    private(set) var tier: GroomTier = .quick
    /// Roster ids who go.
    var picked: [Int] = []
    /// 0...1: how opaque the shop-front scene is over the room.
    private(set) var shopAlpha: Float = 0
    /// Seconds at the shop (0...shopSeconds).
    private(set) var shopT: Float = 0
    private(set) var cheerT: Float = 0
    var refusal: String?          // the picker's inline line
    var toast: String?
    @ObservationIgnored var toastT: Float = 0
    @ObservationIgnored var skipRequested = false
    @ObservationIgnored var dryerCaptioned = false
    /// The world swap, with the shop opaque (GameCare+Groom.swift). Returns false when the visit cannot start (nothing charged, back home).
    @ObservationIgnored var onSwap: () -> Bool = { true }
    /// The shop fades away: the reveal sound and the line-up's emotes.
    @ObservationIgnored var onReveal: () -> Void = {}
    @ObservationIgnored var onEnd: () -> Void = {}

    nonisolated deinit {}

    var active: Bool { phase != .off }
    var picking: Bool { phase == .picking }
    /// The shop-front scene is up (drawn by GroomChrome).
    var showsShop: Bool { phase == .fadeOut || phase == .shop || phase == .reveal }
    var dryerOn: Bool { phase == .shop && shopT >= GroomTuning.dryerAt }
    var celebrating: Bool { phase == .reveal || phase == .cheer }

    func openPicker(all: [Int]) { guard phase == .off else { return }; picked = all; refusal = nil; phase = .picking }
    func cancelPicker() { if phase == .picking { phase = .off; refusal = nil } }
    func toggle(_ id: Int) {
        if let i = picked.firstIndex(of: id) { if picked.count > 1 { picked.remove(at: i) } } else { picked.append(id); picked.sort() }
        refusal = nil
    }
    func begin(_ t: GroomTier) {
        guard phase == .picking, !picked.isEmpty else { return }
        tier = t; shopAlpha = 0; shopT = 0; cheerT = 0; skipRequested = false; dryerCaptioned = false; refusal = nil
        phase = .fadeOut
    }
    /// A tap during the visit: straight to the reveal.
    func skip() { if phase == .fadeOut || phase == .shop { skipRequested = true } }
    func say(_ s: String) { toast = s; toastT = 0 }
    func finish() { phase = .off; shopAlpha = 0; shopT = 0; cheerT = 0; skipRequested = false; onEnd() }

    /// Once per fixed step. `blocked`: something started under the fade (checked while fading out).
    func step(dt: Float, blocked: Bool = false) {
        if toast != nil { toastT += dt; if toastT > GroomTuning.toastSeconds { toast = nil } }
        switch phase {
        case .off, .picking: break
        case .fadeOut:
            if blocked { finish(); return }
            shopAlpha = min(shopAlpha + dt / GroomTuning.fadeOut * (skipRequested ? 4 : 1), 1)
            if shopAlpha >= 1 {
                guard onSwap() else { finish(); return }
                phase = .shop; shopT = skipRequested ? GroomTuning.shopSeconds : 0
            }
        case .shop:
            shopT = skipRequested ? GroomTuning.shopSeconds : min(shopT + dt, GroomTuning.shopSeconds)
            if shopT >= GroomTuning.shopSeconds { phase = .reveal; cheerT = 0; onReveal() }
        case .reveal:
            cheerT += dt
            shopAlpha = max(shopAlpha - dt / GroomTuning.fadeIn, 0)
            if shopAlpha <= 0 { phase = .cheer }
        case .cheer:
            cheerT += dt
            if cheerT >= GroomTuning.cheerSeconds { finish() }
        }
    }
}

/// What GameCare keeps while the visit is on.
@MainActor
final class GroomBook {
    var actors: [JellyActor] = []
    var autonomy: [Int: Bool] = [:]
    var emoted: Set<Int> = [], twirled: Set<Int> = []
    var charged = 0
    var lastTick: Double?
    nonisolated deinit {}
}
