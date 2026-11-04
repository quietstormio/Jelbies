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
        let airborne = gait.isBusy || flapHop.active || airBothFeet
        if airborne {
            if ContactTrace.on { ContactTrace.mod(steerID) { $0.nudge = "air" } }
            let d = simd_length(d) > 0.015 ? simd_normalize(d) * 0.015 : d          // (a rigid warp of the sim body strains the one-piece join: 1.5 cm a step at most, the settle asks again next step)
            px += d.x; pz += d.y
            stepRoot0 += d
            feet.shift(d)
            if gait.isBusy { gait.nudge(d) }
            if flapHop.active { flapHop.from += d }
            contactSim?.shift(byXZ: d)
            return
        }
        if case .walk = script { if ContactTrace.on { ContactTrace.mod(steerID) { $0.nudge = "walk" } }; return }          // (walking: the destination carries it)
        // planted: lean. d is along the axis to the partner: its length is the cm to close (+) or give (-); a lean of theta moves the contact point ~ theta/2 m (the cheeks sit ~0.5 m up)
        guard let pid = socialPartnerID, let o = socialBrain(pid) else { return }
        let toward = simd_dot(d, simd_normalize(o.position - position + SIMD2(1e-6, 0)))
        if toward > 0, contactTurning { if ContactTrace.on { ContactTrace.mod(steerID) { $0.nudge = "turning" } }; return }          // (the skin's reach toward him changes with the heading: the gap of a body that is still turning says nothing - closing on it makes the shuffle step that turns him back)
        socialBook.trimPartner = pid
        let want = socialBook.leanTrim + toward * ContactTuning.leanPerMetre
        if abs(want) > ContactTuning.leanBudget {          // beyond the budget: one small shuffle step on the locomotion (soles stay put until then)
            socialBook.leanTrim = max(-ContactTuning.leanBudget, min(ContactTuning.leanBudget, want))
            if socialBook.shuffleReq == 0, toward > 0 { socialBook.shuffleReq = 1 }          // (forward only: a backward step would turn the walker round)
        } else { socialBook.leanTrim = want }
        if ContactTrace.on { let sr = socialBook.shuffleReq; ContactTrace.mod(steerID) { $0.nudge = (abs(want) > ContactTuning.leanBudget ? "lean+budget" : "lean") + "/req\(sr)"; $0.want = want } }
    }

    /// Adds the lean trim to this tick's lean overlay (after the emote's drive set its own): toward the partner with the soles fixed.
    func contactApplyLean() {
        defer { contactGovernLean() }
        guard abs(socialBook.leanTrim) > 1e-4, let o = socialBrain(socialBook.trimPartner), social != nil else { return }
        let local = rotXZ(o.position - position, -yaw), ln = max(simd_length(local), 1e-3)
        socialBook.wantRoll += -local.x / ln * socialBook.leanTrim
        socialBook.wantPitch += local.y / ln * socialBook.leanTrim
    }

    /// THE LUNGE GOVERNOR (2026-11-04): a drive's lean (boop 0.20 rad, bump 0.22 rad EACH) is shaped for a standing distance it does not know; the peak of the move must land AT the skin contact, never past it. After
    /// the drive set its wants (and the trim was added), the lean toward the partner is capped at what the rest of the gap can take: applied lean + this body's half of the predicted gap / `ContactTuning.leanMetresPerRad`.
    /// Only caps (never adds), only while the stance asks for a target in this phase.
    func contactGovernLean() {
        guard ContactField.enabled, let s = social, s.end == nil, !s.kind.isGroup, let st = ContactStance.entry(s.kind), st.cls == .touching, let step = st.step(at: s.phase), let target = step.target,
              let p = (s.a === self ? s.b : s.a), p !== self, var g = ContactField.gap(steerID, p.steerID, features: st.features) else { return }
        if let sg = ContactField.skinGap(steerID, p.steerID) { g = min(g, sg) }
        let key = steerID &* 4096 &+ p.steerID
        let prev = s.t < 0.1 ? g : (ContactTouchMemory.govGap[key] ?? g)
        ContactTouchMemory.govGap[key] = g
        let gPred = g + ContactSettleTuning.lead * (g - prev)
        let local = rotXZ(p.position - position, -yaw), ln = max(simd_length(local), 1e-3)
        func toward(_ pitch: Float, _ roll: Float) -> Float { (pitch * local.y - roll * local.x) / ln }
        let applied = toward(socialBook.pitch, socialBook.roll)
        let want = toward(socialBook.wantPitch, socialBook.wantRoll)
        let cap = applied + 0.5 * (min(g, gPred) - target) / ContactTuning.leanMetresPerRad
        guard want > cap else { return }
        let over = want - cap
        socialBook.wantPitch -= over * local.y / ln
        socialBook.wantRoll += over * local.x / ln
        if ContactTrace.on { ContactTrace.mod(steerID) { $0.nudge += String(format: "|gov%.3f", over) } }
    }

    /// The pair's touch distance for the walk destination, STABLE (2026-11-04): the live support reach swings 0.39 ... 1.6 m while the legs step, so a destination derived from it every tick jumps and the pair
    /// chases itself. Captured along the stance axis `u` (partner -> destination) at a STANDING moment (both planted: `ContactField.touchDistance(_:_:dir:)` of the standing profiles); until such a moment the
    /// value is a hard low-pass of the live one (first sample clamped to a plausible 0.6 ... 1.5 m, then an EMA with a rate clamp). Kept per (walker, partner) in `ContactTouchMemory`, reset per session / phase,
    /// and re-captured when the axis turns by more than 25 degrees (front-to-front touches closer than side-by-side).
    func contactStableTouch(_ p: BlobBrain, axis u: SIMD2<Float>) -> Float? {
        guard let s = social, let raw = stanceTouch(p, axis: u, facing: ContactStance.entry(s.kind)?.facing ?? .toward) else { return nil }
        let key = steerID &* 4096 &+ p.steerID
        let sid = ObjectIdentifier(s)
        func planted(_ b: BlobBrain) -> Bool { !b.gait.isBusy && !b.flapHop.active && !b.airBothFeet && !b.feet.active }
        var e = ContactTouchMemory.store[key]
        if let x = e, x.session != sid || s.t < x.seenT - 0.05 || x.phase != s.phase || simd_dot(x.axis, u) < 0.906 { e = nil }          // (s.t running backwards = a new session at a recycled address)
        if var x = e {
            if !x.frozen {
                if planted(self), planted(p) { x.d = raw; x.frozen = true }
                else { x.d = max(x.d0 - 0.12, min(x.d0 + 0.12, x.d + max(-0.01, min(0.01, (raw - x.d) * 0.1)))) }
            }
            x.seenT = s.t
            ContactTouchMemory.store[key] = x
            return x.d
        }
        let standing = planted(self) && planted(p)
        let d0 = standing ? raw : max(0.6, min(1.5, raw))
        let x = ContactTouchMemory.Entry(session: sid, phase: s.phase, axis: u, d: d0, d0: d0, frozen: standing, seenT: s.t)
        ContactTouchMemory.store[key] = x
        return x.d
    }

    /// The touch distance on the stance's OWN yaws (`ContactStance.Facing`), from the profiles of the bodies as they stand now: a body's support toward a world direction `dir` at the hypothetical heading `hyp` is the
    /// profile's support at `rotXZ(rotXZ(dir, -hyp), yaw)` (the same local direction in the pose it has now). `u` runs from the partner to me.
    func stanceTouch(_ p: BlobBrain, axis u: SIMD2<Float>, facing: ContactStance.Facing) -> Float? {
        func head(_ v: SIMD2<Float>) -> Float { atan2f(v.x, v.y) }
        let cam = faceCameraYaw()
        let hm: Float, hp: Float
        switch facing {
        case .toward: hm = head(-u); hp = head(u)
        case .camera: hm = cam; hp = cam
        case .away: hm = head(u); hp = head(-u)
        }
        func ext(_ b: BlobBrain, _ dir: SIMD2<Float>, _ hyp: Float) -> Float? { ContactField.supportExt(b.steerID, rotXZ(rotXZ(dir, -hyp), b.yaw)) }
        guard simd_distance(ContactField.root(steerID), position) < 0.05, simd_distance(ContactField.root(p.steerID), p.position) < 0.05 else { return nil }          // (a profile of an older pose - the first tick of a session - says nothing about the yaw used here)
        guard let a = ext(self, -u, hm), let c = ext(p, u, hp) else { return nil }
        return a + c
    }

    /// The body is turning to the heading the stance wants (the drive's hold / face yaw), or a turn step is running.
    var contactTurning: Bool {
        if feet.active, abs(stepYawD) > 0.05 { return true }
        if socialBook.hold, let fy = socialBook.faceYaw, abs(wrapAngle(fy - yaw)) > 0.2 { return true }
        return false
    }

    /// A turn step inside a touching stance's own HOLD (a real, non-keep-apart step, no explicit parting): the turn belongs to the stance (nuzzle turns to the camera at the touch, the retarget turns back toward the partner ...).
    /// A parting retreat there backs the body off a full 36 cm each turn and the pair never rests; the settle takes the swing.
    var contactStanceTurnInPlace: Bool {
        guard ContactField.enabled, socialBook.partFrom < 0 || peerClock >= socialBook.partUntil, let s = social, s.end == nil, let st = ContactStance.entry(s.kind), st.cls == .touching,
              let step = st.step(at: s.phase), step.target != nil, !step.onlySeparate else { return false }
        return true
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
        if case .walk = script {} else { ContactTouchMemory.shuffling.remove(steerID) }
        slotWalk = false
        if retarget, !ContactTouchMemory.shuffling.contains(steerID), case .walk(let t, let then) = script, simd_distance(t, p.position) < 3.2 {
            var u = t - p.position; let L = simd_length(u)
            if L > 0.3 {
                u /= L
                var want: SIMD2<Float>, dist: Float, stable: Float?
                if case .walk(let tp, _) = p.script, let ses = social, p.social === ses {
                    // BOTH walk toward each other: each retargeting to "the partner's current spot + the touch distance" chases a moving spot and the pair overshoots into each other. The meeting point is
                    // fixed once per phase from the two drive destinations, and each takes half of the touch distance on its side of it (symmetric: neither target depends on the other's rewrite).
                    let key = min(steerID, p.steerID) &* 4096 &+ max(steerID, p.steerID), lo = steerID < p.steerID
                    let sid = ObjectIdentifier(ses), ph = ses.phase
                    var m = ContactTouchMemory.meet[key]
                    if m == nil || m!.session != sid || m!.phase != ph || ses.t < m!.seenT - 0.05 {
                        let tLo = lo ? t : tp, tHi = lo ? tp : t
                        let ax = simd_normalize(tHi - tLo + SIMD2(1e-6, 0))
                        m = ContactTouchMemory.Meet(session: sid, phase: ph, mid: (tLo + tHi) / 2, axis: ax, seenT: ses.t)
                        ContactTouchMemory.meet[key] = m
                    }
                    m!.seenT = ses.t; ContactTouchMemory.meet[key] = m
                    let side: SIMD2<Float> = lo ? -m!.axis : m!.axis          // from the meeting point toward my side
                    stable = contactStableTouch(p, axis: side)
                    dist = (stable ?? 1.405) + max(gapWanted, ContactStance.arrive) + ContactStance.walkShort
                    want = fixed(m!.mid + side * (dist / 2))
                    if ContactTrace.on { ContactTrace.mod(steerID) { $0.tgt += "|meet" } }
                    let okFix = simd_distance(want, m!.mid + side * (dist / 2)) < 0.25
                    want = noTurnAround(want, was: t, partner: p)
                    let dT = simd_distance(want, t)
                    if okFix, dT > 0.01, dT < 1.2 { script = .walk(target: want, then: then) }
                    slotWalk = okFix
                } else {
                    stable = contactStableTouch(p, axis: u)
                    dist = (stable ?? 1.405) + max(gapWanted, ContactStance.arrive) + ContactStance.walkShort
                    want = fixed(p.position + u * dist)
                    let okFix = simd_distance(want, p.position + u * dist) < 0.25
                    want = noTurnAround(want, was: t, partner: p)
                    let dT = simd_distance(want, t)
                    if ContactTrace.on { ContactTrace.mod(steerID) { $0.tgt += String(format: "|stable%@", stable.map { String(format: "%.3f", $0) } ?? "nil") } }
                    slotWalk = okFix && !ContactTouchMemory.shuffling.contains(steerID)
                    if okFix, dT > 0.01, dT < 1.2 { script = .walk(target: want, then: then); if ContactTrace.on { ContactTrace.mod(steerID) { $0.walk = String(format: "fired(d%.3f,dist%.3f)", dT, dist) } } }
                    else if ContactTrace.on { ContactTrace.mod(steerID) { $0.walk = String(format: "skip(fixOK%d,dT%.3f,dist%.3f,want(%.2f,%.2f),fixed(%.2f,%.2f),partner(%.2f,%.2f))", okFix ? 1 : 0, dT, dist, (p.position + u * dist).x, (p.position + u * dist).y, fixed(p.position + u * dist).x, fixed(p.position + u * dist).y, p.position.x, p.position.y) } }
                }
            }
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
    struct Entry { var session: ObjectIdentifier; var phase: Int; var axis: SIMD2<Float>; var d: Float; var d0: Float; var frozen: Bool; var seenT: Float = 0 }
    /// Bodies whose current walk IS a shuffle step (aimed by the residual, not to be retargeted to the stance spot).
    static var shuffling: Set<Int> = []
    static var store: [Int: Entry] = [:]
    /// Two walkers heading for each other: their meeting point and axis (lower steerID -> higher), fixed once per session phase.
    struct Meet { var session: ObjectIdentifier; var phase: Int; var mid: SIMD2<Float>; var axis: SIMD2<Float>; var seenT: Float = 0 }
    static var meet: [Int: Meet] = [:]
    /// The last pair gap the lunge governor saw, per (body, partner).
    static var govGap: [Int: Float] = [:]
}
