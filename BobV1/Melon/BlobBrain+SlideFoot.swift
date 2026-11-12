//
//  BlobBrain+SlideFoot.swift
//  The park slide's foot stays free (2026-11-11): the one who has just ridden walks off to the lawn left of the path, and a free Jelbie who stands on the foot
//  while someone else has the slide steps off too. Before, the ex-rider got up and stayed on the landing: the next rider waited on the platform for the 8 s cap
//  (`runSlide` stage 4) and then rode into him.
//

import simd
import Foundation

extension BlobBrain {
    /// Where the chute lets him off: the floor spot at the end of the ride.
    func slideLanding(_ f: DecorFoot) -> SIMD2<Float> { f.centre + f.turned(SIMD2(0, Self.slideAt(Self.slideLength).z)) }

    /// The lawn spots an ex-rider (or a stander asked off the foot) walks to, in the slide's own frame (x to the side, z along the chute). With the park's layout
    /// (slide (2.9, 1.0), court (-2.1, 1.9)) they are (-0.35, 3.5), (-0.5, 2.1), (-0.5, 0.65): one column left of the path, each at least `peerGap + 0.3` from
    /// the landing, 1.15 from every hopscotch square and one gap from the next. ParkSlideCrowdTests pins all three.
    static let slideOutSpots: [SIMD2<Float>] = [SIMD2(-3.25, 2.5), SIMD2(-3.4, 1.1), SIMD2(-3.4, -0.35)]

    /// When each brain was last asked off the foot (its own `peerClock`): one ask per `slideFootEvery`, never one per tick.
    nonisolated(unsafe) static var slideFootAsked: [Int: Float] = [:]
    static let slideFootEvery: Float = 2.0

    /// The straight leg from here to `q` never comes nearer the slide's box than he already is (he is soft to the slide while he leaves; a leg across its corner walks through it).
    func slideLegClear(_ f: DecorFoot, to q: SIMD2<Float>) -> Bool {
        let from = position
        let floorD = min(f.distance(from), 0.15) - 0.02
        let n = max(1, Int(simd_distance(from, q) / 0.05))
        for i in 1...n { if f.distance(from + (q - from) * (Float(i) / Float(n))) < floorD { return false } }
        return true
    }

    /// How often `slideWalkOut` had no candidate with a clear leg and took the one with the largest clearance (tests / the soak report).
    nonisolated(unsafe) static var slideNoClearLeg = 0

    /// The least distance from any other body to the straight leg a -> b (9 = nobody about).
    func legClearance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        var least: Float = 9
        let d = b - a, len2 = max(simd_dot(d, d), 1e-6)
        for p in steerPeers() {
            let t = max(0, min(1, simd_dot(p.pos - a, d) / len2))
            least = min(least, simd_distance(p.pos, a + d * t))
        }
        return least
    }

    /// Park slide only. Candidate order: (1) the three `slideOutSpots`, starting at this brain's own index (two who leave together do not pick the same spot); (2) the ex-rider only
    /// (still in his slide behaviour): a ring round the landing at radius peerGap + 0.3 then peerGap + 0.9, every 30 degrees, only the half away from the slide (the front half-plane of
    /// the landing, the sides included), nearest to him first. Every candidate must pass the same checks: on the roam floor (`GameCamera.constrain` moves it < 0.05), the straight leg clear of
    /// the slide's box, no friend within 0.9 of the spot, outside every solid piece's zone, and NO FRIEND WITHIN 0.9 OF THE LEG (a friend on the leg is waited for up to 6 s by a requested walk,
    /// `BlobBrain.steerTarget`). The first candidate in that order that passes everything wins. If none does, the ex-rider takes the one with the largest leg clearance (counted in
    /// `slideNoClearLeg`): he must leave. A stander asked off the foot gets nil instead.
    func slideWalkOut(_ f: DecorFoot) -> SIMD2<Float>? {
        guard f.uid == ParkToys.slideUID else { return nil }
        let landing = slideLanding(f)
        let n = Self.slideOutSpots.count
        let exRider = idleState.kind == .decorSlide
        var rest: [(q: SIMD2<Float>, clear: Float)] = []          // (passed everything but the leg-friend check)
        func consider(_ q: SIMD2<Float>) -> SIMD2<Float>? {
            let c = legClearance(position, q)
            if c >= 0.9 { return q }
            rest.append((q, c))
            return nil
        }
        for k in 0..<n {
            let q = f.centre + f.turned(Self.slideOutSpots[(steerID + k) % n])
            guard let out = decorFreeSpot(near: q), simd_distance(out, q) < 0.3, simd_distance(out, landing) >= peerGap + 0.3, slideLegClear(f, to: out) else { continue }
            if let ok = consider(out) { return ok }
        }
        guard exRider else { return nil }
        let away = simd_normalize(landing - f.centre + SIMD2<Float>(1e-4, 0))
        var ring: [SIMD2<Float>] = []
        for r in [peerGap + 0.3, peerGap + 0.9] {
            for k in 0..<12 {
                let a = Float(k) * .pi / 6
                let d = SIMD2<Float>(sinf(a), cosf(a))
                if simd_dot(d, away) >= -0.01 { ring.append(landing + d * r) }
            }
        }
        for q in ring.sorted(by: { simd_distance($0, position) < simd_distance($1, position) }) {
            let c = GameCamera.constrain(SIMD3(q.x, 0, q.y), radius: footprint)
            guard simd_distance(SIMD2(c.x, c.z), q) < 0.05, slideLegClear(f, to: q) else { continue }
            guard !steerPeers().contains(where: { simd_distance($0.pos, q) < 0.9 }) else { continue }
            guard !DecorField.shared.feet.contains(where: { $0.spec.solid && $0.distance(q) < footprint * $0.spec.reach + 0.12 }) else { continue }
            if let ok = consider(q) { return ok }
        }
        // none has a clear leg: the ex-rider must still leave. Only candidates at least peerGap from the landing, the one with the largest leg clearance; if none is that far, the farthest
        // from the landing whose leg clearance is at least 0.45.
        if let b = rest.filter({ simd_distance($0.q, landing) >= peerGap }).max(by: { $0.clear < $1.clear }) { Self.slideNoClearLeg += 1; return b.q }
        if let b = rest.filter({ $0.clear >= 0.45 }).max(by: { simd_distance($0.q, landing) < simd_distance($1.q, landing) }) { Self.slideNoClearLeg += 1; return b.q }
        return nil
    }

    /// Park slide only, called with no behaviour running (`decorExitCheck`): a free Jelbie who stands on the slide's foot while someone else has the slide walks off
    /// to the lawn, so the rider has a clear landing. No spot free = he stays.
    func slideFootCheck() {
        guard !held, !decorLocked, pending == nil, social == nil, case .none = script else { return }
        guard let f = DecorField.shared.foot(ParkToys.slideUID), let rider = DecorField.shared.occupant[f.uid], rider != steerID else { return }
        guard simd_distance(position, slideLanding(f)) < peerGap + 0.1 else { return }
        if let t = Self.slideFootAsked[steerID], peerClock >= t, peerClock - t < Self.slideFootEvery { return }
        guard let out = slideWalkOut(f) else { return }
        Self.slideFootAsked[steerID] = peerClock
        if f.distance(position) < footprint * f.spec.reach + 0.05 { insideDecorT = -4; insideStuckT = 0; decorIgnore = f.uid }          // (inside the zone: the generic walk-out must not fire on top of this one)
        request(.goTo(out))          // (NOT requestNow: from script .none that aborts the walk on the next tick)
    }
}
