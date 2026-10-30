//
//  BlobBrain+WakeUps.swift
//  Wake-ups that vary (user 2026-10-30: "add wake up animations that vary, make them get up differently too, in sync"). Two choices per wake:
//    GET-UP (stage 4, off his back):  pop (the 0.5 s roll-up), rock-a-bye (rocks, then pops), side roll, slow sit-up (groggy), spring up (lively)
//    FLOURISH (stage 5, standing):    big stretch (+ yawn when groggy), shake off, blinky look-around (groggy), happy bounce (lively), signature
//  The signature follows the BODY's feature, not the name: wings stretch and flutter, the dino tail thumps twice, the daisy has a sun stretch.
//  Every get-up ends at k = 0 in the same standing pose, so `sleepStand` and the stretch hand-off are the same for all of them.
//
//  IN SYNC: a group wake (wakeAll, the chime, the morning) gives each sleeper a DIFFERENT get-up and flourish and one shared length for each stage
//  (`groupWakePlans`): they start on the same tick, land on the same frame and finish together. A style is time-warped to the shared length (a short
//  one waits a beat with a stir on his back first rather than crawl).
//  Fast wakes (a race, a meal) and Reduce Motion keep the plain pop + stretch. Nothing here is saved: the last pair lives in the brain only.
//

import Foundation
import simd

enum GetUp: Int, CaseIterable, Sendable { case pop, rock, side, sit, spring }
enum WakeFlourish: Int, CaseIterable, Sendable { case stretch, shake, look, bounce, signature }
struct WakePair: Equatable { var up: GetUp; var flo: WakeFlourish }

/// One wake as decided: the styles, the shared lengths of a group (0 = the style's own) and the side to roll to.
struct WakePlan {
    var up: GetUp = .pop
    var flo: WakeFlourish = .stretch
    var upLen: Float = 0
    var floLen: Float = 0
    var side: Float = 1
    var chosen = false
}

/// What the get-up adds to the lying pose this tick (`applyLie`): all neutral = today's roll-up.
struct WakeLie {
    var k: Float = 1                 // fraction of the lie he is still in (times kStart)
    var yRoll: Float = 0             // roll onto his side (rad, about his own long axis; + = toward his right)
    var lift: Float = 0              // the anchor's lift (the spring up / the happy hops)
    var sq: Float = 1
    var pitch: Float = 0             // extra nod (+ = forward)
    var eyeMul: Float = 1
}

enum WakeTuning {
    static let popLen: Float = SleepTuning.rollBackTime, rockLen: Float = 1.3, sideLen: Float = 1.2, sitLen: Float = 2.0, springLen: Float = 0.9
    static let shakeLen: Float = 1.3, lookLen: Float = 2.4, bounceLen: Float = 1.3, wingsLen: Float = 1.9, thumpLen: Float = 1.9, sunLen: Float = 1.9
    /// A get-up stretches at most this far before it waits with a stir; a flourish warps within this range.
    static let upStretch: Float = 1.25
    static let floRange: ClosedRange<Float> = 0.62...1.3
    /// A group's shared length: the geometric middle of its styles, but never below the longest over this (nobody crawls and nobody is rushed past ~0.6x).
    static let groupSpan: Float = 1.6
    static let sideRoll: Float = 0.85
    static let springApex: Float = 0.22, hopApex: Float = 0.12
    /// Forced styles for the captures / tests (DEBUG launch arguments -WakeGetUp n, -WakeFlourish n; nil = the draw).
    nonisolated(unsafe) static var forceUp: GetUp?
    nonisolated(unsafe) static var forceFlo: WakeFlourish?
    nonisolated(unsafe) static var debugLoaded = false
    /// DEBUG `-WakeSeed n`: the group's draw is made from this seed (a different draw per clip); 0 = the brain's own.
    nonisolated(unsafe) static var seed: UInt64 = 0

    static func loadDebug() {
        #if DEBUG
        guard !debugLoaded else { return }
        debugLoaded = true
        let d = UserDefaults.standard
        if d.object(forKey: "WakeGetUp") != nil, let u = GetUp(rawValue: d.integer(forKey: "WakeGetUp")) { forceUp = u }
        if d.object(forKey: "WakeFlourish") != nil, let f = WakeFlourish(rawValue: d.integer(forKey: "WakeFlourish")) { forceFlo = f }
        seed = UInt64(max(0, d.integer(forKey: "WakeSeed")))
        #endif
    }

