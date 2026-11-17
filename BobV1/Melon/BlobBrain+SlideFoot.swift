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

    /// Park slide only. Candidates: the three `slideOutSpots` (this brain's own index first for a stander: two who leave together do not pick the same spot) and, for the ex-rider only (still in
    /// his slide behaviour), a ring round the landing at radius peerGap + 0.5 then peerGap + 1.0, every 30 degrees, only the half away from the slide (the front half-plane of the landing,
    /// the sides included). Every candidate is at least peerGap + 0.3 from the landing and must pass: on the roam floor (`GameCamera.constrain` moves it < 0.05), the straight leg clear of the
    /// slide's box (so the walk never passes the box), no friend within 0.9 of the spot, outside every solid piece's zone, and NO FRIEND WITHIN 0.9 OF THE LEG (a friend on the leg is waited for up
    /// to 6 s by a requested walk, `BlobBrain.steerTarget`). ORDER: a stander takes the spots in his own index order; the ex-rider takes spots and ring TOGETHER, nearest first (the legs are
    /// straight and clear of the box, so the nearest is the shortest walk). The first candidate that passes everything wins.
    func slideWalkOut(_ f: DecorFoot, ring wantRing: Bool = false, accept: ((SIMD2<Float>) -> Bool)? = nil) -> SIMD2<Float>? {
        guard f.uid == ParkToys.slideUID else { return nil }
        let landing = slideLanding(f)
        let n = Self.slideOutSpots.count
        let exRider = wantRing || idleState.kind == .decorSlide          // (`ring`, r4: a stander walked off the foot by his own pick takes the ex-rider's ring of spots too)
        var rest: [(q: SIMD2<Float>, clear: Float)] = []          // (passed everything but the leg-friend check)
        func consider(_ q: SIMD2<Float>) -> SIMD2<Float>? {
            let c = legClearance(position, q)
            if c >= 0.9, accept?(q) ?? true { return q }          // (`accept`, r4: the waiter's own test of the leg; nil after the list, no fallback)
            rest.append((q, c))
            return nil
        }
        var spots: [SIMD2<Float>] = []
        for k in 0..<n {
            let q = f.centre + f.turned(Self.slideOutSpots[(steerID + k) % n])
            guard let out = decorFreeSpot(near: q), simd_distance(out, q) < 0.3, simd_distance(out, landing) >= peerGap + 0.3, slideLegClear(f, to: out) else { continue }
            spots.append(out)
        }
        guard exRider else {
            for q in spots { if let ok = consider(q) { return ok } }
            return nil
        }
        let away = simd_normalize(landing - f.centre + SIMD2<Float>(1e-4, 0))
        var ring: [SIMD2<Float>] = []
        for r in [peerGap + 0.5, peerGap + 1.0] {
            for k in 0..<12 {
                let a = Float(k) * .pi / 6
                let d = SIMD2<Float>(sinf(a), cosf(a))
                if simd_dot(d, away) >= -0.01 { ring.append(landing + d * r) }
            }
        }
        var all = spots
        for q in ring {
            let c = GameCamera.constrain(SIMD3(q.x, 0, q.y), radius: footprint)
            guard simd_distance(SIMD2(c.x, c.z), q) < 0.05, slideLegClear(f, to: q) else { continue }
            guard !steerPeers().contains(where: { simd_distance($0.pos, q) < 0.9 }) else { continue }
            guard !DecorField.shared.feet.contains(where: { $0.spec.solid && $0.distance(q) < footprint * $0.spec.reach + 0.12 }) else { continue }
            all.append(q)
        }
        for q in all.sorted(by: { simd_distance($0, position) < simd_distance($1, position) }) { if let ok = consider(q) { return ok } }
        if accept != nil { return nil }
        // none has a clear leg: the ex-rider must still leave. Only candidates at least peerGap from the landing, the one with the largest leg clearance; if none is that far, the farthest
        // from the landing whose leg clearance is at least 0.45.
        if let b = rest.filter({ simd_distance($0.q, landing) >= peerGap }).max(by: { $0.clear < $1.clear }) { Self.slideNoClearLeg += 1; return b.q }
        if let b = rest.filter({ $0.clear >= 0.45 }).max(by: { simd_distance($0.q, landing) < simd_distance($1.q, landing) }) { Self.slideNoClearLeg += 1; return b.q }
        return nil
    }

    /// The park slide fixes, by level (owner 2026-11-16, "They're still walking in slide"). 0 = main's rules before them. 1 = park-slide-r3: `decorExitCheck` keeps the park slide solid
    /// for a body whose centre is only over its edge (BlobBrain+Decor.swift), and the run-out's lifted floor rules end at the park swap (`GameCare.outingLanded`). 2 = park-slide-r4 (the
    /// game's level): also no walk-out softens it from outside its box (`walkOutSoftens`), nobody settles on its foot (`onSlideFoot`) and no wander leg ends there (`slideFootPoint`).
    /// Dev builds only: `-ParkSlideFix old` = 0, `-ParkSlideFix r3` = 1, for real-app before / after in one build; the headless soak's arms.
    nonisolated(unsafe) static var slideFixLevel: Int = {
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: "ParkSlideFix") else { return 2 }
        return v == "old" ? 0 : (v == "r3" ? 1 : 2)
    }()
    /// r3's two changes are on (level 1 or more). Set: true = every level (2), false = main's rules (0).
    static var slideSoftEndEnabled: Bool { get { slideFixLevel >= 1 } set { slideFixLevel = newValue ? 2 : 0 } }
    /// How many autonomous picks the foot rule turned into a walk off the foot (r4; the soak prints it against the social rates).
    nonisolated(unsafe) static var slideFootTurnAways = 0
    /// park-slide-r4: may a walk-out from piece `f` make it soft for him? Not the park slide while his centre is outside its box: from there every walk can leave it with the slide solid
    /// (his steps are pushed off it, the planner goes round it). The headless dense soak (seed 3) caught the walk-outs (after a ride, out of the zone, off the slide's foot) going
    /// straight through the box to a free spot on its far side while the slide was soft for them.
    func walkOutSoftens(_ f: DecorFoot) -> Bool { !(f.uid == ParkToys.slideUID && Self.slideFixLevel >= 2 && f.distance(position) > 0) }
    /// park-slide-r4: he stands on the park slide's foot (within peerGap + 0.1 of where a rider comes off the chute, `slideFootCheck`'s own measure) and is not using the slide. Nobody
    /// settles there: no social is started with him (`socialFree`, `socialWandering`: an invite used to stop an ex-rider's walk-out a step on, right on the landing) and his own pick is a
    /// walk off it (`pickAutonomous`). The dense soak (seed 3) had a cuddle-lean held on the foot: the rider on the platform waited his 8 s and came down into it (pairs closer than
    /// 0.9: 3 -> 280).
    var onSlideFoot: Bool {
        guard !(idleState.kind == .decorSlide && idleState.decorUID == ParkToys.slideUID) else { return false }
        return slideFootPoint(position)
    }
    /// The floor point `p` is on the park slide's foot (r4 only; never at home): a wander leg does not end there.
    func slideFootPoint(_ p: SIMD2<Float>) -> Bool {
        guard Self.slideFixLevel >= 2, let f = DecorField.shared.foot(ParkToys.slideUID) else { return false }
        return simd_distance(p, slideLanding(f)) < peerGap + 0.1
    }

    /// park-slide-r4 (owner: "smooth motion no glitchy movement"). A walk on the slide's foot that a friend standing on its leg holds (`steerTarget`: a requested walk waits up to 6 s,
    /// in the walking pose with no step: the walk "on the spot" after a ride) is not held there. After a quarter second the walk ends and he stands and waits, idle, feet still; his own
    /// pick (`slideFootRetry`, every quarter second) walks that walk, or another walk off the foot (`slideWalkOut`: the friend has moved), as soon as `steerTarget` would not hold
    /// it (`slideLegHeld`: its own tests, dry). After `slideFootWaitMax` of waiting (`slideFootWaitRider` while somebody else has the slide: the foot is his landing) he walks
    /// the best leg and does not wait for the friend on it (`slideFootForceTo`): the contact steering takes him past, as a requested walk went on after its 6 s before r4. The walks: a walk off the foot (the ex-rider's, a stander's: `slideFootWalkTo`), a step-aside asked of him there (`stepAside`), a wander leg (that one
    /// just ends: his own pick walks him off the foot).
    static let slideFootWaitMax: Float = 6, slideFootWaitRider: Float = 2
    var slideFootHoldStands: Bool {
        guard Self.slideFixLevel >= 2, !commanded, social == nil, idleState.kind == nil, onSlideFoot else { return false }
        guard let j = job else { return true }
        if let w = slideFootWalkTo, case .goTo(let p) = j, p == w { return true }
        return false
    }
    func slideFootStand(_ sim: SoftBody) {
        var resume: SIMD2<Float>?
        if let w = slideFootWalkTo, case .goTo(let p)? = job, p == w { resume = p }
        step(after: .none, sim, giveUp: true)          // (the hold comes between two steps: the walk ends, he stands, feet still)
        slideFootWalkTo = nil; heldByPeer = false
        if let resume { slideFootResume = resume; slideFootWaitSince = slideFootWaitSince ?? peerClock }
        restTimer = 0.25
    }
    /// His own pick while he waits on the slide's foot. True: the pick is made (he walks, or waits on).
    func slideFootRetry() -> Bool {
        guard let r = slideFootResume else { return false }
        let waited = peerClock - (slideFootWaitSince ?? peerClock)
        guard Self.slideFixLevel >= 2, onSlideFoot, waited <= Self.slideFootWaitMax + 1 else { slideFootResume = nil; slideFootWaitSince = nil; return false }          // (moved off the foot meanwhile, or an old wait: done)
        let f = DecorField.shared.foot(ParkToys.slideUID)
        var next: SIMD2<Float>? = slideLegHeld(position, r) ? nil : r
        if next == nil, let f { next = slideWalkOut(f, ring: true, accept: { [unowned self] q in simd_distance(q, r) > 0.3 && !self.slideLegHeld(self.position, q, planned: false) }) }
        if let q = next { slideFootResume = nil; slideFootWaitSince = nil; slideFootWalkTo = q; request(.goTo(q)); restTimer = 0.3; return true }
        let rider = DecorField.shared.occupant[ParkToys.slideUID].map { $0 != steerID } ?? false
        if waited >= (rider ? Self.slideFootWaitRider : Self.slideFootWaitMax) {
            let q = f.flatMap { slideWalkOut($0, ring: true) } ?? r
            slideFootResume = nil; slideFootWaitSince = nil; slideFootForceTo = q; request(.goTo(q)); restTimer = 0.3
            return true
        }
        restTimer = 0.25
        return true
    }
    /// Would `steerTarget` hold a walk from `a` to `b` for a friend on its leg right now? Its own tests in its order, with no side effects on the walk (the route, the patience).
    func slideLegHeld(_ a: SIMD2<Float>, _ b: SIMD2<Float>, planned: Bool = true) -> Bool {
        guard peerOnLeg(a, b) else { return false }
        if legClear(a, b, margin: steerMargin) || softLegClear(a, b, r: peerGap * 0.8) { return false }
        return !planned || planRoute(a, b, depth: 2) == nil          // (`planned` false: the other legs are not planned round; a held one is simply not taken)
    }
    /// He stands on the slide's foot waiting for his leg to clear: nobody asks him to step aside (`MelonStage.makeRoom`), `decorExitCheck` does not walk him out of the slide's zone.
    var slideFootWaiting: Bool { slideFootResume != nil && onSlideFoot }
    /// A step-aside (`MelonStage.makeRoom`, `clearWay`). On the slide's foot it is a slide-foot walk: held there, he stands and waits.
    func stepAside(to spot: SIMD2<Float>) {
        requestNow(.goTo(spot))
        if Self.slideFixLevel >= 2, onSlideFoot { slideFootWalkTo = spot }
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
        if Self.slideFixLevel >= 2 { slideFootWalkTo = out }          // (r4: held, he stands and waits)
        if f.distance(position) < footprint * f.spec.reach + 0.05 { insideDecorT = -4; insideStuckT = 0; if walkOutSoftens(f) { decorIgnore = f.uid } }          // (inside the zone: the generic walk-out must not fire on top of this one; r4: soft only from inside the box)
        request(.goTo(out))          // (NOT requestNow: from script .none that aborts the walk on the next tick)
    }
}
