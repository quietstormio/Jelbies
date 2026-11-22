//
//  MoveMix.swift
//  move-mix-r1 (movement plan, first BEHAVIOUR change; the owner 2026-11-21: "full floor wandering with occasional group emotes ... less standing around and bumping into each other",
//  "like a roaming pet in a tank or room"): pets ROAM, emotes are moments. ONE master switch (`MoveMix.on`, default ON; `-MoveMix 0` in a DevArgs build or env MOVEMIX_OFF=1 = exactly the old
//  behaviour) and EVERY constant of the change lives here. Home room and park.
//   1. A stroll after every pair / group emote: each member walks a real roam leg to a stale part of the floor, fanning out (never off side by side).
//   2. No chaining: after a pair emote nothing social for that body for `quiet` s, the same two do not pair again for `pairAgain` s, a partner starts at least `pairMinDist` away.
//   3. Group emotes are occasional: `groupCool` after one, and the company time needed before one doubles.
//   4. Walking between things: after a solo emote the next pick is a leg `legAfterSolo` of the time; legs >= `legMin`, goals prefer stale floor; no two in-place picks in a row.
//   5. No emote under the HUD buttons: stopping spots (solo, pair, group, strolls, roam goals) are clear of the rails (`RoamFloor.stopFree`); walking THROUGH under them stays allowed.
//

import Foundation
import simd

nonisolated enum MoveMix {
    private static func flag() -> Bool {
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: "MoveMix") else { return true }
        return !["0", "no", "false", "old", "off"].contains(v.lowercased())
    }
    nonisolated(unsafe) static var on: Bool = flag() && ProcessInfo.processInfo.environment["MOVEMIX_OFF"] == nil

    // 1. stroll
    /// A stroll leg after a pair / group emote (u), the pause before it (s), how long it stays due (s).
    static let strollLeg: ClosedRange<Float> = 2.5...4.5
    static let strollWait: ClosedRange<Float> = 0.35...0.9, strollDue: Float = 8
    /// The stroll heads away from the others of the session: within this angle (rad) of "outward"; two strollers' headings differ by at least `strollSplit` (cos).
    static let strollOutward: Float = 1.2, strollSplitCos: Float = 0.35
    // 2. no chaining
    static let quiet: ClosedRange<Float> = 10...16
    static let pairAgain: ClosedRange<Float> = 30...45
    static let pairMinDist: Float = 1.4
    static let watchPairMul: Float = 1.5          // was SocialTuning.livelyChance 4.0
    // 3. group
    static let groupCoolHome: ClosedRange<Float> = 170...230          // (round 2: one group moment of any kind per ~3 min at home; treats share this clock)
    static let groupCoolParkMul: Float = 0.5
    static let groupWaitMul: Float = 2
    // 4. walking
    static let legAfterSolo: Float = 0.7
    /// The wait before the next solo special (idleEnd) is this much longer: legs and calm standing fit between solos.
    static let soloGapMul: Float = 3.4
    static let legMin: Float = 2.5
    static let windowGap: Float = 90
    /// Longest roam leg (was 5.5; 3.4 grumpy): a stale far cell is reachable in one leg.
    nonisolated(unsafe) static var legMax: Float = ProcessInfo.processInfo.environment["MOVEMIX_LEGMAX"].flatMap { Float($0) } ?? 8.0
    static let legMaxGrumpy: Float = 5.5
    static let idleWeight: Float = 6.0          // x (blend of the shared and the body's own idleness) / 60 in a roam goal's score
    /// Round 2: each body also keeps its OWN 6 x 6 "seconds since I was last here"; the goal score blends it with the shared board map (this much own).
    static let ownShare: Float = 0.7
    static let thirdWeight: Float = 12, thirdWindow: Float = 180
    /// Rug-centre penalty of EmoteSpot.score (was 2.2): pair / group spots lean away from the centre.
    static let rugWeight: Float = 3.4
    /// A stroll goal in another depth third than where the body stands / where its mates strolled to.
    static let strollThirdBonus: Float = 1.2
    static let roamCandidates = 8          // (was 6 valid candidates)
    static let claimRadius: Float = 1.1
    /// Dev (round 2b, finding what empties the front): `-MixStopOff 1` = stopOK always true; `-MixPenaltyOff 1` = no under-button goal penalty.
    nonisolated(unsafe) static var stopOff: Bool = DevArgs.enabled && UserDefaults.standard.bool(forKey: "MixStopOff")
    nonisolated(unsafe) static var penaltyOff: Bool = DevArgs.enabled && UserDefaults.standard.bool(forKey: "MixPenaltyOff")
    static var underButtonPenalty: Float { penaltyOff ? 0 : 0.4 }
    /// A pair partner may be this far (was 4.8): the strolls spread them out.
    static let pairMaxDist: Float = 6.5
    /// Night / sleepy: the in-place chain rule and the forced leg off the buttons do not apply.
    static let sleepyNight: Float = 0.4
    // 6. a little more running about (round 2): a share of the long roam / stroll legs is done with the game's own RUN gait (idleStart(.run, goal:)), happy / okay only, less at night
    nonisolated(unsafe) static var runChance: Float = {
        if let v = ProcessInfo.processInfo.environment["MOVEMIX_RUNCHANCE"], let f = Float(v) { return f }
        if DevArgs.enabled, let v = UserDefaults.standard.string(forKey: "MoveMixRun"), let f = Float(v) { return f }
        return 0.3
    }()
    static let runLegMin: Float = 3.5
    static let runShare: Float = 0.68, runTail: Float = 1.3          // the run ends this fraction of the leg in (and at least `runTail` u before the goal); the walk finishes it
    static let runClearance: Float = 1.7          // a run keeps this far from any body that is in an emote (a session, a special) or walking its own leg across
    static let okayRunMul: Float = 0.6
    // 5. buttons: see RoamFloor.stopFree / stopOK
}

