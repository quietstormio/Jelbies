//
//  GameCare+Focus.swift
//  "Come here" for ANY Jelly, and for everyone at once.
//  `comeHere(jelly:)`: that Jelly runs to the front spot and the close-up frames him; the others keep roaming, out of the camera's way (GameCare+FocusKeepOut.swift).
//  `comeHere(jellies:)`: the several named run to a row, the others keep roaming. `comeHereEveryone()`: all of them run to a row on the front line and the close-up widens to frame the row.
//  Jelly 0 keeps his own path in GameCare (the `queued` come, `tickFocus`); the others are driven here, once per fixed step (`driveFocus`).
//

import Foundation
import simd

/// Who the close-up is on, where each one stands, and the small per-Jelly bookkeeping of the approach and the touch.
@MainActor
final class FocusGroup {
    /// The Jellies the close-up is on (sorted ids). Empty = no focus has been asked for (or it is over).
    private(set) var ids: [Int] = []
    /// Their spots (x, z), by id.
    private(set) var spots: [Int: SIMD2<Float>] = [:]
    private(set) var arrived: Set<Int> = []
    /// Autonomy to hand back (Jellies whose wandering the focus paused), by id.
    var saved: [Int: Bool] = [:]
    /// The steering gap each row member had before the line-up (he keeps only the row's gap from the others while it is on: the slots are 1.15 apart, the room's gap is 1.4).
    var gapSaved: [Int: Float] = [:]
    static let rowSteerGap: Float = 1.05
    struct Approach { var requested = false; var age: Float = 0; var calm: Float = 0; var retries = 0; var short = 0; var hopped = false; var onSlot: Float = 0; var via: SIMD2<Float>? = nil; var viaNext: SIMD2<Float>? = nil; var best: Float = .infinity; var stuckT: Float = 0; var detours = 0 }
    /// A come walk that ended SHORT of the spot (someone stood on it and the floor rules dragged the target over the gap: he turned to wave 1.4 u early) is
    /// re-asked at once, this many times at most, while the stander steps aside (`MelonController.clearWay`); not counted against the calm retries.
    static let shortRetries = 6
    var approach: [Int: Approach] = [:]
    /// Jellies whose `.come` walk has just finished (reported by their brain).
    var came: Set<Int> = []
    /// The Jelly under the finger in the close-up (set by the stage); his centroid anchors the hearts (`touchAnchor`).
    var touchID = 0
    var touchAnchor: SIMD3<Float>?
    /// Pet attention not yet credited to a non-Bob Jelly (credited in chunks so a saving profile does not write every step).
    var petOwed: Float = 0
    var petClock: Float = 0

    nonisolated deinit {}

    var isRow: Bool { ids.count > 1 }
    /// Jelly 0 is part of this focus (also true when no focus was asked for: the one-Jelly game and the old tests).
    func includes(_ id: Int) -> Bool { ids.isEmpty || ids.contains(id) }
    func spot(of id: Int) -> SIMD2<Float> { spots[id] ?? GameCamera.callSpot }
    /// The floor's visible sides do not hold the wide row: while it is on, the brains may walk past them.
    var rowOpen = false
    /// The keep-out wedge for the current close-up (GameCare+FocusKeepOut.swift), cached per aspect / group, and the walk-out request clocks.
    var koCache: FocusKeepOut?
    var koAspect: Float = 0
    var koKey: [Int] = []
    var evictT: [Int: Float] = [:]
    /// Seconds since the walk began, the Jelly who stands in the middle (he goes first: nobody has to pass between two standing ones), and Jelly 0's walk held back for him.
    var clock: Float = 0
    var front = 0
    var zeroPending = false
    /// The uncalled bodies' floor spots at the call (the row is laid clear of them; a walker detours round one that lies on his straight way), and Jelly 0's detour point.
    var uncalled: [SIMD2<Float>] = []
    var viaZero: SIMD2<Float>?
    var viaZeroNext: SIMD2<Float>?
    var viaZeroAt: Float = 0
    var zeroBest: Float = .infinity, zeroStuck: Float = 0, zeroDetours = 0
    /// Smart line-up: the row's slots (0 = the middle), who has which, who is settled (within `Lineup.commitDistance` of his slot, or arrived), and the re-plan clock.
    private(set) var slots: [SIMD2<Float>] = []
    private(set) var slotOf: [Int: Int] = [:]
    private var committed: Set<Int> = []
    private var replanClock: Float = 0
    private(set) var replans = 0
    /// The line-up is never stuck: after `softAccept` seconds a Jelly within `nearEnough` of his spot is taken as arrived where he stands, after `hardAccept` anyone is.
    nonisolated(unsafe) static var softAccept: Float = 5.5, hardAccept: Float = 8
    /// 2026-11-19 ("the purple was sleep and now he's in the back there"): a called sleeper is woken with the SHORT wake at the call, his walk is held until he is on his feet, and the
    /// safety net's clock waits for him (at most `sleepWait` s), so he is never "accepted" lying / half-risen behind another. Off (dev `-ComeHereOld 1`, simulator builds) = the earlier behaviour.
    nonisolated(unsafe) static var sleeperFix = !(DevArgs.enabled && UserDefaults.standard.integer(forKey: "ComeHereOld") == 1)
    static let sleepWait: Float = 6
    nonisolated(unsafe) static var twoCornerMin: Float = 1.3
    /// Seconds the safety net's clock was held for a sleeper still waking.
    var netShift: Float = 0
    static let nearEnough: Float = 1.5, sidesWait: Float = 1.5
    /// Members the safety net had to accept where they stood (tests: a line-up that works needs none).
    var netAccepted = 0
    /// A side Jelly may set off once the middle one is (nearly) there, or after `sidesWait` seconds.
    func mayGo(_ id: Int, frontDistance: Float?) -> Bool {
        id == front || ids.count < 3 || arrived.contains(front) || clock > Self.sidesWait || (frontDistance ?? 99) < 2.4
    }