    static func upLen(_ u: GetUp) -> Float {
        switch u { case .pop: return popLen; case .rock: return rockLen; case .side: return sideLen; case .sit: return sitLen; case .spring: return springLen }
    }
    static func floLen(_ f: WakeFlourish, groggy: Bool, feature: JellyFeature) -> Float {
        switch f {
        case .stretch: return SleepTuning.stretchTime * (groggy ? 1.5 : 1)
        case .shake: return shakeLen
        case .look: return lookLen
        case .bounce: return bounceLen
        case .signature: return feature == .wings ? wingsLen : (feature == .spines ? thumpLen : sunLen)
        }
    }
    /// The shared length of a group: from the styles' own lengths.
    static func sharedLen(_ lens: [Float]) -> Float {
        guard let lo = lens.min(), let hi = lens.max() else { return 0 }
        return max((lo * hi).squareRoot(), hi / groupSpan)
    }
    /// A get-up's timing: when it lands, its time-warp, and the seconds of stir on his back before it starts.
    static func upTiming(_ plan: WakePlan) -> (end: Float, scale: Float, lead: Float) {
        let nat = upLen(plan.up)
        guard plan.upLen > 0 else { return (nat, 1, 0) }
        if plan.upLen > nat * upStretch { return (plan.upLen, upStretch, plan.upLen - nat * upStretch) }
        return (plan.upLen, plan.upLen / nat, 0)
    }
    static func floTiming(_ plan: WakePlan, groggy: Bool, feature: JellyFeature) -> (end: Float, scale: Float) {
        let nat = floLen(plan.flo, groggy: groggy, feature: feature)
        guard plan.floLen > 0 else { return (nat, 1) }
        return (plan.floLen, max(floRange.lowerBound, min(floRange.upperBound, plan.floLen / nat)))
    }

    /// The get-up curve at natural time `lt` (seconds of the style's own length; negative = still stirring).
    static func getUp(_ up: GetUp, lt: Float, side: Float) -> WakeLie {
        var w = WakeLie()
        let lt = max(lt, 0)
        switch up {
        case .pop:
            // ease-out: the roll-up pops up fast, then settles onto his feet; a taller body for a beat as he comes up
            let x = min(lt / popLen, 1)
            w.k = (1 - x) * (1 - x)
            if x > 0.5 { w.sq = 1 + 0.07 * sinf(.pi * min((x - 0.5) / 0.5, 1)) }
        case .rock:
            // two rocks back and forth (k dips to 0.85, then 0.7, back to 1 each time, a small side tilt with them), the third swing carries him all the way up
            if lt < 0.4 {
                let d = sinf(.pi * lt / 0.4)
                w.k = 1 - 0.15 * d; w.yRoll = side * 0.10 * d
            } else if lt < 0.85 {
                let d = sinf(.pi * (lt - 0.4) / 0.45)
                w.k = 1 - 0.30 * d; w.yRoll = side * 0.16 * d
            } else {
                let x = min((lt - 0.85) / (rockLen - 0.85), 1)
                w.k = 1 - (0.65 * smooth01(x) + 0.35 * (1 - (1 - x) * (1 - x)))
                w.yRoll = side * 0.08 * sinf(.pi * x)
                if x > 0.45 { w.sq = 1 + 0.06 * sinf(.pi * min((x - 0.45) / 0.55, 1)) }
            }
        case .side:
            // onto his side (away from a neighbour), a beat, then pushes up
            let e = smooth01(lt / 0.5)
            if lt < 0.62 {
                w.k = 1 - 0.4 * e; w.yRoll = side * sideRoll * e
            } else {
                let u = min((lt - 0.62) / (sideLen - 0.62), 1)
                w.k = 0.6 * (1 - u) * (1 - u)
                w.yRoll = side * sideRoll * (1 - smooth01(u))
                if u > 0.5 { w.sq = 1 + 0.04 * sinf(.pi * min((u - 0.5) / 0.5, 1)) }
            }
        case .sit:
            // up to a sleepy sit-up: a slow nod and one slow blink there, then the rest of the way up
            if lt < 0.7 {
                w.k = 1 - 0.55 * smooth01(lt / 0.7)
            } else if lt < 1.5 {
                w.k = 0.45
                let h = lt - 0.7
                w.pitch = 0.07 * sinf(.pi * h / 0.8) - 0.03 * sinf(.pi * h / 0.4)
                if lt > 1.0 && lt < 1.4 { w.eyeMul = 1 - 0.8 * sinf(.pi * (lt - 1.0) / 0.4) }
            } else {
                w.k = 0.45 * (1 - smooth01((lt - 1.5) / (sitLen - 1.5)))
            }
        case .spring:
            // a quick squash on his back, then he launches: upright in about 0.3 s, a small hop (apex ~0.22), down onto his feet at the end
            if lt < 0.45 {
                w.sq = 1 - 0.15 * smooth01(lt / 0.35)
            } else {
                let u = min((lt - 0.45) / (springLen - 0.45), 1)
                let v = min(u / 0.67, 1)
                w.k = (1 - v) * (1 - v)
                w.lift = springApex * 4 * u * (1 - u)
                w.sq = (1 - 0.15 * (1 - smooth01(u / 0.3))) + 0.05 * sinf(.pi * u) * smooth01(u / 0.3)
            }
        }
        return w
    }

