//
//  DiningGroup.swift
//  The meal for 2 or 3 Blobs: the same rule as one Blob (GameCare.serveWanted), for everyone at once.
//
//  The visible floor beside the 1.56 (N=2/3: 17 % wider) tray is a corridor ~0.2 u wide, so no Blob can pass the tray or each other there.
//  Instead the tray waits: every Blob first walks (no tray out) to the approach point 0.25 behind HIS place, then everybody rests `popSettle`,
//  then the tray pops and each steps forward to his place. Places are handed out in x order (left Blob -> left place), so the approach paths
//  never cross each other. Only targets / ordering / timing: the walk itself is untouched.
//
//  GameCare (GameCare+Group.swift) runs this for a GROUP serving: one drink, one straw per Jelly. It then shares its own DiningSet (`shared`), sets
//  `tierOf` / `pay` so every Jelly takes what HIS tier asks (Quenched refuses and shakes his head, Normal a little ... Parched all of it) and is paid
//  per piece, and lowers the peer gap of the diners while they stand round the tray. Food can use the same driver later (`serving.kind`).
//  Without those hooks (the nav tests) it behaves exactly as before: everybody takes the whole serving.
//

import Foundation
import simd

@MainActor
final class DiningGroup {
    enum State { case idle, approaching, serving }

    let dining: DiningSet
    /// GameCare owns the set's update / render and the tray obstacle (its resolver already wraps every brain): the group then neither updates nor wraps.
    private let shared: Bool
    /// Centre gap the diners keep from each other while they stand round the tray (the stands are 1.1 apart).
    static let diningGap: Float = 0.7
    /// The tray has three places at most (DiningLayout): with four Jellies GameCare+Group seats three and the fourth eats at the next sitting.
    static let maxDiners = 3
    /// Per Jelly (by his ROSTER id, `memberIDs`): his tier now (nil = everybody takes the whole serving, no plan), and a callback for each piece he has eaten (jelly, count).
    var tierOf: ((Int) -> NeedTier)?
    var pay: ((Int, Int) -> Void)?
    /// Famished / Parched take their pieces faster (tests of the shared bite timing turn this off).
    var eager = true
    private var tiers: [NeedTier] = []
    private var paid: [Int] = []
    private var savedFinished: [((BlobRequest) -> Void)?] = []
    private var savedGap: [Float] = []
    private var savedPeers: [(() -> [(id: Int, pos: SIMD2<Float>)])] = []
    /// What each blob does with the serving this sitting (pieces by tier) and which refused.
    private(set) var piecesFor: [Int] = []
    private(set) var state: State = .idle
    private(set) var n = 0
    private var serving: Consumable = Consumables.berries
    private var brains: [BlobBrain] = []
    private var floor: (Int) -> SIMD2<Float> = { _ in .zero }
    private var origin = DiningSpot.preferred
    /// place index of Blob i
    private(set) var placeOf: [Int] = []
    /// The roster id of diner i (`start(... ids:)`; by default 0..<n).
    private(set) var memberIDs: [Int] = []
    private var finished: [Bool] = []
    /// Diner i is done and has been handed back to his own life (released ahead of the others; `releaseFinished`).
    private var released: [Bool] = []
    /// Is this roster id a diner who is still held by the sitting (not yet released)?
    func isHolding(_ id: Int) -> Bool { isActive && memberIDs.firstIndex(of: id).map { !(released.indices.contains($0) && released[$0]) } ?? false }
    /// Blob i has been sent to eat (he arrived at his place).
    private var started: [Bool] = []
    private var requested = false
    private var settle: Float = 0
    private var age: Float = 0
    private var idle: [Float] = []
    private(set) var walkRetries: [Int] = []
    private var mealRetries: [Int] = []
    /// Re-serves used (a displaced Blob: the tray poofs, everybody re-forms behind it, it pops again). Bounded like GameCare.
    private(set) var reserves = 0
    private(set) var gaveUp = false
    private var hooked = false
    var isActive: Bool { state != .idle }