    /// Distance between neighbouring row centres: the game's, or the Adoption Center's wider pick row (set by `GameCare.beginFocus` for a preview).
    var rowSpacing: Float = GameCamera.focusRowSpacing

    func begin(ids new: [Int], front frontAsked: Int? = nil, floors: [Int: SIMD2<Float>] = [:], avoiding obstacles: [SIMD2<Float>] = [], reachable: @escaping (SIMD2<Float>) -> Bool = { _ in true }) {
        ids = new; uncalled = obstacles; viaZero = nil; viaZeroNext = nil; zeroBest = .infinity; zeroStuck = 0; zeroDetours = 0; arrived = []; clock = 0; netShift = 0; netAccepted = 0; zeroPending = false; front = frontAsked.flatMap { new.contains($0) ? $0 : nil } ?? new.first ?? 0; saved = [:]; gapSaved = [:]; approach = [:]; came = []; evictT = [:]; koCache = nil; touchID = new.first ?? 0; touchAnchor = nil; petOwed = 0; petClock = 0
        spots = [:]; GameCamera.focusFramed = []
        if new.count > 1 {
            let row = Self.rowAvoiding(count: new.count, spacing: rowSpacing, obstacles: obstacles, reachable: reachable)          // (the same expression a preview group is born on, moved aside only when an uncalled body would stand between or over them)
            // no fixed spot per Jelly: whoever is nearest the middle takes it, the others the free slot on their side (`Lineup`), re-read while they come (`replan`)
            slots = row; slotOf = [:]; committed = []; replanClock = 0; replans = 0
            if floors.count == new.count {
                let plan = Lineup.best(from: new.map { floors[$0]! }, slots: row, locked: [Int?](repeating: nil, count: new.count), centre: 0)
                for (i, id) in new.enumerated() { slotOf[id] = plan[i] }
                front = new.first { slotOf[$0] == 0 } ?? front
            } else {
                let order = front
                for (k, id) in ([order] + new.filter { $0 != order }).enumerated() { slotOf[id] = k }
            }
            for id in new { spots[id] = row[slotOf[id]!] }
            GameCamera.focusSpots = new.map { spots[$0]! }
        } else {
            let free = Self.rowAvoiding(count: 1, spacing: rowSpacing, obstacles: obstacles, reachable: reachable)[0]          // (decor may cover the usual spot; an uncalled body is never over him)
            for id in new { spots[id] = free }
            GameCamera.focusSpots = new.isEmpty ? [] : [free]
        }
        rowOpen = new.count > 1
    }

    // MARK: uncalled bodies are obstacles (2026-11-20: "two called, the third asleep in the middle": the called pair were pushed to either side of him and the close-up read as three in a row)
    /// A body's half width on the floor for the screen test (R 0.7 plus a sliver; an uncalled one may be lying: 1.8 across), and the floor distance a spot keeps from an uncalled body.
    static let bodyHalf: Float = 0.75, lyingHalf: Float = 0.95, bodyApart: Float = 1.6