    /// The landing: the squish (fraction of the squash), the jelly kick.
    static func landing(_ up: GetUp) -> (dip: Float, kick: Float) {
        switch up {
        case .pop: return (0, SleepTuning.wakeKick)
        case .rock: return (0.10, 2.0)
        case .side: return (0.08, 1.4)
        case .sit: return (0, 1.0)
        case .spring: return (0.14, 2.4)
        }
    }
}

extension BlobBrain {
    // MARK: choosing

    /// Reduce Motion: only the pop and the stretch.
    private var wakeCalm: Bool { A11ySettings.shared.reduceMotion || amplitude < 0.7 }

    /// The get-ups / flourishes this body may do now.
    func wakeUpChoices(groggy: Bool) -> [GetUp] {
        if wakeCalm { return [.pop] }
        var c: [GetUp] = groggy ? [.pop, .side, .sit] : [.pop, .rock, .side, .spring]
        if sleep.bed >= 0 { c.removeAll { $0 == .side || $0 == .spring } }          // in a pet bed: in place only
        return c
    }
    func wakeFlourishChoices(groggy: Bool) -> [WakeFlourish] {
        if wakeCalm { return [.stretch] }
        var c: [WakeFlourish] = groggy ? [.stretch, .shake, .look] : [.stretch, .shake, .bounce]
        if sleep.bed >= 0 { c.removeAll { $0 == .bounce } }
        if wakeSignatureOK { c.append(.signature) }
        return c
    }
    /// The body has a feature to show off (a back item that folds the wings gives no wing stretch).
    var wakeSignatureOK: Bool { feature == .spines || feature == .daisy || (feature == .wings && !wingsFolded) }

    /// One wake of his own (a poke, a name, the hold running out): random from the right sets, never the pair he did last.
    func chooseWakePlan(groggy: Bool) -> WakePlan {
        WakeTuning.loadDebug()
        var p = WakePlan()
        p.chosen = true
        let ups = wakeUpChoices(groggy: groggy), flos = wakeFlourishChoices(groggy: groggy)
        for _ in 0..<12 {
            p.up = ups[Int(rand() * Float(ups.count)) % ups.count]
            p.flo = flos[Int(rand() * Float(flos.count)) % flos.count]
            if wakeLast != WakePair(up: p.up, flo: p.flo) { break }
        }
        if let u = WakeTuning.forceUp { p.up = u }
        if let f = WakeTuning.forceFlo { p.flo = f }
        p.side = wakeRollSide()
        return p
    }

    /// DEBUG log of the pair a solo wake will be forced to (nil forces = the draw is made at the wake).
    func chooseWakePlanPreview() -> String { "\(WakeTuning.forceUp.map { "\($0)" } ?? "random")/\(WakeTuning.forceFlo.map { "\($0)" } ?? "random")" }