/// What a body's last pick was (`BlobBrain.mix.last`).
enum MixLast { case none, leg, inPlace, solo, social }

struct MixBook {
    var last: MixLast = .none
    /// No new social (pair or group) for this body until this game time (`variety.now`).
    var quietUntil: Float = -1
    /// A stroll is due (set when a pair / group emote ends): the others of that session, where they stood, the time it lapses; the heading it took (for the next stroller to differ).
    var strollUntil: Float = -1
    var strollMates: [Int] = []
    var strollFrom = SIMD2<Float>.zero
    var strollDir = SIMD2<Float>.zero
    var strollDirAt: Float = -99
    var strollThird = -1
    var windowUntil: Float = -1
    /// A run covers the first `runShare` of a leg; the rest is walked at the normal blend (afterRun = the real goal), so a run never ends in a stop.
    var afterRun: SIMD2<Float>?
    var afterRunUntil: Float = -1
    /// What kind of leg this body was last sent on (the foot-lift proof logs by it): "roam", "stroll", "out" (from under a button).
    var legKind = "roam"
    /// The body's OWN idleness map: game time it was last in each of the 6 x 6 cells of the live floor (-inf = never).
    var own = [Float](repeating: -.infinity, count: 36)
    /// Round 2b: seconds this body spent in the back / middle / front third of the floor's depth (decaying over ~3 min): the goal score nudges toward the third it has had least.
    var thirdT: [Float] = [1, 1, 1]
}

extension GameCamera.RoamFloor {
    /// True when a body standing at `p` is clear of the HUD button rails (`stopFree`, built whether or not the rails are cut out of the walkable floor). No rails built = everywhere.
    func stopOK(_ p: SIMD2<Float>) -> Bool {
        guard !MoveMix.stopOff, !stopFree.isEmpty, let g = zs.first else { return true }
        let i = min(max(Int(floorf((p.y - g) / Self.step)), 0), zs.count - 1)
        for r in [i, min(i + 1, zs.count - 1)] where r < stopFree.count {
            if !stopFree[r].contains(where: { $0.contains(p.x) }) { return false }
        }
        return true
    }
}