    /// Where the uncalled bodies stand against the row `spots` on the close-up's screen: > 0 = every one is wholly to one side of the row (not between, not over), <= 0 = one is between or over them.
    /// (In half-bodies at the row's depth.)
    static func screenClear(_ spots: [SIMD2<Float>], _ obstacles: [SIMD2<Float>]) -> Float {
        let pose = GameCamera.focusPose(aspect: GameCamera.aspect, spots: spots)
        let f = simd_normalize(pose.target - pose.eye)
        func box(_ p: SIMD2<Float>, half: Float = bodyHalf) -> (lo: Float, hi: Float) {
            let d = max(simd_dot(SIMD3<Float>(p.x, 0.5, p.y) - pose.eye, f), 0.3)
            let c = (p.x - pose.eye.x) / d, h = half / d
            return (c - h, c + h)
        }
        let boxes = spots.map { box($0) }
        let lo = boxes.map(\.lo).min() ?? 0, hi = boxes.map(\.hi).max() ?? 0
        let unit = bodyHalf / max(simd_dot(SIMD3<Float>(spots[0].x, 0.5, spots[0].y) - pose.eye, f), 0.3)
        var worst = Float.infinity
        for o in obstacles {
            let b = box(o, half: lyingHalf)
            worst = min(worst, max(b.lo - hi, lo - b.hi) / unit)
        }
        return worst
    }

    /// How far to the side a row spot may be at depth `z` (the room's walkable width; the wide floor on a phone on its side).
    static func sideLimit(z: Float) -> Float {
        GameCamera.aspect > 1 ? min(GameCamera.roamRectWide.max.x - 0.4, max(2.2, GameCamera.visibleHalfWidthAtBody(z: z) * 0.93 - 0.3)) : 2.2
    }

    /// The spot is inside the floor's HUD-button cut-outs (`RoamFloor.railFree`): `GameCamera.constrain` would not move a body standing there.
    static func railFreeAt(_ p: SIMD2<Float>) -> Bool {
        guard let rf = GameCamera.roamFloor, !rf.railFree.isEmpty, let g = rf.zs.first, !rf.zs.isEmpty else { return true }
        let i = min(max(Int(floorf((p.y - g) / GameCamera.RoamFloor.step)), 0), rf.zs.count - 1)
        for r in [i, min(i + 1, rf.zs.count - 1)] where r < rf.railFree.count {
            let spans = rf.railFree[r]
            if spans.isEmpty || spans.contains(where: { $0.contains(p.x) }) { continue }
            if rf.free.isEmpty || r >= rf.free.count { continue }
            return false
        }
        return true
    }

    /// The row's spots (2026-11-20 rule): every called body in the FRONT-most row. An uncalled body (asleep or not) may stand BEHIND the row, even in the middle, but never beside or in front of it close enough
    /// to cover one (it keeps `bodyApart` from every spot, and is behind every spot by 0.25, or wholly to one side of the row on screen). The usual row (`previewRowSpots`) when that holds; else the nearest
    /// row to the call spot that holds it, that the called can walk to (`reachable`) and that lies inside the floor's button cut-outs. None: the usual row.
    static func rowAvoiding(count n: Int, spacing: Float, obstacles: [SIMD2<Float>], reachable: (SIMD2<Float>) -> Bool = { _ in true }) -> [SIMD2<Float>] {
        let base = GameCamera.previewRowSpots(count: n, spacing: spacing)
        guard !obstacles.isEmpty else { return base }
        func clear(_ sp: [SIMD2<Float>]) -> Bool {
            obstacles.allSatisfy { o in
                sp.allSatisfy { simd_distance($0, o) >= bodyApart } && (sp.allSatisfy { o.y <= $0.y - 0.25 } || screenClear(sp, [o]) > 0.05)
            }
        }
        if clear(base) { return base }
        let offs = n > 1 ? GameCamera.focusRowSpots(count: n, anchor: .zero, spacing: spacing) : [SIMD2<Float>.zero]
        var best: (spots: [SIMD2<Float>], d: Float)?
        var x: Float = -2.6
        while x <= 2.6001 {
            var z = GameCamera.callSpot.y - 1.4
            while z <= min(GameCamera.callSpot.y + 0.7, GameCamera.roamMaxZ - 0.4) {
                let a = SIMD2<Float>(x, z)
                let spots = offs.map { a + $0 }
                z += 0.1
                guard spots.allSatisfy({ abs($0.x) <= sideLimit(z: $0.y) && FreeFloor.isFree($0, radius: 0.8) && railFreeAt($0) && reachable($0) }), clear(spots) else { continue }
                let d = simd_distance(a, GameCamera.callSpot)
                if d < (best?.d ?? .infinity) { best = (spots, d) }
            }
            x += 0.1
        }
        return best?.spots ?? base
    }

