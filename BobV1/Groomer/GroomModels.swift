//
//  GroomModels.swift
//  The Groomer ("Jelly Spa") as data and a pure state machine (CafeTrip style): three tiers priced per Jelbie, the picker's state, the cut-scene's clock
//  (white fade out, ~7.6 s on the 3D street outside the Jelly Spa (GroomRoom.swift), the door opens and they hop out, the cheer, white fade home). It owns no bodies: GameCare+Groom.swift does the swap and the reveal.
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
    static func refusal(total: Int, wallet: Int) -> String? { total <= wallet ? nil : "You need \(total - wallet) more JellyCoins. Races pay JellyCoins!" }
}

nonisolated enum GroomTuning {
    static let fadeOut: Float = 0.5, fadeIn: Float = 0.6, holdSteps = 8
    /// Seconds outside the shop before the door opens (the ambience clip is 8.5 s; the reveal cuts it).
    static let shopSeconds: Float = 7.6
    /// The dryer (steam puffs, "Hair dryer humming") runs from here.
    static let dryerAt: Float = 4.2
    /// How long they hop and cheer at the door, then the fade home. `twirlAt` is the second beat of the cheer.
    static let cheerSeconds: Float = 6.2, cheerStagger: Float = 0.25, twirlAt: Float = 1.7
    static let doorOpen: Float = 0.55, walkOut: Float = 1.4
    static let toastSeconds: Float = 2.5
    static let lineSpacing: Float = 1.5
    static let clipBell = "groom_bell", clipAmbience = "groom_ambience", clipReveal = "groom_reveal"
}

@MainActor
@Observable
final class GroomTrip {
    enum Phase { case off, picking, fadeOut, arriveIn, shop, reveal, leaveOut, leaveIn }
    enum Dest { case shop, home }

    private(set) var phase: Phase = .off
    private(set) var tier: GroomTier = .quick
    /// Roster ids who go.
    var picked: [Int] = []
    /// 0...1: the white overlay over the 3D street (the swaps happen at exactly 1).
    private(set) var wipe: Float = 0
    /// Seconds at the shop (0...shopSeconds), and since the door opened.
    private(set) var shopT: Float = 0
    private(set) var cheerT: Float = 0
    @ObservationIgnored private var holdFrames = 0
    var refusal: String?          // the picker's inline line
    var toast: String?
    @ObservationIgnored var toastT: Float = 0
    @ObservationIgnored var skipRequested = false
    @ObservationIgnored var dryerCaptioned = false
    /// The world swaps, with the white opaque (GameCare+Groom.swift). The shop swap returns false when the visit cannot start (nothing charged, back home).
    @ObservationIgnored var onSwap: (Dest) -> Bool = { _ in true }
    /// The door opens: the reveal sound and the line-up's emotes.
    @ObservationIgnored var onReveal: () -> Void = {}
    @ObservationIgnored var onEnd: () -> Void = {}

    nonisolated deinit {}

    var active: Bool { phase != .off }
    var picking: Bool { phase == .picking }
    /// The 3D street is the room now (the swap to it happened and the one back has not).
    var inScene: Bool { phase == .arriveIn || phase == .shop || phase == .reveal || phase == .leaveOut }
    var dryerOn: Bool { phase == .shop && shopT >= GroomTuning.dryerAt }
    var celebrating: Bool { phase == .reveal }
    var doorOpen: Float { phase == .reveal ? min(cheerT / GroomTuning.doorOpen, 1) : (phase == .leaveOut ? 1 : 0) }

    func openPicker(all: [Int]) { guard phase == .off else { return }; picked = all; refusal = nil; phase = .picking }
    func cancelPicker() { if phase == .picking { phase = .off; refusal = nil } }
    func toggle(_ id: Int) {
        if let i = picked.firstIndex(of: id) { if picked.count > 1 { picked.remove(at: i) } } else { picked.append(id); picked.sort() }
        refusal = nil
    }
    /// Starts the fade out (after the run-out; the picker is closed meanwhile).
    func begin(_ t: GroomTier) {
        guard (phase == .picking || phase == .off), !picked.isEmpty else { return }
        tier = t; wipe = 0; shopT = 0; cheerT = 0; holdFrames = 0; skipRequested = false; dryerCaptioned = false; refusal = nil
        phase = .fadeOut
    }
    /// The picker closes while the Jelbies run out; `begin` follows.
    func closePicker() { if phase == .picking { phase = .off; refusal = nil } }
    /// A tap during the visit: straight to the door.
    func skip() { if phase == .arriveIn || phase == .shop { skipRequested = true } }
    func say(_ s: String) { toast = s; toastT = 0 }
    func finish() { phase = .off; wipe = 0; shopT = 0; cheerT = 0; skipRequested = false; onEnd() }

    /// Once per fixed step. `blocked`: something started under the fade (checked while fading out).
    func step(dt: Float, blocked: Bool = false) {
        if toast != nil { toastT += dt; if toastT > GroomTuning.toastSeconds { toast = nil } }
        switch phase {
        case .off, .picking: break
        case .fadeOut:
            if blocked { finish(); return }
            wipe = min(wipe + dt / GroomTuning.fadeOut, 1)
            if wipe >= 1 {
                guard onSwap(.shop) else { finish(); return }
                phase = .arriveIn; holdFrames = 0; shopT = 0
            }
        case .arriveIn:
            holdFrames += 1
            if holdFrames > GroomTuning.holdSteps { wipe = max(wipe - dt / GroomTuning.fadeIn * (skipRequested ? 3 : 1), 0) }
            if skipRequested { shopT = GroomTuning.shopSeconds }
            if wipe <= 0 { phase = .shop }
        case .shop:
            shopT = skipRequested ? GroomTuning.shopSeconds : min(shopT + dt, GroomTuning.shopSeconds)
            if shopT >= GroomTuning.shopSeconds { phase = .reveal; cheerT = 0; onReveal() }
        case .reveal:
            cheerT += dt
            if cheerT >= GroomTuning.cheerSeconds { phase = .leaveOut }
        case .leaveOut:
            wipe = min(wipe + dt / GroomTuning.fadeOut, 1)
            if wipe >= 1 { _ = onSwap(.home); phase = .leaveIn; holdFrames = 0 }
        case .leaveIn:
            holdFrames += 1
            if holdFrames > GroomTuning.holdSteps { wipe = max(wipe - dt / GroomTuning.fadeIn, 0) }
            if wipe <= 0 { finish() }
        }
    }
}

/// What GameCare keeps while the visit is on.
@MainActor
final class GroomBook {
    var actors: [JellyActor] = []
    var autonomy: [Int: Bool] = [:]
    var homes: [Int: SIMD2<Float>] = [:]
    var emoted: Set<Int> = [], twirled: Set<Int> = []
    /// Who has hopped out of the door (the others are not drawn).
    var out: Set<Int> = []
    var charged = 0
    var lastTick: Double?
    var fxShown = false
    nonisolated deinit {}
}
