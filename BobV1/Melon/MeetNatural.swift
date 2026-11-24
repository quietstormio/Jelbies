//
//  MeetNatural.swift
//  meet-natural-r1 (2026-11-24; the owner: "make them going into emotes better it should be more natural not one standing waiting and then one side steps over ... they just walk into it").
//  THE JOINT APPROACH of a pair moment. Before: the initiator walked to a spot beside / before the partner, who stood and waited (`socialBook.hold`), then the stance walk shuffled the last centimetres.
//  Now, the instant a pair session starts (`socialStart`, every path), the whole START GEOMETRY of the kind is moved by one shift `c` toward the initiator: the partner walks to where he stands + c, the initiator to
//  his own goal + c. The shift is chosen so that both arrive together (equal ETA: distance / speed + the turn of a body that starts from a stand), through the kind's own legality rules (floor, free spot, clear leg).
//  The end spots are the kind's own (standGap / sideSpot: never closer), only moved; the contact stance still owns the last centimetres. Switch: `-MeetNatural 0` (DevArgs) / env MEETNATURAL=0 = the old start exactly.
//

import Foundation
import simd

enum MeetNatural {
    nonisolated(unsafe) static var enabled: Bool = {
        if let e = ProcessInfo.processInfo.environment["MEETNATURAL"] { return e != "0" }
        if DevArgs.enabled, UserDefaults.standard.object(forKey: "MeetNatural") != nil { return UserDefaults.standard.integer(forKey: "MeetNatural") != 0 }
        return enabledDefault
    }()
    static let enabledDefault = true
    /// Pair kinds whose start is "the initiator walks to a spot beside / before the partner, who waits": the two families (side by side facing the room, face to face) and the sit / hold kinds.
    /// Left on the old start: follow, chase, tag, sneak, keepAway, line, pass, bagSit, cuddle (a prop / a seat / a run), look, greet, zoomies, the travelling and the ring kinds.
    static let kinds: Set<SocialKind> = [.boop, .squabble, .cheekSquish, .hopAlong, .highFive, .chestBump, .twirl, .nuzzle, .sitTogether, .swayHug, .whisperGiggle, .shyWave, .danceOff, .spinHug, .backToBack, .cuddleLean, .bellyBounce, .mirrorDance, .peekaboo, .tag, .littleRace, .leapfrog, .ringAround]
    static let minLeg: Float = 0.7
    static let minShift: Float = 0.35
    static let partnerLag: Float = 0.08
    nonisolated(unsafe) static var why = [0, 0, 0, 0]
    /// A walk's speed (u/s) for the ETA.
    static let baseSpeed: Float = 1.25
    nonisolated(unsafe) static var log = false
}

extension BlobBrain {
    func meetSpeed() -> Float { MeetNatural.baseSpeed * min(max(amplitude, 0.6), 1) }
    private func meetTurnT(_ d: SIMD2<Float>) -> Float { simd_length(d) < 1e-4 ? 0 : abs(wrapAngle(atan2f(d.x, d.y) - yaw)) / max(turnRate, 0.5) }

    /// The straight leg a -> b is free floor (the floor rules leave every sample alone) and no body but the session's two stands within 0.8 gap of it (`legClear` counts the initiator, who is about to move, as an obstacle).
    func meetLegOK(_ a: SIMD2<Float>, _ b: SIMD2<Float>, partner: BlobBrain) -> Bool {
        let n = max(2, Int(simd_distance(a, b) / 0.15))
        let others = socialOthers().filter { $0 !== self && $0 !== partner }
        for i in 1...n {
            let p = a + (b - a) * (Float(i) / Float(n))
            if simd_distance(closeFixed(p), p) > 0.06 { return false }
            if others.contains(where: { simd_distance($0.position, p) < peerGap * 0.8 }) { return false }
        }
        return true
    }