    /// A point to walk to first, when the straight way from `p` to `s` brushes past an uncalled body. A lying body is 1.8 across (2.07 along) and a walker 1.4: the way past needs about 1.7 from its
    /// centre, so two lying bodies less than ~3.4 apart are a wall, not a slit a walker can use (r1 had them pin walkers at 1.3). The cheapest point `w` whose two legs both keep that clearance from every
    /// uncalled body and stay on free floor; the clearance steps down 1.7, 1.5, 1.3 only when no point works. nil = the straight way is fine, or no point works.
    static func detour(from p: SIMD2<Float>, to s: SIMD2<Float>, obstacles: [SIMD2<Float>], soft: [SIMD2<Float>] = [], fixed: (SIMD2<Float>) -> SIMD2<Float>) -> [SIMD2<Float>] {
        guard simd_length(s - p) > 1.5, !obstacles.isEmpty else { return [] }
        func segClear(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ clr: Float) -> Bool {
            let d = b - a, len = simd_length(d)
            guard len > 1e-3 else { return true }
            let u = d / len
            for o in obstacles {
                let t = min(max(simd_dot(o - a, u), 0), len)
                if simd_length(o - (a + u * t)) < clr { return false }
            }
            var t: Float = 0.1
            while t < len {
                let q = a + u * t
                if !FreeFloor.isFree(q, radius: 0.5) { return false }
                if simd_distance(q, s) > 1.6, soft.contains(where: { simd_distance($0, q) < min(clr, 1.4) }) { return false }          // (a called neighbour who will be standing on his spot: not passed through, except in the last stretch to my own spot)
                t += 0.2
            }
            return true
        }
        let dir = s - p, dl = simd_length(dir)
        guard obstacles.contains(where: { o in let t = min(max(simd_dot(o - p, dir / dl), 0), dl); return simd_length(o - (p + dir / dl * t)) < 1.7 }) || !segClear(p, s, 1.7) else { return [] }          // (nobody in the way: the usual walk)          // (nobody on the straight way: the usual walk)
        for clr: Float in [1.7, 1.5, 1.3] {
            var best: (SIMD2<Float>, Float)?
            var x: Float = -2.2
            while x <= 2.2001 {
                var z: Float = -2.0
                while z <= 3.0001 {
                    let w = SIMD2<Float>(x, z)
                    z += 0.25
                    guard simd_distance(fixed(w), w) < 0.15, obstacles.allSatisfy({ simd_distance($0, w) >= clr + 0.1 }), segClear(p, w, clr), segClear(w, s, clr) else { continue }
                    let cost = simd_distance(p, w) + simd_distance(w, s)
                    if cost < (best?.1 ?? .infinity) { best = (w, cost) }
                }
                x += 0.25
            }
            if let b = best { return [b.0] }
            // two corners (along the back wall, then up the side): both legs and the last one clear (not through a gap tighter than `twoCornerMin`: walkers are pushed off those)
            guard clr >= twoCornerMin, !soft.isEmpty else { continue }          // (a row only: for one called body the corner walks pinned him in r2's trials)
            var cand: [SIMD2<Float>] = []
            var cx: Float = -2.2
            while cx <= 2.2001 {
                var cz: Float = -2.0
                while cz <= 3.0001 {
                    let w = SIMD2<Float>(cx, cz); cz += 0.5
                    if simd_distance(fixed(w), w) < 0.15, obstacles.allSatisfy({ simd_distance($0, w) >= clr + 0.1 }) { cand.append(w) }
                }
                cx += 0.5
            }
            var best2: ([SIMD2<Float>], Float)?
            for a in cand where segClear(p, a, clr) {
                for b in cand where b != a && segClear(a, b, clr) && segClear(b, s, clr) {
                    let cost = simd_distance(p, a) + simd_distance(a, b) + simd_distance(b, s)
                    if cost < (best2?.1 ?? .infinity) { best2 = ([a, b], cost) }
                }
            }
            if let b = best2 { return b.0 }
        }
        return []
    }