extension BlobBrain {
    func mixStopOK(_ p: SIMD2<Float>) -> Bool {
        guard MoveMix.on, let rf = roamProvider?() else { return true }
        return rf.stopOK(p)
    }
    var mixQuiet: Bool { MoveMix.on && variety.now < mix.quietUntil }
    var mixSleepy: Bool { idleNight >= MoveMix.sleepyNight || idleDeepNight > 0.1 }

    /// A pair / group session of this body just ended (BlobSocial.socialRelease): quiet period, then a stroll away.
    func mixSessionEnded(_ s: SocialSession, hard: Bool) {
        guard MoveMix.on, s.kind != .look, s.kind != .zoomies else { return }
        let now = variety.now
        mix.quietUntil = now + rand(MoveMix.quiet.lowerBound, MoveMix.quiet.upperBound)
        socialBook.cooldown = max(socialBook.cooldown, mix.quietUntil - now)
        guard !hard, s.kind != .greet else { return }
        var mates = [Int]()
        for id in (s.kind.isGroup ? s.crewIDs : [s.idA, s.idB, s.idC]) where id >= 0 && id != steerID && !mates.contains(id) { mates.append(id) }
        guard !mates.isEmpty else { return }
        mix.strollMates = mates
        var c = position, n: Float = 1
        for id in mates { if let o = socialBrain(id) { c += o.position; n += 1 } }
        mix.strollFrom = c / n
        mix.strollUntil = now + MoveMix.strollDue
        if scriptIsNone { restTimer = rand(MoveMix.strollWait.lowerBound, MoveMix.strollWait.upperBound) }
    }

    /// pickAutonomous: a stroll is due -> walk it. True = a leg was started.
    func mixStrollDue(_ sim: SoftBody) -> Bool {
        guard MoveMix.on, mix.strollUntil > 0 else { return false }
        let now = variety.now
        guard now < mix.strollUntil, idleState.kind == nil else { mix.strollUntil = -1; return false }
        guard let g = mixStrollGoal() else {
            if pickTimedOut { restTimer = 0.03; return true }          // (out of pick time, not out of places: stay due, look again in two frames)
            mix.strollUntil = -1; return false
        }
        mix.strollUntil = -1
        let here = position
        let d = g - here
        let len = simd_length(d)
        mix.strollDir = len > 1e-3 ? d / len : .zero; mix.strollDirAt = now
        if let rf = roamProvider?() { mix.strollThird = mixThird(g.y, rf) }
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
        mix.last = .leg; mix.legKind = "stroll"
        if mixTryRun(to: g, sim) { return true }
        script = .walk(target: g, then: .none); activity = .walking
        return true
    }