    init(dining: DiningSet = DiningSet(), shared: Bool = false) { self.dining = dining; self.shared = shared }
    nonisolated deinit {}
    var blobCount: Int { n }
    var kind: NeedKind { serving.kind == .food ? .hunger : .thirst }
    /// Gap the diners keep from each other right now (nil = the room's usual one).
    var peerGapNow: Float? { isActive ? Self.diningGap : nil }
    /// The diners' stands while a sitting runs (GameCare+Group moves the Jellies who are NOT at this sitting off them).
    var standsNow: [SIMD2<Float>] { isActive ? stands : [] }

    private var stands: [SIMD2<Float>] { // the tray-less stand of each place (eating / sipping offset included)
        let layout = DiningLayout.make(n: n)
        return layout.places.map { p in
            var s = origin + p.rel
            s.y += serving.eatStyle == .sip ? GameCare.sipCloser : GameCare.eatCloser
            return s
        }
    }
    /// Where Blob `i` first walks to: 0.25 behind his own place.
    func approachPoint(blob i: Int) -> SIMD2<Float> {
        let s = stands[placeOf[i]]
        return SIMD2(s.x, s.y - GameCare.approachBack)
    }

    /// Spots are NOT assigned per Jelly: every diner takes the free spot nearest to him. Greedy over all (Jelly, spot) pairs by distance (his floor
    /// position to the spot's approach point): the closest pair claims first, so a nearer Jelly keeps a spot two are heading for and the other
    /// gets his next-closest free one. Decided once at the start (arrival distance), so nobody swaps back and forth.
    static func nearestSpots(floors: [SIMD2<Float>], spots: [SIMD2<Float>]) -> [Int] {
        var pairs: [(d: Float, b: Int, p: Int)] = []
        for (b, f) in floors.enumerated() { for (p, q) in spots.enumerated() { pairs.append((simd_distance(f, q), b, p)) } }
        pairs.sort { $0.d != $1.d ? $0.d < $1.d : ($0.b != $1.b ? $0.b < $1.b : $0.p < $1.p) }
        var out = [Int](repeating: -1, count: floors.count), taken = Set<Int>()
        for e in pairs where out[e.b] < 0 && !taken.contains(e.p) { out[e.b] = e.p; taken.insert(e.p) }
        return out
    }

    func start(_ c: Consumable, brains bs: [BlobBrain], floor f: @escaping (Int) -> SIMD2<Float>, ids: [Int]? = nil) {
        guard state == .idle, dining.phase == .absent, !bs.isEmpty else { return }
        brains = Array(bs.prefix(Self.maxDiners)); n = brains.count; serving = c; floor = f
        memberIDs = Array((ids ?? Array(bs.indices)).prefix(n))
        origin = DiningSpot.choose(bob: SIMD2(99, 99), layout: DiningLayout.make(n: n))
        // nearest free spot for everybody (first claim wins by distance)
        let spots = DiningLayout.make(n: n).places.map { p -> SIMD2<Float> in
            var s = origin + p.rel
            s.y += c.eatStyle == .sip ? GameCare.sipCloser : GameCare.eatCloser
            return SIMD2(s.x, s.y - GameCare.approachBack)
        }
        placeOf = Self.nearestSpots(floors: brains.indices.map { f($0) }, spots: spots)
        finished = [Bool](repeating: false, count: n); released = [Bool](repeating: false, count: n)
        idle = [Float](repeating: 0, count: n); walkRetries = [Int](repeating: 0, count: n); mealRetries = [Int](repeating: 0, count: n)
        reserves = 0; gaveUp = false; age = 0
        tiers = [NeedTier](repeating: .famished, count: n); paid = [Int](repeating: 0, count: n); piecesFor = [Int](repeating: DiningTiming.bitesPerServing, count: n)
        savedFinished = brains.map { $0.onFinished }; savedGap = brains.map { $0.peerGap }; savedPeers = brains.map { $0.peers }
        for (i, b) in brains.enumerated() {
            let prev = b.onFinished
            b.onFinished = { [weak self] r in
                switch r { case .dine, .sip: self?.finished[i] = true; default: break }
                prev?(r)
            }
            if tierOf != nil {
                b.peerGap = min(b.peerGap, Self.diningGap)
                // every Jelly in the room is a diner with his OWN place (assigned once, 1.1 apart): nobody steers round, waits for or re-routes past another diner,
                // each walks straight to his place; MelonStage.keepApart (0.7) stays as the hard "never inside each other" rule
                b.peers = { [] }
            }
            if !shared, !hooked {
                let base = b.resolve
                b.resolve = { [weak self] p, r in
                    let rr = r - (self?.serving.eatStyle == .sip ? GameCare.sipCloser * 1.5 : 0)
                    let q = base(p, rr)
                    return self?.dining.obstacle(q, radius: rr * RoomLayout.lowPropRadiusScale) ?? q
                }
            }
        }
        hooked = true
        for b in brains { b.reserved = true; b.waitFocus = origin }          // everybody waits where he stands (look / step / bounce) until the meal is over
        beginApproach()
    }