    /// Smart line-up, once per fixed step while approaching: settle whoever is near his slot, re-plan the rest. Returns the Jellies whose spot changed.
    func replan(dt: Float, floors: [Int: SIMD2<Float>]) -> [Int] {
        replanClock += dt
        guard ids.count > 1, slots.count == ids.count, replanClock >= Lineup.period else { return [] }
        replanClock = 0
        for id in ids where !committed.contains(id) {
            if arrived.contains(id) || (floors[id].map { simd_distance($0, spot(of: id)) < Lineup.commitDistance } ?? false) { committed.insert(id) }
        }
        guard committed.count < ids.count, ids.allSatisfy({ floors[$0] != nil }) else { return [] }
        let plan = Lineup.best(from: ids.map { floors[$0]! }, slots: slots, locked: ids.map { committed.contains($0) ? slotOf[$0] : nil }, centre: 0, current: ids.map { slotOf[$0] ?? -1 })
        var changed: [Int] = []
        for (i, id) in ids.enumerated() where slotOf[id] != plan[i] && !committed.contains(id) { slotOf[id] = plan[i]; spots[id] = slots[plan[i]]; changed.append(id); replans += 1 }
        if !changed.isEmpty {
            front = ids.first { slotOf[$0] == 0 } ?? front
            GameCamera.focusSpots = ids.map { spots[$0]! }
        }
        return changed
    }

    /// One Jelly has reached his spot; true when the last one has (the camera may go in).
    func markArrived(_ id: Int) -> Bool {
        arrived.insert(id)
        return ids.allSatisfy { arrived.contains($0) }
    }

    func clear() {
        ids = []; uncalled = []; viaZero = nil; viaZeroNext = nil; spots = [:]; slots = []; slotOf = [:]; committed = []; arrived = []; clock = 0; zeroPending = false; saved = [:]; approach = [:]; evictT = [:]; koCache = nil; rowOpen = false; touchAnchor = nil; touchID = 0
        GameCamera.focusSpots = []; GameCamera.focusFramed = []
    }
}

extension GameCare {
    /// The Jellies the close-up is on right now (empty while roaming). In a one-Jelly game this is `[0]` during a close-up.
    var focusedJellies: [Int] { focus.isActive ? focusGroup.ids : [] }

    /// The Jelly the touch goes to in the close-up (the one under the finger; the first focused one until a finger picks another).
    var touchPlayTarget: Int { focusGroup.touchID }

    /// Where a focused Jelly stands in the close-up.
    func focusSpot(for id: Int) -> SIMD2<Float> { focusGroup.spot(of: id) }

    /// "Everyone, come here": all of them run up side by side and the close-up frames the row.
    func comeHereEveryone() { beginFocus(ids: Array(0..<max(jellies.count, 1)), front: targetJelly) }

    /// A preview stage (the Adoption Center): Jelbie `id` hops in place, with no gates. `wantJoy` is gated (antics, a 5 s expiry, "two fast movers at most"), so a second tap soon after
    /// would silently do nothing; `startHopPlay` is the greeting / selection hop and always plays. Distance 0.0001 = on the spot.
    func previewHop(_ id: Int) {
        guard isPreview, let b = brainFor(id) else { return }
        let sim = id == 0 ? lastSim : bathPlug.actors[id]?.actor?.sim
        if let sim { b.startHopPlay(sim: sim, distance: 0.0001) } else { b.wantJoy() }
    }

    /// A preview stage (the Adoption Center): every Jelbie that is not already facing the camera (heading 0) steps round to face it, so the species page, the pick row and the
    /// naming step all show a friendly front view (a snapped arrival skips the come-walk's turn).
    func previewFaceCamera() {
        guard isPreview else { return }
        for id in 0..<max(jellies.count, 1) {
            guard let b = brainFor(id), abs(atan2f(sinf(b.yaw), cosf(b.yaw))) > 0.15, b.idleState.kind == nil, case .none = b.script else { continue }
            if let sim = id == 0 ? lastSim : bathPlug.actors[id]?.actor?.sim { b.startTurn(to: 0, sim: sim) }
        }
    }

    /// "Pip and Moss, come here": just those run to the front row (the first named stands in front); the others keep roaming.
    func comeHere(jellies ids: [Int]) { beginFocus(ids: ids, front: ids.first) }

