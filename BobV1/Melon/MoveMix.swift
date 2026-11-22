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
    static let groupCoolHome: ClosedRange<Float> = 110...170
    static let groupCoolParkMul: Float = 0.5
    static let groupWaitMul: Float = 2
    // 4. walking
    static let legAfterSolo: Float = 0.7
    static let legMin: Float = 2.5
    static let idleWeight: Float = 3.5          // x board.idleness / 60 in a roam goal's score
    static let roamCandidates = 8          // (was 6 valid candidates)
    static let claimRadius: Float = 1.1
    /// Night / sleepy: the in-place chain rule and the forced leg off the buttons do not apply.
    static let sleepyNight: Float = 0.4
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
}

extension GameCamera.RoamFloor {
    /// True when a body standing at `p` is clear of the HUD button rails (`stopFree`, built whether or not the rails are cut out of the walkable floor). No rails built = everywhere.
    func stopOK(_ p: SIMD2<Float>) -> Bool {
        guard !stopFree.isEmpty, let g = zs.first else { return true }
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
        guard MoveMix.on, s.kind != .look, s.kind != .zoomies, !s.kind.isTreat else { return }
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
        defer { mix.strollUntil = -1 }
        guard now < mix.strollUntil, idleState.kind == nil, let g = mixStrollGoal() else { return false }
        let here = position
        let d = g - here
        let len = simd_length(d)
        mix.strollDir = len > 1e-3 ? d / len : .zero; mix.strollDirAt = now
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
        script = .walk(target: g, then: .none); activity = .walking
        mix.last = .leg
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
                var score = 0.6 * nearest + 0.3 * rand()
                if let b = board {
                    if b.claimed(near: cand, radius: MoveMix.claimRadius, except: steerID) { continue }
                    score += MoveMix.idleWeight * b.idleness(at: cand, now: b.now) / WalkBoard.idleCap
                }
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