    /// A group wake: different get-ups and different flourishes (as far as the sets reach), one shared landing and one shared finish.
    static func groupWakePlans(_ bs: [BlobBrain], groggy: Bool) -> [WakePlan] {
        guard let lead = bs.first else { return [] }
        WakeTuning.loadDebug()
        if WakeTuning.seed != 0 { lead.seed = WakeTuning.seed &* 2654435761 }
        var plans: [WakePlan] = []
        for _ in 0..<24 {
            plans = []
            var okAll = true
            var usedU = Set<GetUp>(), usedF = Set<WakeFlourish>()
            for b in bs {
                var ups = b.wakeUpChoices(groggy: groggy), flos = b.wakeFlourishChoices(groggy: groggy)
                if ups.contains(where: { !usedU.contains($0) }) { ups.removeAll { usedU.contains($0) } } else { okAll = okAll && ups.count == 1 }
                if flos.contains(where: { !usedF.contains($0) }) { flos.removeAll { usedF.contains($0) } } else { okAll = okAll && flos.count == 1 }
                var p = WakePlan(); p.chosen = true
                p.up = ups[Int(lead.rand() * Float(ups.count)) % ups.count]
                p.flo = flos[Int(lead.rand() * Float(flos.count)) % flos.count]
                usedU.insert(p.up); usedF.insert(p.flo)
                if b.wakeLast == WakePair(up: p.up, flo: p.flo) { okAll = false }
                plans.append(p)
            }
            if okAll { break }
        }
        if let u = WakeTuning.forceUp { for i in plans.indices { plans[i].up = u } }
        if let f = WakeTuning.forceFlo { for i in plans.indices { plans[i].flo = f } }
        let upL = WakeTuning.sharedLen(plans.map { WakeTuning.upLen($0.up) })
        for (i, b) in bs.enumerated() {
            plans[i].upLen = upL
            plans[i].floLen = WakeTuning.sharedLen(zip(bs, plans).map { WakeTuning.floLen($1.flo, groggy: groggy, feature: $0.feature) })
            plans[i].side = b.wakeRollSide()
        }
        return plans
    }

    /// Which way the side roll goes: away from the nearest sleepers (the roll is toward his right for +1), open floor = either.
    func wakeRollSide() -> Float {
        let right = SIMD2(cosf(yaw), -sinf(yaw))
        var s: Float = 0
        for o in socialOthers() where o !== self && simd_distance(o.position, position) < 3.2 {
            let d = o.position - position, len = max(simd_length(d), 0.3)
            s += simd_dot(d, right) / (len * len)
        }
        if abs(s) < 0.02 { return rand() < 0.5 ? -1 : 1 }
        return s > 0 ? -1 : 1
    }

    /// The get-up begins (stage 4 entered from any road): the plan in hand (a group's), the plain pop + stretch (`plain`: a fast wake, or he is still mid-flop),
    /// or a draw of his own.
    func wakePlanBegin(plain: Bool) {
        if !sleep.plan.chosen {
            if plain { sleep.plan = WakePlan(); sleep.plan.chosen = true } else { sleep.plan = chooseWakePlan(groggy: sleep.groggy) }
        }
        wakeLast = WakePair(up: sleep.plan.up, flo: sleep.plan.flo)
        sleep.x = WakeLie()
        #if DEBUG
        NSLog("[wake] brain %d: %@ / %@ (group length %.2f / %.2f)", steerID, "\(sleep.plan.up)", "\(sleep.plan.flo)", sleep.plan.upLen, sleep.plan.floLen)
        #endif
    }

    /// The morning wake is due for this bedtime sleeper (the room wakes the sleepers together; the same rule stands in `sleepBodyTick` for a brain with no room).
    var sleepMorningDue: Bool {
        isNapping && idleDeepNight < 0.5 && idleNight < SleepTuning.nightEdge && sleep.t >= sleep.minHold && sleep.hold > 600
    }

    // MARK: the flourishes (stage 5)

    /// True while the happy hops own the body (sleepBodyTick drives them, like the get-up).
    var wakeBodyOn: Bool { idleState.kind == .sleep && sleep.stage == 5 && sleep.plan.flo == .bounce && !sleep.bounceDone }