    func beginFocus(ids requested: [Int], front: Int? = nil) {
        guard focus.phase == .roaming, !bath.active, !tripActive else { return }
        var ids = Array(Set(requested.filter { jellies.indices.contains($0) })).sorted()
        if ids.isEmpty { ids = [0] }                  // an id outside the roster (a selection of a Jelly this game does not have): Bob
        if !silentArrival { for id in ids { AudioHub.shared.contextVoice(jelly: id, .mmhmm, chance: 0.5) } }          // (the player called; never from a hidden opening/preview Jelbie)
        greeting = false
        select.cancel()
        // a close-up that has just ended hands the paused Jellies' wandering back one brain per step (`driveFocus`); a call landing inside that window used
        // to wipe `saved` in `begin` and leave them with autonomy off for good (2026-10-21: "the other ones are stuck"). Hand it back here first.
        for (id, a) in focusGroup.saved { brainFor(id)?.autonomy = a }
        focusGroup.rowSpacing = isPreview ? GameCamera.pickRowSpacing : GameCamera.focusRowSpacing
        let others = (isPreview || !FocusGroup.sleeperFix) ? [] : (0..<jellies.count).filter { !ids.contains($0) && brainFor($0)?.isSleeping == true }.compactMap { floorOf($0) }          // (the uncalled who LIE: the row is laid clear of them; an awake one walks out of the camera's wedge by himself, `evictFromKeepOut`)
        focusGroup.begin(ids: ids, front: front, floors: Dictionary(uniqueKeysWithValues: ids.compactMap { id in floorOf(id).map { (id, $0) } }), avoiding: others, reachable: { p in ids.compactMap { self.brainFor($0) }.allSatisfy { simd_distance($0.fixed(p), p) < 0.12 } })
        if ids.count > 1 { for id in ids { if let b = brainFor(id) { focusGroup.gapSaved[id] = b.peerGap; b.peerGap = min(b.peerGap, FocusGroup.rowSteerGap) } } }
        focus.beginApproach()
        approachIdle = 0; approachRetries = 0; approachShort = 0
        var zeroAsleep = false
        if FocusGroup.sleeperFix {          // whoever sleeps is woken now (the quick get-up, never the slow morning wake) and walks to his reserved spot once he is up
            for id in ids where brainFor(id)?.isSleeping == true { wakeSleeper(id, groggy: false, fast: true); if id == 0 { zeroAsleep = true } }
        }
        if ids.contains(0) {
            if focusGroup.mayGo(0, frontDistance: nil), !zeroAsleep {
                if FocusGroup.sleeperFix, let b0 = brainFor(0), case let path = FocusGroup.detour(from: b0.position, to: focusGroup.spot(of: 0), obstacles: focusGroup.uncalled, soft: focusGroup.ids.filter { $0 != 0 }.map { focusGroup.spot(of: $0) }, fixed: { b0.fixed($0) }), let v = path.first { focusGroup.viaZero = v; focusGroup.viaZeroNext = path.count > 1 ? path[1] : nil; focusGroup.viaZeroAt = focusGroup.clock; queued = [.goTo(v)] }
                else { queued = [.come(to: focusGroup.spot(of: 0))] }
            } else { focusGroup.zeroPending = true }
        }
    }

    /// Where Jelly `id` stands on the floor now (nil = not in the room).
    func floorOf(_ id: Int) -> SIMD2<Float>? {
        guard let b = brainFor(id) else { return nil }
        return Self.floorPos(b, id == 0 ? lastSim : bathPlug.actors[id]?.actor?.sim)
    }

    /// Smart line-up: re-plan who takes which slot while they come, and send the ones whose slot changed to the new one.
    func focusReplan(dt: Float) {
        let g = focusGroup
        guard focus.phase == .approaching, g.isRow else { return }
        var floors: [Int: SIMD2<Float>] = [:]
        for id in g.ids { if let f = floorOf(id) { floors[id] = f } }
        for id in g.replan(dt: dt, floors: floors) {
            if id == 0 {
                if !g.zeroPending { queued = [.come(to: g.spot(of: 0))]; approachIdle = 0 }
            } else if g.approach[id]?.requested == true, let b = brainFor(id) {
                g.approach[id]?.age = 0; g.approach[id]?.short = 0
                b.requestNow(.come(to: g.spot(of: id)))
            }
        }
    }

    /// The group close-up frames the bodies where they REALLY stand (eased, so a sway or a settle never jitters the camera), not the slots they were sent to.
    func focusFrame(dt: Float) {
        let g = focusGroup
        guard !isPreview, g.ids.count > 1, focus.phase == .focused else { return }          // (a preview frames the slots the overlay projects; frozen while leaving: the camera eases out on the last frame)
        let now = g.ids.map { floorOf($0) ?? g.spot(of: $0) }
        if GameCamera.focusFramed.count != now.count { GameCamera.focusFramed = g.ids.map { g.spot(of: $0) } }
        let k = 1 - expf(-dt * 2.5)
        for i in now.indices { GameCamera.focusFramed[i] += (now[i] - GameCamera.focusFramed[i]) * k }
    }

