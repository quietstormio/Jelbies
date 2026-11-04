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
        guard var gap = ContactField.gap(a.steerID, b.steerID, features: features) else { if ContactTrace.on { ContactTrace.mod(a.steerID) { $0.step = "nil" } }; return nil }
        if support, let sg = ContactField.skinGap(a.steerID, b.steerID) { gap = min(gap, sg) }          // (the catalogue's support gap - the harness's ground truth - is the stricter of the two when the bodies stand staggered or turn)
        let stamp = ContactField.stamp(a.steerID) &+ ContactField.stamp(b.steerID) &* 7919
        let key = b.steerID
        if a.socialBook.settleStamp[key] == stamp { if ContactTrace.on { ContactTrace.mod(a.steerID) { $0.step = "stamp"; $0.e = gap - target } }; return (gap, false) }          // (this measurement was acted on)
        a.socialBook.settleStamp[key] = stamp
        let e = gap - target
        let prev = a.socialBook.settleGap[key]
        a.socialBook.settleGap[key] = e
        if onlySeparate, e >= 0 {          // (nothing to separate any more: the lean-away that did it is let go, else a body stays tipped away from a partner who is no longer there)
            if !anchoredA, a.socialBook.trimPartner == b.steerID { a.socialBook.leanTrim *= 0.9 }
            if !anchoredB, b.socialBook.trimPartner == a.steerID { b.socialBook.leanTrim *= 0.9 }
        }
        if (onlySeparate && e >= 0) || (anchoredA && anchoredB) { if ContactTrace.on { ContactTrace.mod(a.steerID) { $0.step = (anchoredA && anchoredB) ? "anchored" : "onlySep"; $0.e = e } }; return (gap, false) }
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
            if abs(ePred) <= ContactSettleTuning.deadband { if ContactTrace.on { ContactTrace.mod(a.steerID) { $0.step = "deadband"; $0.e = e } }; return (gap, false) }
            c = max(-ContactSettleTuning.maxStep * 2, min(ContactSettleTuning.maxStep * 2, ePred * ContactSettleTuning.gain))
        } else {          // near: trim the average
            let eAvg = ema - target
            if abs(eAvg) <= ContactSettleTuning.deadband * 0.6 { if ContactTrace.on { ContactTrace.mod(a.steerID) { $0.step = "deadbandNear"; $0.e = e } }; return (gap, false) }
            c = max(-ContactSettleTuning.maxStep * 0.3, min(ContactSettleTuning.maxStep * 0.3, eAvg * ContactSettleTuning.fineGain))
        }
        let axis = simd_normalize(ContactField.root(b.steerID) - ContactField.root(a.steerID) + SIMD2(1e-6, 0))
        let share: Float = (anchoredA || anchoredB) ? 1 : 0.5
        let m = max(-cap, min(cap, c * share))
        if ContactTrace.on { let kind = (urgent && e < -ContactSettleTuning.deadband) ? "urgent" : (abs(e) > ContactSettleTuning.fineBand ? "far" : "near"); ContactTrace.mod(a.steerID) { $0.step = kind; $0.e = e; $0.c = c; $0.m = m } }
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
            if ContactTrace.on { ContactTrace.mod(steerID) { $0.nudge = "lying" } }
            px += d.x; pz += d.y
            if idleState.kind == .sleep {
                sleep.spot += d
                if let sim = contactSim { sim.shift(byXZ: d) }
            }
            return
        }
        // A hop's crouch and landing recovery are PLANTED (the soles are on the floor): only the hop's landing spot moves while it crouches, and the landing recovers by the lean. In the air - the hop's flight, a flap-hop,
        // both soles up - nothing is planted and the whole body warps rigidly (root, soles, the swing foot's own from / to, the hop's start / end, the sim body).
        let gaitAir = gait.isBusy && gait.phase != .crouch && gait.phase != .land && gait.phase != .recover
        if gait.isBusy, gait.phase == .crouch, !flapHop.active, !airBothFeet {
            if ContactTrace.on { ContactTrace.mod(steerID) { $0.nudge = "crouch" } }
            gait.nudgeLanding(d)
            return
        }
        let airborne = gaitAir || flapHop.active || airBothFeet
        if airborne {
            if ContactTrace.on { ContactTrace.mod(steerID) { $0.nudge = "air" } }
            px += d.x; pz += d.y
            stepRoot0 += d
            feet.nudge(d)
            if gait.isBusy { gait.nudge(d) }
            if flapHop.active { flapHop.from += d }
            contactSim?.shift(byXZ: d)
            return
        }
        if case .walk = script { if ContactTrace.on { ContactTrace.mod(steerID) { $0.nudge = "walk" } }; return }          // (walking: the destination carries it)
        // planted: lean. d is along the axis to the partner: its length is the cm to close (+) or give (-); a lean of theta moves the contact point ~ theta/2 m (the cheeks sit ~0.5 m up)
        guard let pid = socialPartnerID, let o = socialBrain(pid) else { return }
        let toward = simd_dot(d, simd_normalize(o.position - position + SIMD2(1e-6, 0)))
        socialBook.trimPartner = pid
        let want = socialBook.leanTrim + toward * ContactTuning.leanPerMetre
        if abs(want) > ContactTuning.leanBudget {          // beyond the budget: one small shuffle step on the locomotion (soles stay put until then)
            socialBook.leanTrim = max(-ContactTuning.leanBudget, min(ContactTuning.leanBudget, want))
            if socialBook.shuffleReq == 0, toward > 0 { socialBook.shuffleReq = 1 }          // (forward only: a backward step would turn the walker round)
        } else { socialBook.leanTrim = want }
        if ContactTrace.on { let sr = socialBook.shuffleReq; ContactTrace.mod(steerID) { $0.nudge = (abs(want) > ContactTuning.leanBudget ? "lean+budget" : "lean") + "/req\(sr)"; $0.want = want } }
    }

    /// Adds the lean trim to this tick's lean overlay (after the emote's drive set its own): toward the partner with the soles fixed. Then the LEAN LIMITER (2026-11-04, "every move peaks at skin contact, never past it"):
    /// the lean toward the partner (the emote's own lunge + the trim) may grow only by what the skins still have to travel (`leanPerMetre` x the gap above the hold, shared with the partner when he leans too); when the
    /// skins already press it is taken back. The drives' lunges (bump, boop, chest bump ...) used to carry the pair 5 - 15 cm into each other at the peak.
    func contactApplyLean() {
        guard let s = social else { return }
        let pid = socialPartnerID ?? (socialBook.trimPartner >= 0 ? socialBook.trimPartner : -1)
        guard pid >= 0, let o = socialBrain(pid) else { return }
        let local = rotXZ(o.position - position, -yaw), ln = max(simd_length(local), 1e-3)
        let nr = -local.x / ln, np = local.y / ln          // lean toward the partner = roll * nr + pitch * np
        if abs(socialBook.leanTrim) > 1e-4, socialBook.trimPartner == pid {
            socialBook.wantRoll += nr * socialBook.leanTrim
            socialBook.wantPitch += np * socialBook.leanTrim
        }
        guard ContactTuning.leanLimiter, ContactField.enabled, let st = contactStance(with: o), st.cls != .none, !s.kind.isGroup,
              var g = ContactField.gap(steerID, pid, features: st.features) else { return }
        if let sg = ContactField.skinGap(steerID, pid) { g = min(g, sg) }
        let floor: Float = st.cls == .touching ? ContactStance.hold : ContactStance.near
        let wantToward = socialBook.wantRoll * nr + socialBook.wantPitch * np
        let applied = socialBook.roll * nr + socialBook.pitch * np
        let anchoredPartner = o.held || o.idleState.kind == .sleep || o.idleState.kind == .decorSit
        let share: Float = anchoredPartner ? 1 : 0.5
        let allowed = applied + (g - floor) * ContactTuning.leanPerMetre * share
        if wantToward > allowed {
            let ex = wantToward - allowed
            socialBook.wantRoll -= nr * ex; socialBook.wantPitch -= np * ex
            if ContactTrace.on { ContactTrace.mod(steerID) { $0.nudge += "|limit" } }
        }
    }

    /// The pair's touch distance for the walk destination, STABLE (2026-11-04): the live support reach swings 0.39 ... 1.6 m while the legs step, so a destination derived from it every tick jumps and the pair
    /// chases itself. Captured along the stance axis `u` (partner -> destination) at a STANDING moment (both planted: `ContactField.touchDistance(_:_:dir:)` of the standing profiles); until such a moment the
    /// value is a hard low-pass of the live one (first sample clamped to a plausible 0.6 ... 1.5 m, then an EMA with a rate clamp). Kept per (walker, partner) in `ContactTouchMemory`, reset per session / phase,
    /// and re-captured when the axis turns by more than 25 degrees (front-to-front touches closer than side-by-side).
    func contactStableTouch(_ p: BlobBrain, axis u: SIMD2<Float>) -> Float? {
        guard let s = social, let raw = (ContactStance.entry(s.kind).flatMap { touchRadiusFacing(p, along: u, $0.facing) } ?? touchRadius(p, along: u)) else { return nil }
        let key = steerID &* 4096 &+ p.steerID
        let sid = ObjectIdentifier(s)
        func planted(_ b: BlobBrain) -> Bool { !b.gait.isBusy && !b.flapHop.active && !b.airBothFeet && !b.feet.active }
        var e = ContactTouchMemory.store[key]
        if let x = e, x.session != sid || x.phase != s.phase || simd_dot(x.axis, u) < 0.906 || s.t + 0.001 < x.clock { e = nil }
        if var x = e {
            if !x.frozen {
                if planted(self), planted(p), simd_distance(position, p.position) < 1.9 { x.d = raw; x.frozen = true }          // (standing AND close: a pair planted at the start of the session, 3 m apart, has not arrived yet)
                else { x.d = max(0.55, min(1.6, x.d + max(-0.03, min(0.03, (raw - x.d) * 0.12)))) }          // (the live value, low-passed: side-on the pair touches at ~1.4 m, facing each other at ~0.75 m - the first sample is not the stance's)
            }
            x.clock = s.t
            ContactTouchMemory.store[key] = x
            return x.d
        }
        let standing = planted(self) && planted(p) && simd_distance(position, p.position) < 1.9
        let d0 = standing ? raw : max(0.6, min(1.5, raw))
        let x = ContactTouchMemory.Entry(session: sid, phase: s.phase, axis: u, d: d0, d0: d0, frozen: standing, clock: s.t)
        ContactTouchMemory.store[key] = x
        return x.d
    }

    /// A walker never turns round to walk BACK (an overshoot): the turn on the spot swings the wide axis (arms, ears, 1.4 m across) through the partner. A destination behind the walker (against the way he
    /// was sent) becomes "stop here" (the walk ends with the current step); the settle's lean takes the rest.
    private func noTurnAround(_ want: SIMD2<Float>, was t: SIMD2<Float>, partner p: BlobBrain) -> SIMD2<Float> {
        guard simd_distance(position, p.position) < 1.3 else { return want }          // (far from him a turn is harmless)
        let fwd = SIMD2<Float>(sinf(yaw), cosf(yaw)), toNew = want - position
        return simd_dot(toNew, fwd) < -0.02 ? position : want
    }

    /// Once a tick for the session's brains: walkers get their destination re-derived from the (stable) touch distance along the line they were sent on (so the steps themselves end at the stance), and a planted body
    /// whose lean ran out takes one shuffle step (locomotion), proportional to the residual, then the trim is released. `retarget: false` (the stance step is `onlySeparate`: a part / step-apart walk) leaves
    /// every walk alone: it must not be rewritten to the touch point.
    func contactStanceWalk(partner p: BlobBrain, gapWanted: Float, features: Bool = true, retarget: Bool = true) {
        guard let sim = contactSim else { return }
        if ContactTrace.on {
            var w = "noWalk", tg = "-"
            if case .walk(let t, _) = script {
                let L = simd_distance(t, p.position); w = L >= 3.2 ? "far" : (L <= 0.3 ? "Lsmall" : "inRange")
                let toP = simd_normalize(p.position - position + SIMD2(1e-6, 0))
                let uu = simd_normalize(t - p.position + SIMD2(1e-6, 0))
                let tr = touchRadius(p, along: uu), td = ContactField.touchDistance(steerID, p.steerID)
                tg = String(format: "tgtAlong%.2f|tgtFromP%.2f|posFromP%.2f|touchRadius%@|touchDist%@", simd_dot(t - position, toP), L, simd_distance(position, p.position), tr.map { String(format: "%.3f", $0) } ?? "nil", td.map { String(format: "%.3f", $0) } ?? "nil")
            }
            ContactTrace.mod(steerID) { $0.walk = w; $0.tgt = tg }
        }
        if case .walk = script {} else { ContactTouchMemory.shuffling.remove(steerID); ContactTouchMemory.exact.remove(steerID); ContactTouchMemory.finalYaw[steerID] = nil; ContactTouchMemory.locked[steerID] = nil; ContactTouchMemory.rewrote.remove(steerID) }
        // THE DESTINATION IS DECIDED ONCE (motion warping): the last 0.8 m of a stance walk keep the spot they were given - the touch distance estimate wobbles +-4 cm with the jelly, and a spot that moves while the last two steps
        // are planned is how the walk used to end 10 cm off. Unlocked when the partner moves (a meeting pair: both walk to a spot fixed per phase, so that does not happen).
        if case .walk(let lt, _) = script, let lp = ContactTouchMemory.locked[steerID] {
            if simd_distance(lp.partner, p.position) > 0.05 || simd_distance(lp.target, lt) > 0.02 { ContactTouchMemory.locked[steerID] = nil }
        }
        let locked = ContactTouchMemory.locked[steerID] != nil
        if retarget, !locked, !ContactTouchMemory.shuffling.contains(steerID), case .walk(let t, let then) = script, simd_distance(t, p.position) < 3.2 {
            var u = t - p.position; let L = simd_length(u)
            ContactTouchMemory.exact.insert(steerID)          // (the stance owns this walk: planWalkStep lands its last step on the destination, within 1 cm)
            if let st = social.flatMap({ ContactStance.entry($0.kind) }), st.facing == .camera { ContactTouchMemory.finalYaw[steerID] = faceCameraYaw() } else { ContactTouchMemory.finalYaw[steerID] = nil }          // (side by side: the walk turns into the pose during its last steps)
            if L > 0.3 {
                u /= L
                var want: SIMD2<Float>, dist: Float, stable: Float?
                if case .walk(let tp, _) = p.script, let ses = social, p.social === ses {
                    // BOTH walk toward each other: each retargeting to "the partner's current spot + the touch distance" chases a moving spot and the pair overshoots into each other. The meeting point is
                    // fixed once per phase from the two drive destinations, and each takes half of the touch distance on its side of it (symmetric: neither target depends on the other's rewrite).
                    let key = min(steerID, p.steerID) &* 4096 &+ max(steerID, p.steerID), lo = steerID < p.steerID
                    let sid = ObjectIdentifier(ses), ph = ses.phase
                    var m = ContactTouchMemory.meet[key]
                    if m == nil || m!.session != sid || m!.phase != ph || ses.t + 0.001 < m!.clock {
                        let tLo = lo ? t : tp, tHi = lo ? tp : t
                        let ax = simd_normalize(tHi - tLo + SIMD2(1e-6, 0))
                        m = ContactTouchMemory.Meet(session: sid, phase: ph, mid: (tLo + tHi) / 2, axis: ax, clock: ses.t)
                        ContactTouchMemory.meet[key] = m
                    }
                    m!.clock = ses.t; ContactTouchMemory.meet[key] = m
                    let side: SIMD2<Float> = lo ? -m!.axis : m!.axis          // from the meeting point toward my side
                    stable = contactStableTouch(p, axis: side)
                    dist = (stable ?? 1.405) + max(gapWanted, ContactStance.arrive) + ContactStance.walkShort
                    want = fixed(m!.mid + side * (dist / 2))
                    if ContactTrace.on { ContactTrace.mod(steerID) { $0.tgt += "|meet" } }
                    let okFix = simd_distance(want, m!.mid + side * (dist / 2)) < 0.25
                    want = noTurnAround(want, was: t, partner: p)
                    let dT = simd_distance(want, t)
                    if okFix, dT > 0.01, dT < 1.2 { script = .walk(target: want, then: then); ContactTouchMemory.rewrote.insert(steerID) }
                } else {
                    stable = contactStableTouch(p, axis: u)
                    dist = (stable ?? 1.405) + max(gapWanted, ContactStance.arrive) + ContactStance.walkShort
                    want = fixed(p.position + u * dist)
                    let okFix = simd_distance(want, p.position + u * dist) < 0.25
                    want = noTurnAround(want, was: t, partner: p)
                    let dT = simd_distance(want, t)
                    if ContactTrace.on { ContactTrace.mod(steerID) { $0.tgt += String(format: "|stable%@", stable.map { String(format: "%.3f", $0) } ?? "nil") } }
                    if okFix, dT > 0.01, dT < 1.2 { script = .walk(target: want, then: then); ContactTouchMemory.rewrote.insert(steerID); if ContactTrace.on { ContactTrace.mod(steerID) { $0.walk = String(format: "fired(d%.3f,dist%.3f)", dT, dist) } } }
                    else if ContactTrace.on { ContactTrace.mod(steerID) { $0.walk = String(format: "skip(fixOK%d,dT%.3f,dist%.3f)", okFix ? 1 : 0, dT, dist) } }
                }
            }
        }
        if retarget, !locked, ContactTouchMemory.exact.contains(steerID), case .walk(let t, _) = script, simd_distance(position, t) < 0.8, ContactTouchMemory.rewrote.contains(steerID), ContactTouchMemory.finalYaw[steerID].map({ abs(wrapAngle($0 - yaw)) < 0.2 }) ?? true {          // (a body still turning into the pose has not got its final outline: its touch distance is read once it stands in it)
            ContactTouchMemory.locked[steerID] = (t, p.position)
        }
        if ContactTrace.on, socialBook.shuffleReq != 0 {
            let why = "blk(script\(scriptIsNone ? "None" : "Busy"),feet\(feet.active ? "Active" : "Idle"),idle\(idleState.kind.map { "\($0)" } ?? "nil"))"
            if !(scriptIsNone && !feet.active && (idleState.kind == nil || idleState.kind == .sit)) { ContactTrace.mod(steerID) { $0.shuffle = why } }
        }
        if socialBook.shuffleReq != 0, scriptIsNone, !feet.active, idleState.kind == nil || idleState.kind == .sit {
            let u = simd_normalize(p.position - position + SIMD2(1e-6, 0))
            // the residual from the LIVE gap (the lean is released by the step, so its share counts): the step is as long as the error, 3 ... 14 cm
            var step: Float = 0.14, trim = false
            if var g = ContactField.gap(steerID, p.steerID, features: features) {
                if let sg = ContactField.skinGap(steerID, p.steerID) { g = min(g, sg) }
                let need = (g - gapWanted) + socialBook.leanTrim / ContactTuning.leanPerMetre
                trim = need <= 0.2
                step = max(0.065, min(0.14, need))          // (forward only; 6.5 cm at least: a shorter walk 'arrives' at once, planWalkStep's arrival radius is 6 cm - the lean takes the overshoot back)
                if need < 0.038 { socialBook.shuffleReq = 0; return }          // (under that the lean covers it; the step's quantum is ~6 cm and the lean's reach +-2.7 cm)
            }
            let spot = fixed(position + u * step)
            socialBook.shuffleReq = 0
            let moved = simd_distance(spot, position)
            let ok = idleState.kind == nil && moved >= 0.5 * abs(step) && moved >= 0.02
            if ContactTrace.on { ContactTrace.mod(steerID) { $0.shuffle = (ok ? "STEP" : "step-dropped") + String(format: "(idle%@,step%.3f,moved%.3f)", idleState.kind.map { "\($0)" } ?? "nil", step, moved) } }
            if ok { socialBook.leanTrim = 0; socialWalk(to: spot, sim); if trim { ContactTouchMemory.shuffling.insert(steerID) } }          // (a big residual is an APPROACH, not a trim: the retarget carries that walk to the stance)
        } else if socialBook.shuffleReq != 0, !scriptIsNone { socialBook.shuffleReq = 0 }
    }
}