    /// A stale, free, button-clear spot 2.5...4.5 u away, away from the others of the session and in a different direction from the one who left first.
    func mixStrollGoal() -> SIMD2<Float>? {
        guard let rf = roamProvider?() else { return nil }
        let here = position, now = variety.now
        let mates = mix.strollMates.compactMap { socialBrain($0) }
        let others = socialOthers().filter { $0 !== self }
        var out = here - mix.strollFrom
        out = simd_length(out) > 0.15 ? out / simd_length(out) : SIMD2(sinf(Float(steerID) * 2.1), cosf(Float(steerID) * 2.1))
        for pass in 0..<3 {
            let lo = pass < 2 ? MoveMix.strollLeg.lowerBound : 1.8, hi = pass < 2 ? MoveMix.strollLeg.upperBound : 5.5
            var best: (SIMD2<Float>, Float)?
            for _ in 0..<40 {
                if pickOver { break }
                let raw = rf.sampleArea(rand(), rand(), rand())
                let dr = simd_distance(raw, here)
                guard dr > lo, dr < hi, rf.stopOK(raw), pass > 0 || simd_dot((raw - here) / dr, out) >= cosf(MoveMix.strollOutward) else { continue }          // (the cheap tests first)
                let rv = resolve(SIMD3(raw.x, 0, raw.y), footprint); let cand = SIMD2(rv.x, rv.z)
                let d = simd_distance(cand, here)
                guard simd_length(cand - raw) < 0.15, d > lo, d < hi, rf.stopOK(cand), peerFree(cand), !slideFootPoint(cand), !hopCourtWithin(cand, footprint * HopscotchTuning.wallReach + HopscotchTuning.noRest), reachable(here, cand) else { continue }
                let dir = (cand - here) / d
                if pass == 0, simd_dot(dir, out) < cosf(MoveMix.strollOutward) { continue }
                var split = true
                if pass < 2 { for m in mates where now - m.mix.strollDirAt < 8 && simd_dot(dir, m.mix.strollDir) > MoveMix.strollSplitCos { split = false } }
                guard split else { continue }
                var nearest: Float = 5
                for o in others {
                    nearest = min(nearest, simd_distance(o.position, cand))
                    if case .walk(let t, _) = o.script { nearest = min(nearest, simd_distance(t, cand)) }
                }
                var score = 0.6 * nearest + 0.3 * rand() - roomLegConflict(from: here, to: cand, speed: roomNominalWalk, others: others, dash: false)
                if let b = board, b.claimed(near: cand, radius: MoveMix.claimRadius, except: steerID) { continue }
                score += MoveMix.idleWeight * mixIdleness(cand, rf) / WalkBoard.idleCap
                score += MoveMix.thirdWeight * mixThirdNeed(cand.y, rf)
                let th = mixThird(cand.y, rf)
                if th != mixThird(here.y, rf) { score += MoveMix.strollThirdBonus }
                if mates.contains(where: { now - $0.mix.strollDirAt < 8 && $0.mix.strollThird == th }) { score -= MoveMix.strollThirdBonus }
                if best == nil || score > best!.1 { best = (cand, score) }
            }
            if let b = best { roamVisits[roamKeyMix(b.0), default: 0] += 1; return b.0 }
        }
        return nil
    }
    func roamKeyMix(_ p: SIMD2<Float>) -> Int { (Int(floorf(p.x)) + 50) * 1000 + Int(floorf(p.y)) + 50 }

    /// pickAutonomous, before a social / special is tried: this pick must be a leg (under a button, after an in-place pick, after a solo emote 70 % of the time).
    func mixWantsLeg() -> Bool {
        guard MoveMix.on, !mixSleepy else { return false }
        if !mixStopOK(position) { return true }
        switch mix.last {
        case .inPlace: return true
        case .solo: return rand() < MoveMix.legAfterSolo
        default: return false
        }
    }

    static let inPlaceKinds: Set<IdleKind> = [.sit, .slump, .look, .window, .lieDown, .sigh, .yawn, .stretch, .sway, .flop, .peek, .hmph]
    /// An idle behaviour just started from the scheduler: what kind of pick was it.
    func mixNoteIdle() {
        guard MoveMix.on else { return }
        let k = idleState.kind ?? emoteSpot.soloKind
        mix.last = k.map { Self.inPlaceKinds.contains($0) ? .inPlace : .solo } ?? .solo
    }
}