    private func beginApproach() {
        state = .approaching; requested = false; settle = 0
        // the food comes first, at its chosen spot; each Jelly then walks over and starts eating the moment he is there (nobody waits for the others)
        started = (0..<n).map { released.indices.contains($0) && released[$0] }          // (the ones already released are not called back)
        spawnTray()
        for i in brains.indices { idle[i] = 0; walkRetries[i] = 0 }
        for i in brains.indices where !released[i] { brains[i].requestNow(.goTo(approachPoint(blob: i))) }
        requested = true
    }

    /// Pops the tray in at the chosen spot (once the old one has gone) and fixes each diner's plan from his tier.
    private func spawnTray() {
        guard dining.phase == .absent, dining.spawn(serving: serving, n: n, bobAt: SIMD2(99, 99), forcedOrigin: origin) else { return }
        for i in brains.indices {
            paid[i] = 0
            if let tierOf { tiers[i] = tierOf(memberIDs[i]); piecesFor[i] = MealAppetite.pieces(tiers[i]) }
        }
    }

    private var trayOut: Bool { dining.phase == .popping || dining.phase == .present }
    private func isIdle(_ b: BlobBrain) -> Bool { b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace }
    /// He is at (or behind) his place's line and close to his approach point.
    private func ready(_ i: Int) -> Bool {
        let a = approachPoint(blob: i), f = floor(i)
        return f.y <= stands[placeOf[i]].y + GameCare.popTolerance && simd_distance(f, a) < 0.5
    }

    private func end() {
        settlePay()
        dining.despawn(); state = .idle; requested = false
        for (i, b) in brains.enumerated() where i < savedFinished.count {
            b.peerGap = savedGap[i]
            if i < released.count, released[i] { continue }          // (already handed back: his hooks, reserve and idle block are his own again)
            b.onFinished = savedFinished[i]; b.idleBlocked = false; b.reserved = false; b.waitFocus = nil; if i < savedPeers.count { b.peers = savedPeers[i] }
        }
        savedFinished = []; savedGap = []; savedPeers = []
    }
    /// The meal is dropped (Come here, grabbed, timeout): the tray poofs, what was eaten stays paid.
    func cancel() { guard state != .idle else { return }; end() }

    /// Pieces blob `i` has eaten so far (gulps drunk / bites gone).
    private func eaten(_ i: Int) -> Int {
        let p = placeOf[i]
        guard dining.phase != .absent, dining.drunk.indices.contains(p) else { return 0 }
        if serving.kind == .drink { return Int((dining.drunk[p] * Float(DiningTiming.gulpsPerDrink) + 0.001).rounded(.down)) }
        return DiningTiming.bitesPerServing - dining.bitesLeft[p]
    }
    private func settlePay() {
        guard let pay, state == .serving || dining.phase != .absent else { return }
        for i in brains.indices {
            let k = min(eaten(i), piecesFor[i])
            if k > paid[i] { pay(memberIDs[i], k - paid[i]); paid[i] = k }
        }
    }
    /// Hooks, plan (from his tier) and request for blob `i` (the first serve, a retry and a re-serve).
    private func startSitting(_ i: Int) {
        brains[i].dineHooks = GameCare.hooks(for: serving, tray: dining, place: placeOf[i])
        if tierOf != nil {
            brains[i].dinePlan = GameCare.plan(for: serving, tier: tiers[i], tray: dining, place: placeOf[i])
            if !eager { brains[i].dinePlan.pace = 1 }
            brains[i].requestNow(GameCare.mealRequest(serving, tray: dining, place: placeOf[i], pieces: piecesFor[i]))
        } else { brains[i].requestNow(GameCare.mealRequest(serving, tray: dining, place: placeOf[i])) }
    }