/// The stable touch distances of the walkers (`BlobBrain.contactStableTouch`): per (walker, partner). Kept here, not in SocialBook (a drive-side file).
@MainActor
enum ContactTouchMemory {
    struct Entry { var session: ObjectIdentifier; var phase: Int; var axis: SIMD2<Float>; var d: Float; var d0: Float; var frozen: Bool; var clock: Float = 0 }          // (clock: the session time of the last use - a freed session's identifier is reused by the next one, time going backwards = a stale entry)
    /// Bodies whose current walk IS a shuffle step (aimed by the residual, not to be retargeted to the stance spot).
    static var shuffling: Set<Int> = []
    /// Bodies whose walk is a stance walk (the destination is the stance spot): planWalkStep arrives within 1 cm and its final step covers exactly the remaining distance.
    static var exact: Set<Int> = []
    /// Bodies whose walk target the stance has rewritten at least once, and the ones whose target is locked for the last 0.8 m (target, the partner's position at the lock).
    static var rewrote: Set<Int> = []
    static var locked: [Int: (target: SIMD2<Float>, partner: SIMD2<Float>)] = [:]
    /// The heading a stance walk ends in when it is not 'facing the partner' (side by side: facing the camera); planWalkStep turns into it during the last steps.
    static var finalYaw: [Int: Float] = [:]
    static var store: [Int: Entry] = [:]
    /// Two walkers heading for each other: their meeting point and axis (lower steerID -> higher), fixed once per session phase.
    struct Meet { var session: ObjectIdentifier; var phase: Int; var mid: SIMD2<Float>; var axis: SIMD2<Float>; var clock: Float = 0 }
    static var meet: [Int: Meet] = [:]
    /// A session's identifier is reused by the next session once the old one is freed, and these tables are keyed by body: when a session's clock runs BACKWARDS (a new session under an old identifier) its bodies' entries are dropped.
    static var clocks: [ObjectIdentifier: Float] = [:]
    static func begin(_ s: SocialSession) {
        let id = ObjectIdentifier(s)
        if clocks[id].map({ s.t + 0.001 < $0 }) ?? true { purge(s.crewIDs.isEmpty ? [s.idA, s.idB, s.idC] : s.crewIDs) }
        clocks[id] = s.t
        if clocks.count > 64 { clocks = clocks.filter { $0.key == id } }
    }
    static func purge(_ ids: [Int]) {
        for i in ids where i >= 0 { shuffling.remove(i); exact.remove(i); finalYaw[i] = nil; locked[i] = nil; rewrote.remove(i) }
        let set = Set(ids)
        store = store.filter { !(set.contains($0.key / 4096) || set.contains($0.key % 4096)) }
        meet = meet.filter { !(set.contains($0.key / 4096) || set.contains($0.key % 4096)) }
    }
}
