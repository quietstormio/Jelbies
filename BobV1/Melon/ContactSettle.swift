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
    nonisolated(unsafe) static var stanceUrgent = true          // the stance ticks' fast way out of an overlap. A/B 2026-11-03 with the geometry fixed: OFF is worse everywhere (leapfrog -119, circleDance -57, squabble -29, spinHug -14, tag -18 vs -9 / -18 / -5 / -3 / -4)
    nonisolated(unsafe) static var fineBand: Float = 0, fineAlpha: Float = 1.0 / 45, fineGain: Float = 0.12
}

@MainActor
enum ContactSettle {
    /// One step for the pair. Returns the measured skin gap (nil: no profile yet), `moved` = whether the roots were nudged.
    @discardableResult
    static func step(_ a: BlobBrain, _ b: BlobBrain, target: Float = 0, anchoredA: Bool = false, anchoredB: Bool = false, onlySeparate: Bool = false, features: Bool = false, urgent: Bool = false, support: Bool = false) -> (gap: Float, moved: Bool)? {
        guard var gap = ContactField.gap(a.steerID, b.steerID, features: features) else { return nil }
        if support, let sg = ContactField.skinGap(a.steerID, b.steerID) { gap = min(gap, sg) }          // (the catalogue's support gap - the harness's ground truth - is the stricter of the two when the bodies stand staggered or turn)
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
        var cap = ContactSettleTuning.maxStep
        if urgent, e < -ContactSettleTuning.deadband {          // (sunk in during a fast move - a lean, a hop: the way out is quick, 5 cm a step at most; the way in stays gentle)
            let ePred = e + ContactSettleTuning.lead * (e - (prev ?? e))
            c = max(-0.16, min(ePred, e)); cap = 0.08
        } else if abs(e) > ContactSettleTuning.fineBand {          // far: the fast approach, on the error where it is heading (the skin trails the root)
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
        let m = max(-cap, min(cap, c * share))
        if !anchoredA { a.contactNudge(axis * m) }
        if !anchoredB { b.contactNudge(-axis * m) }
        return (gap, true)
    }
}

extension BlobBrain {
    /// The settle's output for one body: `d` is the move along the pair axis the controller wants (+ toward the partner). A body whose soles are PLANTED never slides: the move is consumed by ONE channel
    /// chosen by what the body is doing (2026-11-04, the skating rule):
    ///   lying / asleep / outside a session   the root moves (rigid lying body; the settle tests) - as before
    ///   WALKING                              nothing here: the walk's own destination is re-derived from the touch distance every tick (`contactRetarget`)
    ///   AIRBORNE (hop, flap-hop, both feet up)   a rigid warp: root, stepRoot0, soles, the hop's start / end, the winged hop's start and the sim body move together, at once
    ///   PLANTED (standing, sitting, a spin on the spot)   the body LEANS toward / away from the partner with the soles fixed (`leanTrim`, a budget of `leanBudget` rad); a residual beyond it asks the
    ///                                        locomotion for one small shuffle step (`shuffleReq`), the only way feet move
    func contactNudge(_ d: SIMD2<Float>) {
        let lying = idleState.kind == .sleep || idleState.kind == .lieDown || idleState.kind == .flop
        guard social != nil, !lying else {
            px += d.x; pz += d.y
            if idleState.kind == .sleep {
                sleep.spot += d
                if let sim = contactSim { sim.shift(byXZ: d) }
            }
            return
        }
        let airborne = gait.isBusy || flapHop.active || airBothFeet
        if airborne {
            px += d.x; pz += d.y
            stepRoot0 += d
            if feet.pos.count > 1 { feet.pos[0] += d; feet.pos[1] += d }
            if gait.isBusy { gait.nudge(d) }
            if flapHop.active { flapHop.from += d }
            contactSim?.shift(byXZ: d)
            return
        }
        if case .walk = script { return }          // (walking: the destination carries it)
        // planted: lean. d is along the axis to the partner: its length is the cm to close (+) or give (-); a lean of theta moves the contact point ~ theta/2 m (the cheeks sit ~0.5 m up)
        guard let pid = socialPartnerID, let o = socialBrain(pid) else { return }
        let toward = simd_dot(d, simd_normalize(o.position - position + SIMD2(1e-6, 0)))
        socialBook.trimPartner = pid
        let want = socialBook.leanTrim + toward * ContactTuning.leanPerMetre
        if abs(want) > ContactTuning.leanBudget {          // beyond the budget: one small shuffle step on the locomotion (soles stay put until then)
            socialBook.leanTrim = max(-ContactTuning.leanBudget, min(ContactTuning.leanBudget, want))
            if socialBook.shuffleReq == 0 { socialBook.shuffleReq = toward > 0 ? 1 : -1 }
        } else { socialBook.leanTrim = want }
    }

    /// Adds the lean trim to this tick's lean overlay (after the emote's drive set its own): toward the partner with the soles fixed.
    func contactApplyLean() {
        guard abs(socialBook.leanTrim) > 1e-4, let o = socialBrain(socialBook.trimPartner), social != nil else { return }
        let local = rotXZ(o.position - position, -yaw), ln = max(simd_length(local), 1e-3)
        socialBook.wantRoll += -local.x / ln * socialBook.leanTrim
        socialBook.wantPitch += local.y / ln * socialBook.leanTrim
    }

    /// Once a tick for the session's brains: walkers get their destination re-derived from the touch distance along the line they were sent on (so the steps themselves end at the stance), and a planted body
    /// whose lean ran out takes one shuffle step (locomotion), then the trim is released.
    func contactStanceWalk(partner p: BlobBrain, gapWanted: Float) {
        guard let sim = contactSim else { return }
        if case .walk(let t, let then) = script, simd_distance(t, p.position) < 3.2 {
            var u = t - p.position; let L = simd_length(u)
            if L > 0.5 {
                u /= L
                let dist = (touchRadius(p, along: u) ?? 1.405) + max(gapWanted, ContactStance.arrive)
                let want = fixed(p.position + u * dist)
                if simd_distance(want, p.position + u * dist) < 0.1, simd_distance(want, t) > 0.02, simd_distance(want, t) < 0.6 { script = .walk(target: want, then: then) }
            }
        }
        if socialBook.shuffleReq != 0, scriptIsNone, !feet.active, idleState.kind == nil || idleState.kind == .sit {
            let u = simd_normalize(p.position - position + SIMD2(1e-6, 0))
            let step: Float = 0.14 * Float(socialBook.shuffleReq)
            let spot = fixed(position + u * step)
            socialBook.shuffleReq = 0
            if idleState.kind == nil, simd_distance(spot, position) > 0.1 { socialBook.leanTrim = 0; socialWalk(to: spot, sim) }
        } else if socialBook.shuffleReq != 0, !scriptIsNone { socialBook.shuffleReq = 0 }
    }
}