extension BlobBrain {
    /// 6 x 6 cell of a floor point (the board's grid: the live floor's bounds).
    func mixCell(_ p: SIMD2<Float>, _ rf: GameCamera.RoamFloor) -> Int {
        let b = rf.bounds, n: Float = 6
        let u = min(max((p.x - b.min.x) / max(b.max.x - b.min.x, 0.01), 0), 0.9999), v = min(max((p.y - b.min.y) / max(b.max.y - b.min.y, 0.01), 0), 0.9999)
        return Int(v * n) * 6 + Int(u * n)
    }
    /// Every tick (centreDwellTick): the cell this body is in is "here now".
    func mixOwnTick() {
        guard MoveMix.on, let rf = roamProvider?() else { return }
        mix.own[mixCell(position, rf)] = variety.now
        let cur = mixThird(position.y, rf), k = 1 - 1 / (MoveMix.thirdWindow * 60)          // (one tick = 1/60 s)
        for i in 0..<3 { mix.thirdT[i] = mix.thirdT[i] * k + (i == cur ? 1 / 60 : 0) }
    }
    /// 0...60: the blend of the shared idleness and this body's own for a goal at `p`.
    func mixIdleness(_ p: SIMD2<Float>, _ rf: GameCamera.RoamFloor) -> Float {
        let own = min(WalkBoard.idleCap, max(0, variety.now - mix.own[mixCell(p, rf)]))
        var shared = own
        if let b = board { shared = b.idleness(at: p, now: b.now) }
        return MoveMix.ownShare * own + (1 - MoveMix.ownShare) * shared
    }
    /// 0 back, 1 middle, 2 front third of the floor's depth.
    /// How much less than a third of its recent time this body has spent in the depth third of `z` (positive = under-used).
    func mixThirdNeed(_ z: Float, _ rf: GameCamera.RoamFloor) -> Float {
        let tot = max(mix.thirdT.reduce(0, +), 1e-3)
        return 1.0 / 3.0 - mix.thirdT[mixThird(z, rf)] / tot
    }
    func mixThird(_ z: Float, _ rf: GameCamera.RoamFloor) -> Int { min(2, max(0, Int((z - rf.minZ) / max(rf.maxZ - rf.minZ, 0.1) * 3))) }
}

extension BlobBrain {
    /// The leg `here -> g` was just picked (roam or stroll): sometimes run it with the game's own run gait. True = the run started (the caller must not start the walk).
    func mixTryRun(to g: SIMD2<Float>, _ sim: SoftBody) -> Bool {
        guard MoveMix.on, MoveMix.runChance > 0, idleMood != .grumpy, !mixSleepy, runMoveDemo == nil, !race.active, idleState.kind == nil, !hurry, commandedIdle == nil else { return false }
        let here = position, d = simd_distance(here, g)
        guard d >= MoveMix.runLegMin, fastOthers() < 2 else { return false }
        let others = socialOthers().filter { $0 !== self }
        for o in others {
            // never through a pair / group that is emoting, nor past anyone who is busy near the line
            let busy = o.social != nil || o.idleState.kind != nil || o.meetBusy
            let ab = g - here, t = max(0, min(1, simd_dot(o.position - here, ab) / max(simd_dot(ab, ab), 1e-4)))
            let near = simd_distance(o.position, here + ab * t)
            if (busy && near < MoveMix.runClearance) || near < peerGap * 1.1 { return false }
        }
        if let b = board, b.claimed(near: g, radius: MoveMix.claimRadius, except: steerID) { return false }
        guard roomLegConflict(from: here, to: g, speed: roomNominalWalk * 1.6, others: others, dash: true) < 0.01 else { return false }
        let chance = MoveMix.runChance * (1 - 0.75 * idleNight) * (idleMood == .happy ? 1 : MoveMix.okayRunMul)
        guard rand() < chance else { return false }
        var rg = here + (g - here) * MoveMix.runShare
        if d - simd_distance(here, rg) < MoveMix.runTail { rg = here + (g - here) / d * max(d - MoveMix.runTail, 0) }
        guard simd_distance(here, rg) >= 2.3, simd_distance(fixed(rg), rg) < 0.1, peerFree(rg), reachable(here, rg) else { return false }
        guard idleStart(.run, sim, goal: rg) else { return false }
        mix.afterRun = g; mix.afterRunUntil = variety.now + 14
        if anticsEnabled { kindCooldownStart(.run) }
        mix.legKind = "run"
        return true
    }
}

extension BlobBrain {
    /// pickAutonomous: a run just ended short of its goal: walk the rest (the normal blend in, no stop between).
    func mixAfterRunDue(_ sim: SoftBody) -> Bool {
        guard MoveMix.on, let g = mix.afterRun else { return false }
        mix.afterRun = nil
        guard variety.now < mix.afterRunUntil, idleState.kind == nil, simd_distance(position, g) > 0.5, peerFree(g) else { return false }
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
        script = .walk(target: g, then: .none); activity = .walking
        mix.last = .leg; mix.legKind = "run-tail"
        return true
    }
}