    /// The wet-dog shake (the same numbers as `runShake`) at natural time `t`.
    private func wakeShakePose(_ t: Float) {
        if idleState.phase == 0 {
            idleState.phase = 1
            AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.6)
            face(.joyArc, hold: 1.3)
        }
        let crouch = smooth01(t / 0.15) * (1 - smooth01((t - 1.1) / 0.2))
        squash *= 1 - 0.06 * crouch
        if t > 0.15 {
            let s = t - 0.15
            let env = max(0, sinf(.pi * min(1.0, s)))
            twist = 0.26 * env * sinf(2 * .pi * 7.5 * s)
            roll += 0.05 * env * sinf(2 * .pi * 7.5 * s + 0.6)
            squash *= 1 - 0.05 * env * (0.5 - 0.5 * cosf(2 * .pi * 15 * s))
        }
        armWalkWant = 1
        if idleState.phase == 1, t > 1.15 { idleState.phase = 2; jellyKick = max(jellyKick, 2.4) }
    }

    /// Two slow blinks, left then right, then a small smile.
    private func wakeLookPose(_ skinner: Skinner, _ t: Float) {
        func blink(_ a: Float, _ b: Float) -> Float { t > a && t < b ? sinf(.pi * (t - a) / (b - a)) : 0 }
        let droop = 0.35 * smooth01(t / 0.15) * (1 - smooth01((t - 0.6) / 0.8))
        let eyes = (1 - droop) * (1 - 0.93 * max(blink(0.2, 0.65), blink(0.8, 1.2)))
        let left = smooth01((t - 1.05) / 0.3) * (1 - smooth01((t - 1.45) / 0.3))
        let right = smooth01((t - 1.6) / 0.3) * (1 - smooth01((t - 2.05) / 0.3))
        twist = 0.5 * (right - left)
        pitch += 0.02 * (left + right)
        armWalkWant = 1
        if t > 1.95 {
            if idleState.phase == 0 { idleState.phase = 1; sleep.faceFree = true; face(.happy, hold: 1.2) }
        } else {
            skinner.setEyeOpenness(max(0.05, eyes))
        }
    }

    /// Signature: the wings stretch wide and flutter; the tail thumps twice; the daisy has a sun stretch.
    private func wakeSignaturePose(_ skinner: Skinner, _ t: Float, _ dt: Float) {
        switch feature {
        case .wings:
            if idleState.phase == 0 { idleState.phase = 1; face(.happy, hold: 1.8); AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.4) }
            let sc = max(0, min(1, wingFlapMax / 75))
            let open = smooth01(t / 0.45) * (1 - smooth01((t - 1.55) / 0.35))
            var flap = 45 * open
            if t > 0.75 && t < 1.55 { flap += 22 * sinf(2 * .pi * 8 * (t - 0.75)) * sinf(.pi * (t - 0.75) / 0.8) }
            flapHop.flapDeg = flap * sc
            flapHop.spreadDeg = max(75 * open * sc, 0.4 * max(flap * sc, 0))          // (FeatureSet clamps both to what the worn items allow)
            pitch += 0.08 * open
            twist = -1.0 * smooth01(t / 0.4) * (1 - smooth01((t - 1.5) / 0.35))          // a turn to show the wings from the side (they lie on his back)
            squash *= 1 + 0.05 * open
            armWalkWant = 1
        case .spines:
            if idleState.phase == 0 { idleState.phase = 1; face(.excited, hold: 1.9) }
            let start: Float = 0.25, cyc = Self.thumpCycle
            let ct = t - start
            var lift: Float = 0, tip: Float = 0
            if ct >= 0 {
                let idx = Int(ct / cyc)
                if idx < 2 {
                    let l = ct - Float(idx) * cyc
                    if l < Self.thumpRaise {
                        let u = smooth01(l / Self.thumpRaise); lift = Self.thumpLiftDeg * u; tip = 12 * u
                    } else if l < Self.thumpRaise + Self.thumpDrop {
                        let u = (l - Self.thumpRaise) / Self.thumpDrop; lift = Self.thumpLiftDeg * (1 - u * u); tip = 12 * (1 - u)
                    } else if tailPlay.thumpsDone <= idx {
                        tailPlay.thumpsDone = idx + 1; tailPlay.impactT = 0
                        AudioHub.shared.play(.footstep, jelly: steerID, x: px, volume: 0.85)
                        jellyKick = max(jellyKick, 0.9)
                    }
                }
            } else {
                squash *= 1 - 0.03 * smooth01(t / start)
            }
            twist = 0.6 * smooth01(t / 0.3) * (1 - smooth01((t - 1.5) / 0.35))          // a turn to show the tail to the room
            tailPlay.lift = lift; tailPlay.liftTip = tip
            tailPlay.impactT += dt
            squash *= 1 - 0.035 * max(0, 1 - tailPlay.impactT / 0.18)
            armWalkWant = 1
        default:
            // the sun stretch: tips back with the face up, arms up, eyes closed and smiling (the daisy rides the body)
            if idleState.phase == 0 { idleState.phase = 1; face(.joyArc, hold: 1.9) }
            let env = smooth01(t / 0.5) * (1 - smooth01((t - 1.3) / 0.5))
            pitch -= 0.30 * env
            squash *= 1 + 0.10 * env
            armWalkWant = 1
            armDirW = env
            armDirEl = [0.95, 0.95]; armDirSa = [0.12, 0.12]; armDirOut = 0.07
        }
    }

    /// The happy hops on the spot, body-led (the get-up's machinery: the anchor lifts, the rigid feet ride along): 2 small hops, natural time `t`.
    func wakeBounceX(_ t: Float) -> WakeLie {
        var w = WakeLie()
        func hop(_ a: Float, _ b: Float) -> Float { t > a && t < b ? sinf(.pi * (t - a) / (b - a)) : 0 }
        w.lift = WakeTuning.hopApex * (hop(0.2, 0.6) + hop(0.7, 1.1))
        let crouch = smooth01(t / 0.15) * (1 - smooth01((t - 0.2) / 0.06)) + smooth01((t - 0.6) / 0.05) * (1 - smooth01((t - 0.7) / 0.06))
        let air = hop(0.2, 0.6) + hop(0.7, 1.1)
        var dip: Float = 0
        for land in [Float(0.6), 1.1] where t >= land { dip = max(dip, expf(-(t - land) / 0.08)) }
        w.sq = 1 - 0.07 * crouch + 0.04 * air - 0.08 * dip
        return w
    }

    /// Stage 5 of the happy bounce, called from `sleepBodyTick`. True = this tick's body is handled (false = the hops are over, the normal path takes him).
    func wakeBounceTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        let scale = WakeTuning.floTiming(sleep.plan, groggy: sleep.groggy, feature: feature).scale
        let t = sleep.t / scale
        if idleState.phase == 0 { idleState.phase = 1; sleep.faceFree = true; face(.happy, hold: 1.4) }
        if t >= WakeTuning.bounceLen - 0.2 {
            sleep.bounceDone = true; sleep.x = WakeLie()
            feetInit = false; feet.reset(); stepLive = false; walkFinal = false
            return false
        }
        let prev = sleep.wakeHopT
        func crossed(_ x: Float) -> Bool { prev < x && t >= x }
        if crossed(0.2) || crossed(0.7) { AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.4) }
        if crossed(0.6) { jellyKick = max(jellyKick, 1.2); AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.4) }
        if crossed(1.1) { jellyKick = max(jellyKick, 1.4); AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.5) }
        sleep.wakeHopT = t
        sleep.x = wakeBounceX(t)
        return true
    }

    /// The flourish's pose in the normal stand path (stage 5), after the get-up's landing squish.
    func wakeFlourishPose(_ skinner: Skinner, _ t: Float, _ dt: Float) {
        switch sleep.plan.flo {
        case .shake: wakeShakePose(t)
        case .look: wakeLookPose(skinner, t)
        case .signature: wakeSignaturePose(skinner, t, dt)
        default: break
        }
    }

    /// The stage ends: nothing of the flourish stays on him.
    func wakeFlourishEnd() {
        flapHop.flapDeg = 0; flapHop.spreadDeg = 0
        twist = 0
        sleep.faceFree = false
    }

    /// Wings follow the wake's stretch while it plays (FeatureSet reads this like the flap-hop).
    var wakeWingsOn: Bool { idleState.kind == .sleep && sleep.stage == 5 && sleep.plan.flo == .signature && feature == .wings }
    /// The tail follows the wake's thumps while they play (TailPlay's easing must not undo them).
    var wakeThumpOn: Bool { idleState.kind == .sleep && sleep.stage == 5 && sleep.plan.flo == .signature && feature == .spines }
}
