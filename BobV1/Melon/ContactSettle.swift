//
//  ContactSettle.swift
//  The settle controller of the touching stances (hug, cheek bump, spin hug, lying snuggle, sleep pile, huddle ...): measure the pair's SKIN GAP (ContactProfile.swift) and nudge the
//  roots along the pair axis by the error until the drawn skins just touch: band -0.5 ... +0.5 cm, bodies may press a few mm (plush), never deform each other.
//    - once per fresh profile (a skin pass), so the few sim steps between two frames never act on the same stale measurement;
//    - a first-order approach: gain `gain` of the error a step, at most `maxStep` (1.5 cm) a step, nothing inside the deadband: critically damped by construction (no overshoot);
//    - the error is split between the two bodies unless one is ANCHORED (asleep, lying first, held, planted by a script): he does not move, the other takes it all.
//  Call it from the stance's per-step code. `target` is the skin gap wanted (0 = touching). `features: true` = the gap counts the features (wings at their current fold, spikes,
//  daisy): a folded wing between two backs is touched, never sunk into (the lying snuggle uses it). The contact sound / haptic are NOT here: `BlobBrain.contactTick` fires them at the first
//  touch, and the last mm of press does not fire again (re-armed only after the skins part by 3 cm).
//

import Foundation
import simd

nonisolated enum ContactSettleTuning {
    nonisolated(unsafe) static var deadband: Float = 0.005, maxStep: Float = 0.015, gain: Float = 0.15, lead: Float = 3          // lead: frames the skin trails the root (the error is judged where it is going)
    /// Within `fineBand` of the target the gap is trimmed on its slow average (a lying body breathes +-1 cm, a jelly wobbles): 0 = off.
    nonisolated(unsafe) static var fineBand: Float = 0, fineAlpha: Float = 1.0 / 45, fineGain: Float = 0.12
}

@MainActor
enum ContactSettle {
    /// One step for the pair. Returns the measured skin gap (nil: no profile yet), `moved` = whether the roots were nudged.
    @discardableResult
    static func step(_ a: BlobBrain, _ b: BlobBrain, target: Float = 0, anchoredA: Bool = false, anchoredB: Bool = false, onlySeparate: Bool = false, features: Bool = false) -> (gap: Float, moved: Bool)? {
        guard let gap = ContactField.gap(a.steerID, b.steerID, features: features) else { return nil }
        let stamp = ContactField.stamp(a.steerID) &+ ContactField.stamp(b.steerID) &* 7919
        let key = b.steerID
        if a.socialBook.settleStamp[key] == stamp { return (gap, false) }          // (this measurement was acted on)
        a.socialBook.settleStamp[key] = stamp
        let e = gap - target
        let prev = a.socialBook.settleGap[key]
        a.socialBook.settleGap[key] = e
        if (onlySeparate && e >= 0) || (anchoredA && anchoredB) { return (gap, false) }
        // the slow average of the gap: a lying body breathes (+-1 cm of skin), a jelly wobbles: the last centimetre is trimmed on the average, not chased
        var ema = a.socialBook.settleEMA[key] ?? gap
        if abs(gap - ema) > 0.03 { ema = gap }
        ema += (gap - ema) * ContactSettleTuning.fineAlpha
        a.socialBook.settleEMA[key] = ema
        var c: Float
        if abs(e) > ContactSettleTuning.fineBand {          // far: the fast approach, on the error where it is heading (the skin trails the root)
            let ePred = e + ContactSettleTuning.lead * (e - (prev ?? e))
            if abs(ePred) <= ContactSettleTuning.deadband { return (gap, false) }
            c = max(-ContactSettleTuning.maxStep * 2, min(ContactSettleTuning.maxStep * 2, ePred * ContactSettleTuning.gain))
        } else {          // near: trim the average
            let eAvg = ema - target
            if abs(eAvg) <= ContactSettleTuning.deadband * 0.6 { return (gap, false) }
            c = max(-ContactSettleTuning.maxStep * 0.3, min(ContactSettleTuning.maxStep * 0.3, eAvg * ContactSettleTuning.fineGain))
        }
        let axis = simd_normalize(ContactField.root(b.steerID) - ContactField.root(a.steerID) + SIMD2(1e-6, 0))
        let share: Float = (anchoredA || anchoredB) ? 1 : 0.5
        let m = max(-ContactSettleTuning.maxStep, min(ContactSettleTuning.maxStep, c * share))
        if !anchoredA { a.contactNudge(axis * m) }
        if !anchoredB { b.contactNudge(-axis * m) }
        return (gap, true)
    }
}

extension BlobBrain {
    /// Move the root by `d` (the settle controller: a few mm a step; the body follows through its pose).
    func contactNudge(_ d: SIMD2<Float>) { px += d.x; pz += d.y }
}