    /// Distance of the middle Jelly from his spot (nil = he is the asker or gone).
    func frontDistance(except id: Int) -> Float? {
        let g = focusGroup
        guard g.front != id, let b = brainFor(g.front) else { return nil }
        return simd_length(Self.floorPos(b, g.front == 0 ? lastSim : bathPlug.actors[g.front]?.actor?.sim) - g.spot(of: g.front))
    }

    /// Never stuck: past `softAccept` seconds a Jelly near his spot, past `hardAccept` anyone, is accepted where he stands so the line-up completes
    /// (a body pinned between two standing ones, pushed by the separation rule, never "arrives"). Called once per fixed step from `tickFocus`.
    func focusSafetyNet(dt: Float) {
        let g = focusGroup
        guard focus.phase == .approaching, !g.ids.isEmpty else { return }
        g.clock += dt
        if FocusGroup.sleeperFix, g.netShift < FocusGroup.sleepWait, g.ids.contains(where: { brainFor($0)?.isSleeping == true }) { g.netShift += dt }          // (the net's clock waits for a sleeper to get up)
        let netClock = g.clock - g.netShift
        guard netClock > min(FocusGroup.softAccept, FocusGroup.hardAccept) else { return }
        for id in g.ids where !g.arrived.contains(id) {
            guard let b = brainFor(id) else { if g.markArrived(id) { focus.arrive(snap: isPreview) }; continue }
            let sim = id == 0 ? lastSim : bathPlug.actors[id]?.actor?.sim
            let d = simd_length(Self.floorPos(b, sim) - g.spot(of: id))
            guard d < FocusGroup.nearEnough || netClock > FocusGroup.hardAccept else { continue }
            b.pending = nil; b.interruptScript = true; g.netAccepted += 1
            if id == 0 {
                queued.removeAll { if case .come = $0 { return true }; return false }; callRunning = false
                g.zeroPending = false
                enterFocus(brain: b)
            } else {
                g.saved[id] = autonomySnapshot(id, b); b.autonomy = false; b.onFinished = nil
                if g.markArrived(id) { focus.arrive(snap: isPreview); if !silentArrival { AudioHub.shared.chirp(jelly: id, .happy, src: "group") } }
            }
            if !focus.isActive { return }
        }
    }

