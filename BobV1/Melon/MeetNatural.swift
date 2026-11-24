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
    static let kinds: Set<SocialKind> = [.boop, .squabble, .cheekSquish, .hopAlong, .highFive, .chestBump, .twirl, .nuzzle, .sitTogether, .swayHug, .whisperGiggle, .shyWave, .danceOff, .spinHug, .backToBack, .cuddleLean, .bellyBounce, .mirrorDance]
    static let minLeg: Float = 0.7
    /// A walk's speed (u/s) for the ETA.
    static let baseSpeed: Float = 1.25
    nonisolated(unsafe) static var log = false
}

extension BlobBrain {
    func meetSpeed() -> Float { MeetNatural.baseSpeed * min(max(amplitude, 0.6), 1) }
    private func meetTurnT(_ d: SIMD2<Float>) -> Float { simd_length(d) < 1e-4 ? 0 : abs(wrapAngle(atan2f(d.x, d.y) - yaw)) / max(turnRate, 0.5) }

    /// The shift `c` (applied to the partner's spot and to the initiator's goal) that makes both arrive together, or nil (the old start).
    func meetShift(goal ga: SIMD2<Float>, with o: BlobBrain) -> (c: SIMD2<Float>, etaA: Float, etaO: Float)? {
        let pa = position, po = o.position
        let L = simd_distance(ga, pa)
        guard L > MeetNatural.minLeg, let rf = roamProvider?() else { return nil }
        let va = meetSpeed(), vo = o.meetSpeed()
        var best: (c: SIMD2<Float>, etaA: Float, etaO: Float)?
        var bestDiff = Float.infinity
        let dir = (pa - ga)
        for k in 0...16 {
            let t = Float(k) / 20          // 0 ... 0.8 of the walk is the partner's
            let c = dir * t
            let af = ga + c, of = po + c
            let etaA = meetTurnT(af - pa) + simd_distance(af, pa) / va
            let etaO = (simd_length(c) > 0.05 ? o.meetTurnT(c) : 0) + simd_length(c) / vo
            let diff = abs(etaA - etaO)
            guard diff < bestDiff - 0.02 || (best == nil && k == 0) else { continue }
            if k > 0 {
                guard rf.contains(af), rf.contains(of), simd_distance(closeFixed(af), af) < 0.1, simd_distance(o.fixed(of), of) < 0.1 else { continue }
                guard spotFree(af, besides: [self, o]), spotFree(of, besides: [self, o]) else { continue }
                guard o.legClear(po, of, margin: o.steerMargin) else { continue }
            }
            best = (c, etaA, etaO); bestDiff = diff
        }
        guard let b = best, simd_length(b.c) > 0.3 else { return nil }
        return b
    }

    /// Called by `socialStart` after the kind's own start succeeded.
    func meetNaturalJoin(_ kind: SocialKind, with o: BlobBrain) {
        guard MeetNatural.enabled, MeetNatural.kinds.contains(kind), let s = social, s.kind == kind, o.social === s, s.end == nil, s.phase == 0,
              case .walk(let ga, _) = script, o.scriptIsNone, o.idleState.kind == nil, !o.socialTaken, o.activity != .walking else { return }
        guard let p = meetShift(goal: ga, with: o) else { return }
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
