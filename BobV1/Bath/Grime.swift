//
//  Grime.swift
//  DIRT (0...1) builds up on his body as he roams: soft charcoal / soot smudges on his skin (BathShaders.metal draws them from
//  `BathLook.soot`, which is seeded from this). `coat` is its named tier.
//  Persisted (UserDefaults, like BlobNeeds.v1). Also: the room sparkle left by a clean-up, which fades slowly and ends when he is dirty again,
//  and a tiny Drops wallet (earned-only currency; races and care will feed it).
//

import Foundation
import UIKit
import Observation
import simd

/// Earned-only currency: it comes from competitions only (races now; more games later), never from care and never from real money.
/// Plus a one-time starter balance (StoreBook). Spent in the store.
@MainActor
@Observable
final class DropsWallet {
    private(set) var count = 0
    @ObservationIgnored private let persists: Bool
    static let key = "BlobDrops.v1"
    init(persists: Bool = true) {
        self.persists = persists
        if persists { count = UserDefaults.standard.integer(forKey: Self.key) }
    }
    nonisolated deinit {}
    /// Drops earned (not silent top-ups): the care glue lets a Jelly jump for joy.
    @ObservationIgnored var onEarn: ((Int) -> Void)?
    func add(_ n: Int = 1, silent: Bool = false) {
        if n > 0, !silent { AudioHub.shared.play(.coin); onEarn?(n) }
        count += n
        if persists { UserDefaults.standard.set(count, forKey: Self.key) }
    }
    /// Spends `n` Drops; false (and nothing changes) when there are not enough.
    @discardableResult
    func spend(_ n: Int) -> Bool {
        guard n >= 0, n <= count else { return false }
        count -= n
        if persists { UserDefaults.standard.set(count, forKey: Self.key) }
        if n > 0 { AudioHub.shared.play(.purchase); UIImpactFeedbackGenerator(style: .light).impactOccurred() }          // every spend: food, toys, decor, wearables, café, spa, trick pages, the adoption fee
        return true
    }
}

@MainActor
@Observable
final class BlobGrime {
    /// 0...1, the shine left from the last clean-up.
    var sparkle: Float = 0
    /// 0...1, how dirty he is (the source of truth; the soot render reads it). A finished Clean sets it to 0.
    var dirt: Float = 0

    typealias CoatTier = JellyCoatTier
    var coat: CoatTier { CoatTier.of(dirt: dirt, sparkle: sparkle) }
    @ObservationIgnored private(set) var distance: Float = 0
    @ObservationIgnored private var saveT: Float = 0
    @ObservationIgnored private var rng: UInt32
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let now: () -> Date
    /// Like BlobNeeds: while set, `save()` keeps this as the timestamp so a background save cannot stamp over unapplied away time.
    @ObservationIgnored private var awaySince: Date?
    @ObservationIgnored private(set) var lastAway: TimeInterval = 0
    @ObservationIgnored var dirtPerUnit = GrimeTuning.dirtPerUnit
    /// The perks of this Jelly (shine: the sparkle fades slower; tidy: lint comes back slower). Set by his profile.
    @ObservationIgnored var perks: JellyPerks?

    init(persists: Bool = true, seed: UInt32 = 0xB47B, defaults: UserDefaults = .standard, key: String = GrimeTuning.defaultsKey, now: @escaping () -> Date = Date.init) {
        self.persists = persists
        self.defaults = defaults
        self.key = key
        self.now = now
        rng = seed
        if persists { load() }
    }
    nonisolated deinit {}

    private func rand() -> Float { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return Float(rng >> 8) / Float(1 << 24) }

    /// Walking / running adds dirt (`dirtPerUnit` per floor unit moved; `exerting` = run / zoomies / slide / scoot makes it 3x). `travelled` is the
    /// floor distance moved this step (0 when idle).
    func step(dt: Float, travelled: Float, exerting: Bool = false) {
        if sparkle > 0 { sparkle = max(0, sparkle - dt * (perks?.cache.fade ?? 1) / GrimeTuning.sparkleFade) }
        if travelled > 0 { addDirt(travelled * dirtPerUnit * (exerting ? GrimeTuning.exertionMul : 1) * (perks?.cache.dirt ?? 1)) }
        saveT += dt
        if saveT > GrimeTuning.saveEvery { saveT = 0; save() }
    }

    /// More dirt (clamped to 1). The sparkle ends the moment he is no longer clean.
    func addDirt(_ x: Float) {
        dirt = min(1, max(0, dirt + x))
        if dirt >= GrimeTuning.cleanBelow { sparkle = 0 }
    }

    // MARK: persistence

    private struct Saved: Codable {
        struct Bit: Codable { var k: UInt8; var d: [Float]; var s: Float; var z: Float }
        var bits: [Bit]?; var sparkle: Float; var distance: Float; var made: Int?; var at: Double; var dirt: Float?
    }
    func save() {
        guard persists else { return }
        let s = Saved(bits: nil, sparkle: sparkle, distance: distance, made: nil, at: (awaySince ?? now()).timeIntervalSince1970, dirt: dirt)
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }
    private func load() {
        guard let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        distance = s.distance; dirt = min(1, max(0, s.dirt ?? 0))
        sparkle = s.sparkle
        applyAway(seconds: now().timeIntervalSince1970 - s.at, endingAt: now())
        save()
    }

    /// The app left the foreground: stamp the time and save (see `awaySince`).
    func leaveActive(at t: Date? = nil) {
        if awaySince == nil { awaySince = t ?? now() }
        save()
    }

    /// The app came back: apply the time since `leaveActive` once.
    @discardableResult
    func returnActive(at t: Date? = nil) -> TimeInterval {
        guard let since = awaySince else { return 0 }
        awaySince = nil
        let away = TimeAway.clamp((t ?? now()).timeIntervalSince(since))
        applyAway(seconds: away, endingAt: t ?? now())
        save()
        return away
    }

    /// THE time-away path (cold launch and foreground resume). The sparkle fades at the wall-clock rate; dirt grows +0.05 per 2 h away, at most +0.15
    /// from one absence (the sparkle also ends if that takes him past `cleanBelow`).
    func applyAway(seconds: TimeInterval, endingAt end: Date? = nil) {
        let away = TimeAway.clamp(seconds)
        lastAway = away
        awaySince = nil
        var fadeAway = away, dirtAway = away
        if let end, let pk = PerkTuning.key(forGrime: key) {          // shine / tidy that were on during the absence slow the fade / the lint
            let from = end.addingTimeInterval(-away)
            let ex = PerkStore.load(defaults: defaults, key: pk)
            if let e = ex[.shine] { fadeAway = PerkStore.effective(away: away, covered: PerkStore.overlap(expiry: e, from: from, to: end), mul: Double(PerkTuning.shineFade)) }
            if let e = ex[.tidy] { dirtAway = PerkStore.effective(away: away, covered: PerkStore.overlap(expiry: e, from: from, to: end), mul: Double(PerkTuning.tidyDirt)) }
        }
        sparkle = AwayMath.sparkle(sparkle, awaySeconds: fadeAway)
        addDirt(AwayMath.dirtGain(awaySeconds: dirtAway))
    }
}