    /// The shift `c` (applied to the partner's spot and to the initiator's goal) that makes both arrive together, or nil (the old start).
    func meetShift(goal ga: SIMD2<Float>, with o: BlobBrain) -> (c: SIMD2<Float>, etaA: Float, etaO: Float)? {
        let pa = position, po = o.position
        let L = simd_distance(ga, pa)
        guard L > MeetNatural.minLeg, let rf = roamProvider?() else { return nil }
        let va = meetSpeed(), vo = o.meetSpeed()
        var best: (c: SIMD2<Float>, etaA: Float, etaO: Float)?
        var bestDiff = Float.infinity
        let dir0 = (pa - ga)
        for ang: Float in [0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.2, -2.2] {          // (the shift points toward the initiator; a few turned ones when that one is not legal: wall, third body)
            let ca = cosf(ang), sa = sinf(ang)
            let dir = SIMD2<Float>(dir0.x * ca - dir0.y * sa, dir0.x * sa + dir0.y * ca)
            for k in 0...18 {
                let t = Float(k) / 20          // 0 ... 0.9 of the walk is the partner's
                let c = dir * t
                if simd_length(c) < MeetNatural.minShift { continue }          // (a partner who only turns and takes a step or two is still a waiter: no tiny shifts)
                let af = ga + c, of = po + c
                let etaA = meetTurnT(af - pa) + simd_distance(af, pa) / va
                let etaO = (simd_length(c) > 0.05 ? o.meetTurnT(c) : 0) + simd_length(c) / vo + MeetNatural.partnerLag          // (measured, takes v2: measured on takes v2 (18 joins): the partner arrives 0.08 s later on average, spread 0.6 s)
                let diff = abs(etaA - etaO) + abs(ang) * 0.15
                guard diff < bestDiff - 0.02 || best == nil else { continue }
                do {
                    guard rf.contains(af), rf.contains(of) else { MeetNatural.why[0] += 1; continue }
                    guard simd_distance(closeFixed(af), af) < 0.1, simd_distance(o.closeFixed(of), of) < 0.1 else { MeetNatural.why[1] += 1; continue }
                    guard spotFree(af, besides: [self, o]), spotFree(of, besides: [self, o]) else { MeetNatural.why[2] += 1; continue }
                    guard o.meetLegOK(po, of, partner: self) else { MeetNatural.why[3] += 1; continue }
                }
                best = (c, etaA, etaO); bestDiff = diff
            }
        }
        guard let b = best, simd_length(b.c) > 0.3 else { return nil }
        return b
    }

    /// Called by `socialStart` after the kind's own start succeeded.
    func meetNaturalJoin(_ kind: SocialKind, with o: BlobBrain) {
        guard MeetNatural.enabled, MeetNatural.kinds.contains(kind), let s = social, s.kind == kind, o.social === s, s.end == nil, s.phase == 0,
              case .walk(let ga, _) = script, o.scriptIsNone, o.idleState.kind == nil, !o.socialTaken, o.activity != .walking else { return }
        MeetNatural.why = [0, 0, 0, 0]
        guard let p = meetShift(goal: ga, with: o) else { if EmoteSpot.logOn { NSLog("[meetjoin] kind=%@ t=%.1f none (leg %.2f) why=%@", kind.rawValue, variety.now, simd_distance(ga, position), MeetNatural.why.map(String.init).joined(separator: ",")) }; return }
        if simd_distance(s.goal, ga) < 0.02 { s.goal = ga + p.c }
        emoteSendWalk(to: closeFixed(ga + p.c))
        o.emoteSendWalk(to: o.position + p.c)
        if MeetNatural.log || EmoteSpot.logOn { NSLog("[meetjoin] kind=%@ t=%.1f c=%.2f,%.2f len=%.2f etaA=%.2f etaO=%.2f", kind.rawValue, variety.now, p.c.x, p.c.y, simd_length(p.c), p.etaA, p.etaO) }
    }

    @discardableResult
    func socialStart(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let ok = socialStartCore(kind, with: o, sim)
        if ok { meetNaturalJoin(kind, with: o) }
        return ok
    }
}

// MARK: the group: everyone converges together

extension MeetNatural {
    /// seconds each member still waits before it sets off (steerID -> game time it may go), set once per group session
    nonisolated(unsafe) static var goAt: [Int: Float] = [:]
    nonisolated(unsafe) static var planned: ObjectIdentifier?
}

extension BlobBrain {
    /// Phase 0 of a ring kind (`gather`): true = this member still waits for its turn to set off, so that every member arrives at about the same moment (the nearer ones start later, nobody stands at the place).
    func meetGroupWait(_ s: SocialSession, _ mem: [BlobBrain]) -> Bool {
        guard MeetNatural.enabled, s.phase == 0, !socialBook.hopStarted else { return false }
        let sid = ObjectIdentifier(s)
        if MeetNatural.planned != sid || s.t < 0.05 {
            MeetNatural.planned = sid
            var eta: [Int: Float] = [:]
            for m in mem { eta[m.steerID] = simd_distance(m.position, m.slot(s)) / m.meetSpeed() + (simd_distance(m.position, m.slot(s)) > 0.3 ? 0.5 : 0) }
            let mx = min(eta.values.max() ?? 0, 4)
            MeetNatural.goAt = [:]
            for m in mem { MeetNatural.goAt[m.steerID] = max(0, mx - (eta[m.steerID] ?? 0)) }
            if MeetNatural.log || EmoteSpot.logOn { NSLog("[meetjoin] group=%@ t=%.1f delays=%@", s.kind.rawValue, variety.now, mem.map { String(format: "%.2f", MeetNatural.goAt[$0.steerID] ?? 0) }.joined(separator: ",")) }
        }
        return s.phaseT < (MeetNatural.goAt[steerID] ?? 0)
    }
}