    /// Each diner who is done with his own serving is handed back at once (he does not wait for the others): his hooks, reserve, idle block and wait-focus
    /// are restored so he roams / plays / socialises again. He keeps the diners' small peer gap and gets his real peers back, so he steers round the ones still
    /// eating (the diners' own empty peers + MelonStage.keepApart stay in force for them). The group wrap-up still happens once, in `end()`.
    private func releaseFinished() {
        guard tierOf != nil else { return }          // (the nav tests keep the old all-together behaviour)
        for i in brains.indices where finished[i] && !released[i] && i < savedFinished.count {
            let b = brains[i]
            guard isIdle(b) else { continue }          // (his dine job has returned; wait until he has settled)
            // `finished` alone is not proof he ate: a retried or preempted dine request also reports .dine / .sip. He is released only once the serving is really
            // down (his planned pieces eaten, tray still out), never before he has started.
            guard started[i], trayOut, eaten(i) >= piecesFor[i] else { continue }
            if let pay { let k = min(eaten(i), piecesFor[i]); if k > paid[i] { pay(memberIDs[i], k - paid[i]); paid[i] = k } }
            released[i] = true
            b.onFinished = savedFinished[i]; b.idleBlocked = false; b.reserved = false; b.waitFocus = nil; b.peers = savedPeers[i]
        }
    }

    func tick(dt: Float) {
        defer { if !shared { dining.update(dt: dt) } }
        guard state != .idle else { return }
        if tierOf != nil { for (i, b) in brains.enumerated() where !(released.indices.contains(i) && released[i]) { b.idleBlocked = true } }          // no idle trick mid-sitting (Bob's walk to the tray is never cut for a flip)
        age += dt
        if age > GameCare.mealTimeout { end(); gaveUp = true; return }
        switch state {
        case .approaching:
            if !trayOut { spawnTray() }
            for i in brains.indices where !started[i] && ready(i) && isIdle(brains[i]) && trayOut { started[i] = true; idle[i] = 0; startSitting(i) }
            if started.allSatisfy({ $0 }) { state = .serving; return }
            // anybody stuck idle away from his approach point is sent again, a few times; then the meal is given up
            for i in brains.indices where !started[i] && !ready(i) && isIdle(brains[i]) {
                // (while another Jelly is still walking in he may brush past and nudge a waiting one off his spot: nobody is given up on, or sent again, until the room has settled)
                guard !started[i] else { continue }
                idle[i] += dt
                if idle[i] > 0.5 {
                    idle[i] = 0
                    if walkRetries[i] < 3 { walkRetries[i] += 1; brains[i].requestNow(.goTo(approachPoint(blob: i))) } else { end(); gaveUp = true; return }
                }
            }
        case .serving:
            settlePay()
            if finished.allSatisfy({ $0 }) { end(); return }
            releaseFinished()
            for i in brains.indices where !finished[i] {
                guard isIdle(brains[i]) else { idle[i] = 0; continue }
                idle[i] += dt
                guard idle[i] > 0.8 else { continue }
                idle[i] = 0
                let st = dining.places[placeOf[i]].stand
                if floor(i).y > st.y + GameCare.popTolerance + 0.05 {
                    // displaced in front of his place (the tray is between): everybody re-forms behind the tray, bounded
                    if reserves < GameCare.maxReserves { reserves += 1; settlePay(); dining.despawn(); finished = finished.indices.map { released[$0] }; beginApproach() } else { end(); gaveUp = true }
                    return
                } else if mealRetries[i] < GameCare.maxReserves {
                    mealRetries[i] += 1
                    startSitting(i)
                } else { end(); gaveUp = true; return }
            }
        case .idle: break
        }
    }
}