    /// The close-up's per-step work for Jelly `id` (Jelly 0 from `tick`, the others from `tickOthers`): pause the Jellies that are not in it,
    /// run the ones that are to their spots, hop them when it ends, and credit the petting to the one being petted.
    func driveFocus(id: Int, brain: BlobBrain, sim: SoftBody?, dt: Float) {
        let g = focusGroup
        guard !g.ids.isEmpty || !g.saved.isEmpty else { return }
        let phase = focus.phase
        if phase == .roaming {                     // over: hand the wandering back, then forget the group once everybody has
            if let a = g.saved.removeValue(forKey: id) { brain.autonomy = a }
            if let gp = g.gapSaved.removeValue(forKey: id) { brain.peerGap = gp }
            if id != 0 { brain.onFinished = nil }
            if g.saved.isEmpty { g.clear() }
            return
        }
        guard g.ids.contains(id) else {            // not in it: he keeps his life; if he stands in the camera's wedge he walks out of it (W2: the others are neither frozen nor hidden)
            evictFromKeepOut(id: id, brain: brain, dt: dt)
            return
        }
        guard id != 0 else { return }              // Jelly 0's own path is tickFocus
        var s = g.approach[id] ?? FocusGroup.Approach()
        defer { g.approach[id] = s }
        switch phase {
        case .approaching:
            if g.arrived.contains(id) { return }
            if FocusGroup.sleeperFix, brain.isSleeping { s.age = 0; s.calm = 0; s.onSlot = 0; return }          // (still getting up: the walk starts when he is on his feet)
            if !s.requested {
                guard g.mayGo(id, frontDistance: frontDistance(except: id)) else { return }
                s.requested = true; s.age = 0
                brain.onFinished = { [weak g] r in if case .come = r { g?.came.insert(id) } }
                if FocusGroup.sleeperFix, case let path = FocusGroup.detour(from: Self.floorPos(brain, sim), to: g.spot(of: id), obstacles: g.uncalled, soft: g.ids.filter { $0 != id }.map { g.spot(of: $0) }, fixed: { brain.fixed($0) }), let v = path.first { s.via = v; s.viaNext = path.count > 1 ? path[1] : nil; brain.requestNow(.goTo(v)) }
                else { brain.requestNow(.come(to: g.spot(of: id))) }
                return
            }
            s.age += dt
            if let v = s.via {          // walking round an uncalled body first, then to his spot
                if simd_length(Self.floorPos(brain, sim) - v) < 0.6 || s.age > 5 {
                    if let n = s.viaNext { s.via = n; s.viaNext = nil; s.age = 0; brain.requestNow(.goTo(n)) }
                    else { s.via = nil; s.age = 0; s.short = 0; s.best = .infinity; s.stuckT = 0; brain.requestNow(.come(to: g.spot(of: id))) }
                }
                return
            }
            // pinned (a lying body's keep-apart holds him short of his spot): walk round it from where he stands, at most three times
            if FocusGroup.sleeperFix {
                let hereNow = Self.floorPos(brain, sim), dNow = simd_length(hereNow - g.spot(of: id))
                if dNow < s.best - 0.05 { s.best = dNow; s.stuckT = 0 } else { s.stuckT += dt }
                if s.stuckT > 2, s.detours < 3, dNow > 0.5 {
                    s.stuckT = 0; s.detours += 1
                    let path = FocusGroup.detour(from: hereNow, to: g.spot(of: id), obstacles: g.uncalled, soft: g.ids.filter { $0 != id }.map { g.spot(of: $0) }, fixed: { brain.fixed($0) })
                    if let v = path.first { s.via = v; s.viaNext = path.count > 1 ? path[1] : nil; s.age = 0; brain.requestNow(.goTo(v)); return }
                }
            }
            // standing on his slot and still = arrived (the turn and the wave play AFTER arrival, they do not gate it)
            if simd_length(Self.floorPos(brain, sim) - g.spot(of: id)) < 0.25 { s.onSlot += dt } else { s.onSlot = 0 }
            if s.onSlot > 0.3 {
                g.saved[id] = autonomySnapshot(id, brain); brain.autonomy = false; brain.onFinished = nil
                if g.markArrived(id) { focus.arrive(snap: isPreview); if !silentArrival { AudioHub.shared.chirp(jelly: id, .happy, src: "group") } }
                return
            }
            let act = brain.activity
            let calm = act == .idle || act == .lookingAround || act == .steppingInPlace
            s.calm = (calm && s.age > 0.5) ? s.calm + dt : 0
            // the walk is over (he is turning / waving) but short of the spot: ask again now, the spot re-reads the floor once the stander has moved
            if s.age > 0.3, brain.isCome, !brain.isWalkScript, s.short < FocusGroup.shortRetries, simd_length(Self.floorPos(brain, sim) - g.spot(of: id)) > 0.5 {
                s.short += 1; s.age = 0; g.came.remove(id); brain.requestNow(.come(to: g.spot(of: id))); return
            }
            if g.came.contains(id) || s.calm > 0.3 {
                s.calm = 0; g.came.remove(id)
                let here = Self.floorPos(brain, sim)
                if simd_length(here - g.spot(of: id)) < 0.5 {
                    g.saved[id] = autonomySnapshot(id, brain); brain.autonomy = false
                    brain.onFinished = nil
                    if g.markArrived(id) { focus.arrive(snap: isPreview); if !silentArrival { AudioHub.shared.chirp(jelly: id, .happy, src: "group") } }
                } else if s.retries < 2 { s.retries += 1; s.age = 0; brain.requestNow(.come(to: g.spot(of: id))) }
                else { focus.cancelApproach() }
            }
        case .focused:
            if id == g.touchID, let tp = touchPlay {                 // petting Pip fills Pip's attention (Bob's goes through tickNeeds)
                let petting = tp.contact && tp.speed > TouchPlay.strokeSpeed * 0.5
                if petting || tp.isPurring { g.petOwed += dt * (tp.isPurring ? NeedsTuning.purrRate : NeedsTuning.petRate) }
            }
            g.petClock += dt
            if g.petClock >= 0.5 {
                g.petClock = 0
                if g.petOwed > 0 { needs(for: g.touchID).gain(.attention, g.petOwed); g.petOwed = 0 }
            }
        case .leaving:
            if !s.hopped {
                s.hopped = true
                if let a = g.saved.removeValue(forKey: id) { brain.autonomy = a }
                if let sim { brain.startHopPlay(sim: sim, distance: 0.25) }
            }
        default: break
        }
    }
}
