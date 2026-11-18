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
    /// C6 (2026-11-17, the owner: "I don't want them ... syncing into each other"): the HOME tray seats TWO per sitting. Three in the row behind it cannot keep apart
    /// in portrait: the 3-place stands are 1.11 apart, a body with its arms is ~1.4 wide (~1.6 through the catch lean), and the portrait floor holds side stands only
    /// to about +-1.2. The two-place row is clear (+0.5 u). The third waits calmly, clear of both, and eats at the next sitting (GameCare+Group); the café keeps
    /// `maxDiners`. Switch `-MealSeats 3` (simulator / dev builds; tests set it) = the old three at once.
    nonisolated(unsafe) static var homeSeats: Int = DevArgs.enabled && UserDefaults.standard.integer(forKey: "MealSeats") == 2 ? 2 : 3
    /// C6: how far a waiter for the next sitting keeps from every eater's stand and approach point (a body with its arms ~1.4 wide, ~1.6 through the catch, + margin).
    static let waiterClear: Float = 1.75
    /// C7 (round E; OFF by default since the round E re-survey: `-MealRolling 1` turns it on, simulator / dev builds): a waiter for the next sitting takes the first FREED place of the
    /// running sitting: the tray stays, that place is set again (DiningSet.restock(place:)), and he walks to its approach point once its leaver is off it
    /// (`joinClear` from the stand, or `joinWaitMax` s after the release). The sitting is kept while a waiter is pending (`waitersPending`).
    /// Off: round E measured 22 tray crossings on the join walk (the tray is already out; with no route found the walk goes straight at its target) and one
    /// 46 s stall, against none in round D. Off = round D's next sitting (the tray goes, the third walks in, a new tray pops).
    nonisolated(unsafe) static var rolling: Bool = DevArgs.enabled && UserDefaults.standard.integer(forKey: "MealRolling") == 1
    static let joinClear: Float = 1.2
    static let joinWaitMax: Float = 2.0
    /// GameCare+Group: true while a waiter for the next sitting is still waiting (C7 keeps the sitting, and its tray, for him).
    var waitersPending: () -> Bool = { false }
    /// GameCare+Group sets it before `start`: where SLEEPING waiters lie (they are never moved): the places and their approach points keep `waiterClear` from them.
    var keepClearOf: [SIMD2<Float>] = []
    /// C7: slots taken over by a joiner who has not been sent to eat yet (the serving state runs the approach logic for exactly these), seconds since each
    /// slot's diner was released, and how long the sitting has been held for a waiter with everybody done.
    private var joining: Set<Int> = []
    private var releasedT: [Float] = []
    private var heldForWaiter: Float = 0
    /// The tray's centre while a sitting runs (the waiters for the next sitting face it).
    var originNow: SIMD2<Float>? { isActive ? origin : nil }
    /// Per Jelly (by his ROSTER id, `memberIDs`): his tier now (nil = everybody takes the whole serving, no plan), and a callback for each piece he has eaten (jelly, count).
    var tierOf: ((Int) -> NeedTier)?
    var pay: ((Int, Int) -> Void)?
    /// Famished / Parched take their pieces faster (tests of the shared bite timing turn this off).
    var eager = true
    /// Every Jelbie's floor spot when the serving is asked for (GameCare sets it): the tray never appears on one of them.
    var avoid: [SIMD2<Float>] = []
    /// The café: the table is already out at this spot (restocked, not popped) and stays out when the sitting ends (the café despawns it).
    var forcedOrigin: SIMD2<Float>?
    var keepTable = false
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
    /// Smart line-up: a diner within `Lineup.commitDistance` of his approach point keeps his place for good; the others are re-planned every `Lineup.period` s (`replan`).
    private var committed: [Bool] = []
    private var replanClock: Float = 0
    /// How many times a place changed hands after the first plan (tests / diagnostics).
    private(set) var replans = 0
    /// Slice 1 of the meal line-up fix (switch `-DiningOrdered 0` = the old smart line-up, simulator / dev builds): the places of a FOOD sitting at the home tray are given once, at the start, in the order of the diners'
    /// x on the floor (left diner -> left place), and never re-planned, so nobody has to pass between or through the others to reach his place and a late arrival is never sent into a middle place
    /// between two standing diners. Since 2026-11-17 a DRINK sitting at the home tray is never re-planned either (the feeding survey: drinks, still re-planned, had the most
    /// stop-and-go and swings of every case), but it keeps the smart FIRST plan (`Lineup.best`): x-order breaks near-ties by index, and three on one side at the same x
    /// then crossed and waited on each other (LineupTests oneSide 10.8 s vs 5.9 s). Only the café keeps the smart line-up with `replan` exactly as before.
    nonisolated(unsafe) static var orderedPlaces: Bool = !(DevArgs.enabled && UserDefaults.standard.object(forKey: "DiningOrdered") != nil && UserDefaults.standard.integer(forKey: "DiningOrdered") == 0)          // (feeding-old-r1 follow-up: ON again, `-DiningOrdered 0` = the smart line-up)
    /// feeding-old-r1 follow-up (2026-11-18), each `-X 0` = the 6f246ad3 behaviour (simulator / dev builds):
    /// `orderedDrinks` (`-MealOrderedDrink 0`): a DRINK sitting is seated left-to-right by the diners' floor x too (the leftmost takes the left place), not by the smart plan.
    /// `trayToThem` (`-MealTrayToThem 0`): the home tray's spot is the open spot where the fewest diners start in front of their stand line, then the least total walking (not random).
    /// `straightWalk` (`-MealStraight 0`): a diner who starts behind his stand line walks STRAIGHT to his stand (no stop at the approach point, no second step in), ending the walk in the place's yaw.
    /// `wideRow` (`-MealWideRow 0`): the three-place row's side places stand 1.45 (or as wide as the floor allows) from the middle one, side diners straight forward (DiningLayout.sideX).
    nonisolated(unsafe) static var orderedDrinks: Bool = !(DevArgs.enabled && UserDefaults.standard.object(forKey: "MealOrderedDrink") != nil && UserDefaults.standard.integer(forKey: "MealOrderedDrink") == 0)
    nonisolated(unsafe) static var trayToThem: Bool = !(DevArgs.enabled && UserDefaults.standard.object(forKey: "MealTrayToThem") != nil && UserDefaults.standard.integer(forKey: "MealTrayToThem") == 0)
    nonisolated(unsafe) static var straightWalk: Bool = !(DevArgs.enabled && UserDefaults.standard.object(forKey: "MealStraight") != nil && UserDefaults.standard.integer(forKey: "MealStraight") == 0)
    nonisolated(unsafe) static var wideRow: Bool = !(DevArgs.enabled && UserDefaults.standard.object(forKey: "MealWideRow") != nil && UserDefaults.standard.integer(forKey: "MealWideRow") == 0)
    /// `endsLayout` (`-MealEnds 0`): the three-place home sitting seats two diners at the tray's two ENDS (45 deg toward tray and camera) and one in the middle behind it (DiningLayout.ends); it wins over `wideRow`.
    nonisolated(unsafe) static var endsLayout: Bool = !(DevArgs.enabled && UserDefaults.standard.object(forKey: "MealEnds") != nil && UserDefaults.standard.integer(forKey: "MealEnds") == 0)
    private var sideSet = false
    /// This sitting uses the x-ordered places (decided in `start`).
    private var ordered = false
    /// Slot of each walker when the walkers are sorted by x and the slots are sorted by x (the pairing that never crosses for walks to a line). Ties go to the lower index.
    static func orderedSlots(floors: [SIMD2<Float>], slots: [SIMD2<Float>]) -> [Int] {
        let by = floors.indices.sorted { floors[$0].x != floors[$1].x ? floors[$0].x < floors[$1].x : $0 < $1 }
        let sl = slots.indices.sorted { slots[$0].x != slots[$1].x ? slots[$0].x < slots[$1].x : $0 < $1 }
        var out = [Int](repeating: -1, count: floors.count)
        for (k, b) in by.enumerated() where k < sl.count { out[b] = sl[k] }
        return out
    }
    /// Diners whose floor x lie within this of a neighbour's (in x order) are a near-tie (2026-11-17, LineupTests: three on one side at the same x).
    static let tieX: Float = 0.5
    /// `orderedSlots`, but the diners of a near-tie in x share their x-ordered slots by the smart plan (`Lineup.best`: shortest walks, no crossings) instead of
    /// by index; everybody else keeps his x-ordered slot. Without a near-tie it is exactly `orderedSlots` (the 11-15 line-up the owner approved).
    static func orderedSlotsTied(floors: [SIMD2<Float>], slots: [SIMD2<Float>], centre: Int?) -> [Int] {
        let plan = orderedSlots(floors: floors, slots: slots)
        let by = floors.indices.sorted { floors[$0].x != floors[$1].x ? floors[$0].x < floors[$1].x : $0 < $1 }
        var tied = Set<Int>()
        for k in by.indices.dropFirst() where floors[by[k]].x - floors[by[k - 1]].x < tieX { tied.insert(by[k]); tied.insert(by[k - 1]) }
        guard !tied.isEmpty, !plan.contains(-1) else { return plan }
        return Lineup.best(from: floors, slots: slots, locked: floors.indices.map { tied.contains($0) ? nil : plan[$0] }, centre: centre)
    }
    /// Slice 2 of the meal line-up fix (switch `-DiningQuiet 0` = the old rule, simulator / dev builds): two diners of this sitting who are both at, or within `Lineup.commitDistance` of, their own place do not push each other
    /// (MelonStage.keepApart: the 0.7 gap and the skin wall are skipped for that pair), so the row at the tray is allowed to overlap a little but nobody is shoved back and forth. Latched per diner from the moment
    /// he is that near (or has started to eat) until he is released or the sitting ends, so it cannot flicker at the radius. Walking diners still avoid everybody else exactly as before.
    nonisolated(unsafe) static var quietPlaces: Bool = DevArgs.enabled && UserDefaults.standard.integer(forKey: "DiningQuiet") == 1
    private var quietLatch: Set<Int> = []
    /// The roster ids whose pair with `id` MelonStage.keepApart skips: the other quiet diners, when `id` is a quiet diner himself (empty otherwise: no allocation).
    func quietPeers(of id: Int) -> Set<Int> { Self.quietPlaces && isActive && forcedOrigin == nil && quietLatch.contains(id) ? quietLatch : [] }          // (food and drinks at the home tray; never the café)
    private func updateQuiet() {
        for i in brains.indices {
            let id = memberIDs[i]
            if released[i] { quietLatch.remove(id); continue }
            if !quietLatch.contains(id), started[i] || simd_distance(floor(i), approachPoint(blob: i)) < Lineup.commitDistance { quietLatch.insert(id) }
        }
    }
    /// C3, the meal's CALM WAIT (2026-11-17, the owner: "No bugs no extra movement they line up quickly and properly ... I don't want them turning, extra steps"; switch
    /// `-MealCalmWait 0` = the old wait, simulator / dev builds). Each diner's approach point lies behind his place ALONG his place's own facing, so the step-in is straight and
    /// he arrives squared up (no turn at the place); while he waits there he faces his place (BlobBrain.mealFaceYaw: one turn on arrival, then still: no look-around, no step in
    /// place, no face-the-camera turn); and he is sent to eat only once he faces it, or after `calmFacingWait` s ready (a diner who cannot square up is never held for good).
    nonisolated(unsafe) static var calmWait: Bool = DevArgs.enabled && UserDefaults.standard.integer(forKey: "MealCalmWait") == 1
    /// The calm wait is the HOME tray's (like the ordered line-up): the café keeps its own wait.
    private var calm: Bool { Self.calmWait && forcedOrigin == nil }
    static let calmFacing: Float = 0.2
    static let calmFacingWait: Float = 1.5
    /// Seconds diner i has stood ready (at his approach point, idle) in this approach (the facing fallback).
    private var readyT: [Float] = []
    /// The facing of each place of this sitting's layout (set in `start`).
    private var placeYaws: [Float] = []
    func placeYaw(_ p: Int) -> Float { placeYaws.indices.contains(p) ? placeYaws[p] : 0 }
    /// The approach point of the stand `s` of place `p`: `GameCare.approachBack` behind it, along the place's facing (calm wait) or straight back (the old rule).
    private func approach(stand s: SIMD2<Float>, place p: Int) -> SIMD2<Float> {
        guard calm else { return SIMD2(s.x, s.y - GameCare.approachBack) }
        let y = placeYaw(p)
        return s - GameCare.approachBack * SIMD2(sinf(y), cosf(y))
    }
    /// He faces his place (calm wait), or has stood ready long enough; always true with the old rule.
    private func facing(_ i: Int) -> Bool {
        guard calm else { return true }
        return abs(wrapAngle(brains[i].yaw - placeYaw(placeOf[i]))) < Self.calmFacing || (readyT.indices.contains(i) && readyT[i] >= Self.calmFacingWait)
    }
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
        approach(stand: stands[placeOf[i]], place: placeOf[i])          // (C3: along his place's facing)
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

    /// The approach points of all places, by place index.
    private var approachPoints: [SIMD2<Float>] { stands.enumerated().map { approach(stand: $0.element, place: $0.offset) } }

    /// Smart line-up: re-read who should take which place while the diners come (the nearest to the middle takes it, the others the free slot on their side, no walk
    /// across another, none through a standing diner). A diner within 1 u of his approach point is settled for good.
    private func replan(dt: Float) {
        replanClock += dt
        guard !ordered else { return }          // (x-ordered places are final: see `orderedPlaces`)
        guard replanClock >= Lineup.period, n > 1 else { return }
        replanClock = 0
        for i in brains.indices where !committed[i] && (started[i] || (released.indices.contains(i) && released[i]) || simd_distance(floor(i), approachPoint(blob: i)) < Lineup.commitDistance) { committed[i] = true }
        guard committed.contains(false) else { return }
        let from = brains.indices.map { floor($0) }
        let locked: [Int?] = brains.indices.map { committed[$0] ? placeOf[$0] : nil }
        let plan = Lineup.best(from: from, slots: approachPoints, locked: locked, centre: n == 3 ? 0 : nil, current: placeOf)
        guard plan != placeOf else { return }
        for i in brains.indices where plan[i] != placeOf[i] && !committed[i] {
            placeOf[i] = plan[i]; replans += 1
            if calm { brains[i].mealFaceYaw = placeYaw(plan[i]) }
            brains[i].callToMeal(.goTo(approachPoint(blob: i)))
        }
    }

    func start(_ c: Consumable, brains bs: [BlobBrain], floor f: @escaping (Int) -> SIMD2<Float>, ids: [Int]? = nil) {
        guard state == .idle, dining.phase == .absent || (forcedOrigin != nil && dining.phase != .poofing), !bs.isEmpty else { return }
        brains = Array(bs.prefix(Self.maxDiners)); n = brains.count; serving = c; floor = f
        memberIDs = Array((ids ?? Array(bs.indices)).prefix(n))
        if let fo = forcedOrigin { origin = fo }
        else if let s = MealTrace.takeSpot() { origin = s; MealTrace.log("choose branch=forced spot=(\(s.x),\(s.y)) (-DiningSpot)") }
        else {
            if (Self.wideRow || Self.endsLayout), n == 3 {          // (the widest side spacing the floor holds: wide row 1.45 / 1.3 / 1.11; ends layout 1.3 / 1.2 / 1.12)
                let js = avoid + brains.indices.map { f($0) }
                DiningLayout.ends = Self.endsLayout
                for sx: Float in (Self.endsLayout ? [1.3, 1.2, 1.12] : [1.45, 1.3, 1.11]) {
                    DiningLayout.sideX = sx
                    if sx == 1.11 || sx == 1.12 || !DiningSpot.openSpots(bob: SIMD2(99, 99), layout: DiningLayout.make(n: n), jellies: js).isEmpty { break }
                }
                sideSet = true
            }
            let L = DiningLayout.make(n: n), keep = keepClearOf, original = DiningSpot.pickOpen
            var was = original
            if Self.trayToThem {          // (the tray goes to them: fewest diners in front of their stand line, then the least total walking)
                let floors = brains.indices.map { f($0) }, closer = c.eatStyle == .sip ? GameCare.sipCloser : GameCare.eatCloser
                was = { offered in
                    var best: (front: Int, total: Float, o: SIMD2<Float>)?
                    for o in offered {
                        let stands = L.places.map { SIMD2(o.x + $0.rel.x, o.y + $0.rel.y + closer) }
                        let slot = Self.orderedSlots(floors: floors, slots: stands)
                        var front = 0, total: Float = 0
                        for i in floors.indices where slot[i] >= 0 {
                            let st = stands[slot[i]]
                            if floors[i].y > st.y + GameCare.popTolerance { front += 1 }
                            total += simd_distance(floors[i], st)
                        }
                        if best == nil || front < best!.front || (front == best!.front && total < best!.total - 1e-4) { best = (front, total, o) }
                    }
                    if let b = best { MealTrace.log("choose: tray to them front=\(b.front) walk=\(b.total)") }
                    return best?.o
                }
            }
            if Self.trayToThem || !keep.isEmpty {          // (round E: a SLEEPING waiter is never moved: this sitting's places and approach points keep `waiterClear` from where he lies)
                DiningSpot.pickOpen = { offered in
                    let ok = offered.filter { o in L.places.allSatisfy { p in let s = o + p.rel; return keep.allSatisfy { simd_distance($0, s) >= Self.waiterClear && simd_distance($0, s - SIMD2(0, GameCare.approachBack)) >= Self.waiterClear } } }
                    if ok.isEmpty { MealTrace.log("choose: no spot clear of the sleeping waiter(s); the usual pick") }
                    return was(ok.isEmpty ? offered : ok)
                }
            } else { DiningSpot.pickOpen = was }
            defer { DiningSpot.pickOpen = original }
            origin = DiningSpot.choose(bob: SIMD2(99, 99), layout: L, jellies: avoid + brains.indices.map { f($0) })
        }
        // nearest free spot for everybody (first claim wins by distance)
        placeYaws = DiningLayout.make(n: n).places.map(\.yaw)
        let spots = approachPoints          // (each place's approach point: `approach(stand:place:)`)
        committed = [Bool](repeating: false, count: n); replanClock = 0; replans = 0; quietLatch = []
        joining = []; releasedT = [Float](repeating: 0, count: n); heldForWaiter = 0
        placeOf = Lineup.best(from: brains.indices.map { f($0) }, slots: spots, locked: [Int?](repeating: nil, count: n), centre: n == 3 ? 0 : nil)
        ordered = Self.orderedPlaces && n > 1 && forcedOrigin == nil          // (food and drinks at the home tray; the café keeps `replan`)
        if ordered && (c.kind == .food || Self.orderedDrinks) { placeOf = Self.orderedSlotsTied(floors: brains.indices.map { f($0) }, slots: spots, centre: n == 3 ? 0 : nil) }          // (a drink keeps the smart first plan above: given once, never re-planned)
        finished = [Bool](repeating: false, count: n); released = [Bool](repeating: false, count: n)
        idle = [Float](repeating: 0, count: n); walkRetries = [Int](repeating: 0, count: n); mealRetries = [Int](repeating: 0, count: n)
        reserves = 0; gaveUp = false; age = 0
        tiers = [NeedTier](repeating: .famished, count: n); paid = [Int](repeating: 0, count: n); piecesFor = [Int](repeating: DiningTiming.bitesPerServing, count: n)
        savedFinished = brains.map { $0.onFinished }; savedGap = brains.map { $0.peerGap }; savedPeers = brains.map { $0.peers }
        for (i, b) in brains.enumerated() {
            let prev = b.onFinished
            b.onFinished = { [weak self] r in
                switch r { case .dine, .sip: self?.finished[i] = true; MealTrace.log("diner \(self?.memberIDs[i] ?? -1) finished (onFinished)"); default: break }
                prev?(r)
            }
            if tierOf != nil {
                b.peerGap = min(b.peerGap, Self.diningGap)
                // the diners keep their real peers (2026-11-01): each walks AROUND the others (standing and walking), whose places are re-planned while they come
                // (`replan`); MelonStage.keepApart (0.7) stays as the last-resort spring
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
        for i in brains.indices { brains[i].mealFaceYaw = calm ? placeYaw(placeOf[i]) : nil }          // (C3: the calm wait faces his own place)
        beginApproach()
        traceReadyIDs = []; traceBiteIDs = []; traceShareIDs = []; inBoxTicks = 0; popReason = "gathered"
        MealTrace.log("group start n=\(n) kind=\(serving.kind == .food ? "food" : "drink") origin=(\(origin.x),\(origin.y)) inFront=\(frontCount()) orderedPlaces=\(ordered) quietPlaces=\(Self.quietPlaces) calmWait=\(calm)")
        for i in brains.indices {
            let st = stands[placeOf[i]], ap = approachPoint(blob: i), f = floor(i)
            MealTrace.log("  diner id=\(memberIDs[i]) floor=(\(f.x),\(f.y)) place=\(placeOf[i]) stand=(\(st.x),\(st.y)) trayDist(stand)=\(trayDistance(st)) trayDist(approach)=\(trayDistance(ap))")
        }
    }

    // MARK: gather first, then the tray

    /// Floor spots of the Jelbies who are NOT at this sitting (GameCare sets it every tick): the tray pops in only where none of them stands.
    var bystanders: () -> [SIMD2<Float>] = { [] }
    /// Simulator-only trace aid (GameCare+Group sets it): diner i's soft-body centroid on the floor, for the `pose` line (the body as drawn, not the brain's root).
    var traceBody: ((Int) -> SIMD2<Float>)?
    /// Simulator-only trace aid (GameCare+Group sets it): diner i's mouth (world) while he sips a gulp (`dineIsSipping`, the chew phase), nil otherwise.
    var traceMouth: ((Int) -> SIMD3<Float>?)?
    /// Simulator-only trace aid (GameCare+Group sets it): the roster ids waiting for the next sitting (C6), for the ` wgaps=` part of the pose line.
    var traceWaiters: (() -> [Int])?
    /// Simulator-only trace aid (GameCare+Group sets it every tick): a waiter's floor point and activity, for the ` wpos=` part of the pose line (T9).
    var traceWaiterFloor: ((Int) -> (SIMD2<Float>, String)?)?
    /// The tray is drawn only once every diner stands at his place (his approach point), so no body ever walks across it on the way: the floor beside it is no wider than
    /// a body, there is no way round its ends (GameCare.serveWanted). Past this many seconds it pops in anyway (a diner that cannot get there is handled by the retries).
    static let gatherCap: Float = 12
    /// The meal's soft wake takes at most about 8 s (lag 2.8 + stir 1.2 + roll 1 + stretch 1.8 + look 0.6 + a bed hop); past this a sleeper is called the hard way.
    static var wakeCap: Float { BlobBrain.slowWakeOn ? SlowWakeTuning.mealCap : 11 }
    /// A bystander closer than this to the tray's rectangle holds the pop-in back (his belly + a margin), for at most 4 s past the cap.
    static let trayClearance: Float = 0.7
    /// Floor distance from `p` to the tray's rectangle (the tray as it will be drawn at its spot).
    func trayDistance(_ p: SIMD2<Float>) -> Float { DiningSpot.distance(from: p, origin: origin, layout: DiningLayout.make(n: max(n, 1))) }
    private var gathered: Bool { brains.indices.allSatisfy { (released.indices.contains($0) && released[$0]) || (ready($0) && isIdle(brains[$0]) && facing($0)) } }
    /// One awake diner is ready at his place and every other waiting diner is a meal-waking sleeper who lies behind his place's line and clear of the tray: the tray comes out now and the awake one eats at the
    /// normal time; each sleeper joins once he is up (the meal already takes a late arrival). Never true for an all-awake or all-asleep meal, nor with a sleeper in front of his line (today's timing then).
    private var awakeFirst: Bool {
        guard BlobBrain.softMealWakeOn else { return false }
        var awake = false
        for i in brains.indices {
            if released.indices.contains(i), released[i] { continue }
            if ready(i), isIdle(brains[i]), facing(i) { if awakeAtStart.indices.contains(i), awakeAtStart[i] { awake = true }; continue }          // (only a diner who was UP at the order counts: a sleeper who has just woken does not set the tray off early)
            guard brains[i].mealWaking, floor(i).y <= stands[placeOf[i]].y + GameCare.popTolerance, trayDistance(floor(i)) >= Self.trayClearance else { return false }
        }
        return awake
    }
    /// The tray's rectangle is not free to pop into: a bystander stands on (or right next to) it, or a diner who is still on his way does (2026-11-17 feeding
    /// survey, night: a meal-woken sleeper from the front was crossing the tray's floor when the 12 s cap popped it, so the tray came out under him and he
    /// walked out through it). A diner at his place (ready), sent to eat (started) or already done (released) never holds it back.
    private var trayBusy: Bool { bystanders().contains { trayDistance($0) < Self.trayClearance } || brains.indices.contains { dinerOnTrayFloor($0) } }
    func dinerOnTrayFloor(_ i: Int) -> Bool {
        guard brains.indices.contains(i), !(released.indices.contains(i) && released[i]), !(started.indices.contains(i) && started[i]), !ready(i) else { return false }
        return trayDistance(floor(i)) < Self.trayClearance
    }

    private func beginApproach() {
        state = .approaching; requested = false; settle = 0; earlyPop = false
        readyT = [Float](repeating: 0, count: n)
        // the food comes first, at its chosen spot; each Jelly then walks over and starts eating the moment he is there (nobody waits for the others)
        started = (0..<n).map { released.indices.contains($0) && released[$0] }          // (the ones already released are not called back)
        spawnTray()          // (OLD FLOW, feeding-old-r1: the tray is out at once for everybody; the café's table is out already: the food lands on it at once; a fresh tray waits for the gathering, see `tick`)
        for i in brains.indices { idle[i] = 0; walkRetries[i] = 0 }
        awakeAtStart = brains.map { !$0.isSleeping }
        for i in brains.indices where !released[i] {
            // a diner who starts at or behind his stand line walks straight to his stand (`startSitting`: the dine request walks, squares up on the way and eats); only one who has to come round uses the approach point
            if Self.straightWalk, forcedOrigin == nil, trayOut, floor(i).y <= stands[placeOf[i]].y + GameCare.popTolerance {
                started[i] = true; MealTrace.log("diner \(memberIDs[i]) straight start place=\(placeOf[i]) from=(\(floor(i).x),\(floor(i).y))"); startSitting(i)
            } else { brains[i].callToMeal(.goTo(approachPoint(blob: i))) }          // (a sleeper is woken at once, not softly: BlobBrain+SleepForce)
        }
        requested = true
    }

    /// Pops the tray in at the chosen spot (once the old one has gone) and fixes each diner's plan from his tier.
    private func spawnTray() {
        if forcedOrigin != nil, dining.phase == .present || dining.phase == .popping, dining.n == n, dining.restock(serving: serving) {          // the café's table is already out: the food lands on it
            MealTrace.log("tray restock reason=cafe")
            for i in brains.indices {
                paid[i] = 0
                if let tierOf { tiers[i] = tierOf(memberIDs[i]); piecesFor[i] = MealAppetite.pieces(tiers[i]) }
            }
            return
        }
        guard dining.phase == .absent, dining.spawn(serving: serving, n: n, bobAt: SIMD2(99, 99), forcedOrigin: origin) else { return }
        MealTrace.log("tray pop reason=\(popReason) inFront=\(frontCount()) age=\(age)")
        #if targetEnvironment(simulator)
        let box = dining.drawnBox(scale: 1)
        MealTrace.log("tray box c=(\(box.centre.x),\(box.centre.y)) half=(\(box.half.x),\(box.half.y)) stands=" + dining.places.map { "(\($0.stand.x),\($0.stand.y))" }.joined(separator: ";"))
        #endif
        for i in brains.indices {
            paid[i] = 0
            if let tierOf { tiers[i] = tierOf(memberIDs[i]); piecesFor[i] = MealAppetite.pieces(tiers[i]) }
        }
    }

    private var trayOut: Bool { dining.phase == .popping || dining.phase == .present }
    private func isIdle(_ b: BlobBrain) -> Bool { !b.mealWaking && (b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace) }
    /// He is at (or behind) his place's line and close to his approach point.
    private func ready(_ i: Int) -> Bool {
        let a = approachPoint(blob: i), f = floor(i)
        return f.y <= stands[placeOf[i]].y + GameCare.popTolerance && simd_distance(f, a) < 0.5
    }

    private func end() {
        settlePay()
        MealTrace.log("end gaveUp=\(gaveUp) trayDespawn=\(!keepTable) inBoxTicks=\(inBoxTicks) sim-age=\(age)")
        if !keepTable { dining.despawn() }
        state = .idle; requested = false
        for (i, b) in brains.enumerated() where i < savedFinished.count {
            b.peerGap = savedGap[i]
            if i < released.count, released[i] { continue }          // (already handed back: his hooks, reserve and idle block are his own again)
            b.onFinished = savedFinished[i]; b.idleBlocked = false; b.reserved = false; b.waitFocus = nil; b.mealFaceYaw = nil; if i < savedPeers.count { b.peers = savedPeers[i] }
        }
        savedFinished = []; savedGap = []; savedPeers = []
        quietLatch = []
        if sideSet { DiningLayout.sideX = 1.11; DiningLayout.ends = false; sideSet = false }
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
            let r = GameCare.mealRequest(serving, tray: dining, place: placeOf[i], pieces: piecesFor[i])
            if brains[i].isSleeping || brains[i].mealWaking { brains[i].callToMeal(r) } else { brains[i].requestNow(r) }
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
            released[i] = true; if releasedT.indices.contains(i) { releasedT[i] = 0 }
            MealTrace.log("diner \(memberIDs[i]) released eaten=\(eaten(i)) state=\(state)")
            b.onFinished = savedFinished[i]; b.idleBlocked = false; b.reserved = false; b.waitFocus = nil; b.mealFaceYaw = nil; b.peers = savedPeers[i]
        }
    }

    // MARK: meal trace (simulator-only output, see MealTrace)
    private var traceReadyIDs: Set<Int> = [], traceBiteIDs: Set<Int> = [], traceShareIDs: Set<Int> = []
    private(set) var popReason = "gathered"
    /// The tray came out for the awake diner(s) while sleepers were still waking (`awakeFirst`).
    private var earlyPop = false
    /// Per diner: was he on his feet (not asleep) when the meal was asked?
    private var awakeAtStart: [Bool] = []
    /// Ticks in which a held diner's floor point lay inside the drawn tray box while the tray was out (must stay 0).
    private(set) var inBoxTicks = 0
    /// Unreleased, unstarted diners nearer the camera (+z) than their place's line.
    private func frontCount() -> Int {
        brains.indices.filter { !(released.indices.contains($0) && released[$0]) && !(started.indices.contains($0) && started[$0]) && floor($0).y > stands[placeOf[$0]].y + GameCare.popTolerance }.count
    }
    private var tracePosTick = -1
    private func traceTick() {
        #if targetEnvironment(simulator)
        // (simulator only, 10 Hz) where every diner of the sitting stands: the meal-lineup captures measure path / reversals / overlap from these
        if Int(age * 10) != tracePosTick {
            tracePosTick = Int(age * 10)
            MealTrace.log("pos " + brains.indices.map { i in let f = floor(i); return "\(memberIDs[i])@p\(placeOf[i])=(\(String(format: "%.3f,%.3f", f.x, f.y)))\(started[i] ? "s" : "")\(released.indices.contains(i) && released[i] ? "r" : "")" }.joined(separator: " ") + " tray=\(trayOut ? 1 : 0)")
        }
        if MealTrace.poseOn {
            // (every fixed step) each diner's brain root, floor point, yaw and activity: the meal smoothness survey reads stalls, reversals, yaw snaps and shoves from these
            var line = String(format: "pose a=%.4f", age)
            for i in brains.indices {
                let b = brains[i], f = floor(i)
                let flags = (started[i] ? "s" : "-") + (released.indices.contains(i) && released[i] ? "r" : "")
                line += " \(memberIDs[i])@p\(placeOf[i])=" + String(format: "%.4f,%.4f,%.4f,%.4f,%.4f", b.position.x, b.position.y, f.x, f.y, b.yaw) + ",\(b.activity),\(flags)"
                if let tb = traceBody {
                    let c = tb(i); line += String(format: ",%.4f,%.4f", c.x, c.y)          // (the body centroid: what the eye follows)
                    if let tm = traceMouth {          // (his mouth to his own straw tip while he sips: the drink "mouth at the rim" check)
                        if let m = tm(i), let tip = dining.strawTip(place: placeOf[i]) { line += String(format: ",%.4f", simd_distance(m, tip)) } else { line += ",nan" }
                    }
                }
            }
            if brains.count > 1 {          // (every pair of diners: the drawn footprints' gap, + apart, - sunk into each other; nan = no profile)
                var gaps: [String] = []
                for i in brains.indices { for j in brains.indices where j > i { gaps.append("\(memberIDs[i])-\(memberIDs[j]):" + (ContactField.gap(memberIDs[i], memberIDs[j]).map { String(format: "%.4f", $0) } ?? "nan")) } }
                line += " gaps=" + gaps.joined(separator: ",")
            }
            if let ws = traceWaiters?(), !ws.isEmpty {          // (C6: every diner and every waiter for the next sitting: the waiter must stay clear of them, gap >= 0)
                var wg: [String] = []
                for i in brains.indices { for w in ws where w != memberIDs[i] { wg.append("\(memberIDs[i])-\(w):" + (ContactField.gap(memberIDs[i], w).map { String(format: "%.4f", $0) } ?? "nan")) } }
                line += " wgaps=" + wg.joined(separator: ",")
                if let wf = traceWaiterFloor {          // (T9: where each waiter stands and what he does: a negative wgap is real only at a short centre distance)
                    let wp = ws.compactMap { w in wf(w).map { "\(w):" + String(format: "%.4f,%.4f", $0.0.x, $0.0.y) + ",\($0.1)" } }
                    if !wp.isEmpty { line += " wpos=" + wp.joined(separator: ";") }
                }
            }
            line += trayOut ? " tray=1" : " tray=0"
            MealTrace.log(line)
        }
        let box = dining.drawnBox(scale: max(dining.scale, 0.001))
        for i in brains.indices where !(released.indices.contains(i) && released[i]) {
            let id = memberIDs[i], f = floor(i)
            if !traceReadyIDs.contains(i), ready(i), isIdle(brains[i]) { traceReadyIDs.insert(i); MealTrace.log("diner \(id) ready floor=(\(f.x),\(f.y)) place=\(placeOf[i])") }
            if started[i], trayOut {
                if !traceBiteIDs.contains(i), eaten(i) > 0 { traceBiteIDs.insert(i); MealTrace.log("diner \(id) first bite") }
                if !traceShareIDs.contains(i), eaten(i) >= piecesFor[i] { traceShareIDs.insert(i); MealTrace.log("diner \(id) ate its share (\(eaten(i)) of \(piecesFor[i]))") }
            }
            if trayOut, abs(f.x - box.centre.x) < box.half.x, abs(f.y - box.centre.y) < box.half.y {
                inBoxTicks += 1
                if inBoxTicks == 1 { MealTrace.log("INBOX diner \(id) floor=(\(f.x),\(f.y)) box c=(\(box.centre.x),\(box.centre.y)) half=(\(box.half.x),\(box.half.y))") }
            }
        }
        #endif
    }

    func tick(dt: Float) {
        defer { if !shared { dining.update(dt: dt) } }
        guard state != .idle else { return }
        if tierOf != nil { for (i, b) in brains.enumerated() where !(released.indices.contains(i) && released[i]) { b.idleBlocked = true } }          // no idle trick mid-sitting (Bob's walk to the tray is never cut for a flip)
        age += dt
        if age > GameCare.mealTimeout { MealTrace.log("giveup reason=timeout"); end(); gaveUp = true; return }
        traceTick()
        if Self.quietPlaces { updateQuiet() }
        for i in brains.indices where releasedT.indices.contains(i) && released.indices.contains(i) && released[i] { releasedT[i] += dt }
        switch state {
        case .approaching:
            if !trayOut, dining.phase == .absent || forcedOrigin != nil {
                let early = false
                if true {
                    popReason = forcedOrigin != nil ? "cafe" : (gathered && !trayBusy ? "gathered" : (early && !trayBusy ? "awake-first" : "cap"))
                    earlyPop = popReason == "awake-first"
                    spawnTray()
                }
            }
            if earlyPop { releaseFinished() }          // (an awake diner who has eaten his share does not stand held until the last sleeper has come)
            replan(dt: dt)
            for i in brains.indices {          // (C3: how long each has stood ready; the calm wait faces his place again after anything that cleared it, e.g. picked up and put down)
                readyT[i] = !started[i] && ready(i) && isIdle(brains[i]) ? readyT[i] + dt : 0
                if calm, !started[i], !(released.indices.contains(i) && released[i]), brains[i].reserved { brains[i].mealFaceYaw = placeYaw(placeOf[i]) }
            }
            for i in brains.indices where !started[i] && ready(i) && isIdle(brains[i]) && facing(i) && trayOut { started[i] = true; idle[i] = 0; joining.remove(i); MealTrace.log("diner \(memberIDs[i]) started place=\(placeOf[i])"); startSitting(i) }
            if started.allSatisfy({ $0 }) { state = .serving; return }
            // a meal-woken sleeper whose wake has run far past its longest legal length (a stuck stage) is called the hard way, once: nobody is left without food
            for i in brains.indices where !started[i] && brains[i].mealWaking && brains[i].sleep.mealWakeT > Self.wakeCap {
                MealTrace.log("wake FALLBACK diner=\(memberIDs[i]) after \(brains[i].sleep.mealWakeT) s")
                brains[i].sleep.mealWake = false; brains[i].sleep.mealCall = nil
                brains[i].requestHard(.goTo(approachPoint(blob: i)))
            }
            // anybody stuck idle away from his approach point is sent again, a few times; then the meal is given up
            for i in brains.indices where !started[i] && !ready(i) && isIdle(brains[i]) {
                // (while another Jelly is still walking in he may brush past and nudge a waiting one off his spot: nobody is given up on, or sent again, until the room has settled)
                guard !started[i] else { continue }
                idle[i] += dt
                if idle[i] > 0.5 {
                    idle[i] = 0
                    if walkRetries[i] < 3 { walkRetries[i] += 1; MealTrace.log("walk re-send diner=\(memberIDs[i]) retry=\(walkRetries[i])"); brains[i].callToMeal(.goTo(approachPoint(blob: i))) } else { MealTrace.log("giveup reason=walkRetries diner=\(memberIDs[i])"); end(); gaveUp = true; return }
                }
            }
        case .serving:
            settlePay()
            if finished.allSatisfy({ $0 }) {
                // (C7: everybody is done but a waiter is still coming: the sitting, and its tray, are kept for him; at most 4 s, then it ends as before)
                if Self.rolling, forcedOrigin == nil, waitersPending(), heldForWaiter < 4 { heldForWaiter += dt } else { end(); return }
            } else { heldForWaiter = 0 }
            releaseFinished()
            if !joining.isEmpty { tickJoining(dt) }
            for i in brains.indices where !finished[i] && !joining.contains(i) {          // (C7: a joiner on his way is not re-asked: tickJoining runs his approach)
                guard isIdle(brains[i]) else { idle[i] = 0; continue }
                idle[i] += dt
                guard idle[i] > 0.8 else { continue }
                idle[i] = 0
                let st = dining.places[placeOf[i]].stand
                if floor(i).y > st.y + GameCare.popTolerance + 0.05 {
                    // displaced in front of his place (the tray is between): everybody re-forms behind the tray, bounded
                    if reserves < GameCare.maxReserves { reserves += 1; MealTrace.log("re-serve #\(reserves) displaced diner=\(memberIDs[i])"); settlePay(); dining.despawn(); finished = finished.indices.map { released[$0] }; beginApproach() } else { MealTrace.log("giveup reason=displaced diner=\(memberIDs[i])"); end(); gaveUp = true }
                    return
                } else if mealRetries[i] < GameCare.maxReserves {
                    mealRetries[i] += 1
                    MealTrace.log("re-ask diner=\(memberIDs[i]) retry=\(mealRetries[i])")
                    startSitting(i)
                } else { MealTrace.log("giveup reason=mealRetries diner=\(memberIDs[i])"); end(); gaveUp = true; return }
            }
        case .idle: break
        }
    }

    // MARK: C7, the rolling seat

    /// The first freed place a waiter can take now: its diner was released and has walked `joinClear` off its stand (or `joinWaitMax` s passed). nil = none yet.
    func freeSlot() -> Int? {
        guard Self.rolling, isActive, forcedOrigin == nil, trayOut else { return nil }
        for i in brains.indices where released.indices.contains(i) && released[i] && !joining.contains(i) {
            if simd_distance(floor(i), stands[placeOf[i]]) >= Self.joinClear || (releasedT.indices.contains(i) && releasedT[i] >= Self.joinWaitMax) { return i }
        }
        return nil
    }

    /// A waiter for the next sitting takes slot `i` (a freed place) of the running sitting: his place is set again, his hooks are saved like a diner's,
    /// and he walks to its approach point (a sleeper is woken softly by `callToMeal`). The trace gets a `join` line.
    func join(slot i: Int, brain b: BlobBrain, id: Int, floor f: @escaping () -> SIMD2<Float>, body: (() -> SIMD2<Float>)? = nil, mouth: (() -> SIMD3<Float>?)? = nil) {
        guard brains.indices.contains(i), released.indices.contains(i), released[i], i < savedFinished.count else { return }
        let old = floor
        floor = { k in k == i ? f() : old(k) }
        if let tb = traceBody, let body { traceBody = { k in k == i ? body() : tb(k) } }
        if let tm = traceMouth, let mouth { traceMouth = { k in k == i ? mouth() : tm(k) } }
        quietLatch.remove(memberIDs[i])          // (the leaver's latch goes with him)
        brains[i] = b; memberIDs[i] = id
        finished[i] = false; released[i] = false; started[i] = false; releasedT[i] = 0
        idle[i] = 0; walkRetries[i] = 0; mealRetries[i] = 0; readyT[i] = 0; committed[i] = true; paid[i] = 0
        savedFinished[i] = b.onFinished; savedGap[i] = b.peerGap; savedPeers[i] = b.peers
        let prev = b.onFinished
        b.onFinished = { [weak self] r in
            switch r { case .dine, .sip: self?.finished[i] = true; MealTrace.log("diner \(self?.memberIDs[i] ?? -1) finished (onFinished)"); default: break }
            prev?(r)
        }
        if tierOf != nil { b.peerGap = min(b.peerGap, Self.diningGap) }
        if let tierOf { tiers[i] = tierOf(id); piecesFor[i] = MealAppetite.pieces(tiers[i]) } else { piecesFor[i] = DiningTiming.bitesPerServing }
        b.reserved = true; b.waitFocus = origin
        if calm { b.mealFaceYaw = placeYaw(placeOf[i]) }
        dining.restock(place: placeOf[i])
        traceReadyIDs.remove(i); traceBiteIDs.remove(i); traceShareIDs.remove(i)
        joining.insert(i); heldForWaiter = 0
        MealTrace.log("join waiter=\(id) slot=\(i) place=\(placeOf[i])")
        b.callToMeal(.goTo(approachPoint(blob: i)))
    }

    /// The approach of the joiners inside the serving state: the calm wait's facing, sent to eat once ready, idle and facing, the walk re-send, the wake fallback.
    private func tickJoining(_ dt: Float) {
        for i in joining.sorted() where brains.indices.contains(i) {
            readyT[i] = ready(i) && isIdle(brains[i]) ? readyT[i] + dt : 0
            if calm, brains[i].reserved { brains[i].mealFaceYaw = placeYaw(placeOf[i]) }
            if ready(i), isIdle(brains[i]), facing(i), trayOut {
                joining.remove(i); started[i] = true; idle[i] = 0
                MealTrace.log("diner \(memberIDs[i]) started place=\(placeOf[i])")
                startSitting(i)
                continue
            }
            if brains[i].mealWaking, brains[i].sleep.mealWakeT > Self.wakeCap {
                MealTrace.log("wake FALLBACK diner=\(memberIDs[i]) after \(brains[i].sleep.mealWakeT) s")
                brains[i].sleep.mealWake = false; brains[i].sleep.mealCall = nil
                brains[i].requestHard(.goTo(approachPoint(blob: i)))
                continue
            }
            if !ready(i), isIdle(brains[i]) {
                idle[i] += dt
                if idle[i] > 0.5, walkRetries[i] < 3 { idle[i] = 0; walkRetries[i] += 1; MealTrace.log("walk re-send diner=\(memberIDs[i]) retry=\(walkRetries[i])"); brains[i].callToMeal(.goTo(approachPoint(blob: i))) }
            } else { idle[i] = 0 }
        }
    }
}
