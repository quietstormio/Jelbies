//
//  EmoteSpot.swift
//  WHERE emotes happen in the HOME rooms (2026-11-20, emote-spread-r1; the owner: "they're doing too much in the middle of the room ... spread out, use the entire room").
//  THE ONE PLACE that chooses a spot for an emote: a solo emote's stand (`emoteSoloGate`), a pair's meeting spots (`emoteMeetPlan`), a group's ring centre (`emoteGroupCentre`).
//  Nothing here changes a move, a body, a contact rule or a rate: an emote that was going to start is only started somewhere else first (a short walk), and only when the place it
//  would have started on is clearly worse than another one. Home rooms only (`homeRoom`): the Park and the Camp never see it.
//  The score of a spot: how often emotes happened there lately (`heat`, a decaying count per 1 u cell) and how near the rug centre it is; a long walk costs a little.
//  Switch: `EmoteSpot.enabled` (dev: `-EmoteSpread 0`).
//

import simd
import Foundation

enum EmoteSpot {
    nonisolated(unsafe) static var enabled: Bool = !(DevArgs.enabled && UserDefaults.standard.object(forKey: "EmoteSpread") != nil && UserDefaults.standard.integer(forKey: "EmoteSpread") == 0)
    /// Recent emotes per 1 u floor cell; every noted emote fades all of them by `decay` (no clock: a count of emotes, so the headless suites behave).
    nonisolated(unsafe) static var heat: [Int: Float] = [:]
    static let decay: Float = 0.94
    /// Rug-centre penalty (a spot right on the centre costs this much; it fades to 0 at `rugReach`).
    static let rugWeight: Float = 2.2
    static let rugReach: Float = 2.6
    /// Weight of a depth / width third being used more (less) than its third of the recent emotes.
    static let bandWeight: Float = 5
    /// A walk costs this per unit of its longest leg; a spot is taken only when it beats where the emote would have been by at least `margin`.
    static let legCost: Float = 0.45
    static let margin: Float = 1.6
    /// Longest walk to a spot: solo, pair (each body), group (checked by the ring plan itself: GroupTuning.walkMax).
    static let soloLeg: Float = 4.5, pairLeg: Float = 6.0
    /// Weight of `score` in a roam goal's score (home rooms): the legs between emotes lean toward the spots emotes have used least, so most emotes need no walk of their own.
    static let roamWeight: Float = 0.6
    /// How far apart the two bodies of a pair stand on the meeting spot.
    static let pairHalf: Float = 0.55

    /// Dev capture (`-EmoteLog 1`, DevArgs builds only): one `[emotespot]` line per body per second: game time, id, floor x / z, what he is doing.
    nonisolated(unsafe) static var logOn: Bool = DevArgs.enabled && UserDefaults.standard.bool(forKey: "EmoteLog")
    static func reset() { heat = [:]; zUse = [0, 0, 0]; xUse = [0, 0, 0] }
    private static func key(_ cx: Int, _ cz: Int) -> Int { (cx + 50) * 1000 + cz + 50 }

    /// Recent emotes per depth third and per width third of the walkable floor (equal-AREA thirds of the roam floor's free spans; faded like `heat`).
    nonisolated(unsafe) static var zUse: [Float] = [0, 0, 0], xUse: [Float] = [0, 0, 0]
    nonisolated(unsafe) private static var cutKey = ""
    nonisolated(unsafe) private static var zCut: (Float, Float) = (0, 0), xCut: (Float, Float) = (0, 0)
    private static func cuts(_ rf: GameCamera.RoamFloor) {
        let k = "\(rf.aspect)/\(rf.zs.count)/\(rf.minZ)/\(rf.maxZ)/\(rf.free.reduce(0) { $0 + $1.count })"
        guard k != cutKey else { return }
        cutKey = k
        var zs = [Float](), xs = [Float]()
        for (i, z) in rf.zs.enumerated() where i < rf.free.count {
            for sp in rf.free[i] { var x = sp.lowerBound; while x <= sp.upperBound { zs.append(z); xs.append(x); x += 0.25 } }
        }
        guard zs.count > 9 else { zCut = (-1e3, 1e3); xCut = (-1e3, 1e3); return }
        zs.sort(); xs.sort()
        zCut = (zs[zs.count / 3], zs[2 * zs.count / 3]); xCut = (xs[xs.count / 3], xs[2 * xs.count / 3])
    }
    private static func band(_ p: SIMD2<Float>) -> (z: Int, x: Int) {
        (p.y < zCut.0 ? 0 : (p.y < zCut.1 ? 1 : 2), p.x < xCut.0 ? 0 : (p.x < xCut.1 ? 1 : 2))
    }
    static func note(_ p: SIMD2<Float>, _ rf: GameCamera.RoamFloor) {
        cuts(rf)
        for k in heat.keys { heat[k]! *= decay }
        heat[key(Int(floorf(p.x)), Int(floorf(p.y))), default: 0] += 1
        let b = band(p)
        for i in 0..<3 { zUse[i] *= decay; xUse[i] *= decay }
        zUse[b.z] += 1; xUse[b.x] += 1
    }
    static func heatAt(_ p: SIMD2<Float>) -> Float {
        let cx = Int(floorf(p.x)), cz = Int(floorf(p.y))
        var h = heat[key(cx, cz)] ?? 0
        for (dx, dz) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { h += 0.3 * (heat[key(cx + dx, cz + dz)] ?? 0) }
        return h
    }
    /// How good a spot is for the next emote (higher = better): few recent emotes in its cell, its depth third and its width third, and away from the rug centre.
    static func score(_ p: SIMD2<Float>, _ rf: GameCamera.RoamFloor) -> Float {
        cuts(rf)
        let rug = max(0, 1 - simd_distance(p, RoomLayout.rugCentre) / rugReach)
        let b = band(p)
        let zt = zUse.reduce(0, +), xt = xUse.reduce(0, +)
        let over = (zt > 1 ? zUse[b.z] / zt - 1 / 3 : 0) + (xt > 1 ? xUse[b.x] / xt - 1 / 3 : 0)
        return -heatAt(p) - rugWeight * rug - bandWeight * over
    }
    /// Standing emotes that are worth walking to a better place for (the in-place ones; the walkers, the reactions and the ones tied to a prop or a window stay as they are).
    static let soloKinds: Set<IdleKind> = [.jacks, .slump, .yawn, .tail, .flop, .stretch, .bounce, .sway, .sigh, .shake, .lieDown, .chirp, .hiccup, .sneeze, .dizzyWobble,
                                           .politeBow, .bellyDrum, .signatureFlourish, .proudStrut, .tailThump, .tailHug]
    /// Pair kinds that start where they are (a glance across the room, a dash) are never moved.
    static let pairStay: Set<SocialKind> = [.look, .zoomies, .greet, .bagSit]
}

/// Per brain: a solo emote waiting for its walk to the spot; seconds spent walking to the spot of the emote that just started (read and cleared by the soak harness).
struct EmoteSpotState {
    var soloKind: IdleKind?
    var soloAt: Float = 0
    var skip = false
    var walked: Float = 0
    var logT: Float = 0
}

extension BlobBrain {
    /// A pair is on its way to / waiting on its meeting spots: nothing else may take either body.
    var meetBusy: Bool { socialBook.meet != nil || socialMeetHeld }
    var emoteSpotLive: Bool { EmoteSpot.enabled && homeRoom && roamProvider != nil && autonomy }

    func emoteSpotLog(_ dt: Float) {
        emoteSpot.logT += dt
        guard emoteSpot.logT >= 1 else { return }
        emoteSpot.logT = 0
        let st: String
        if let s = social { st = (s.kind.isGroup ? "group:" : "pair:") + s.kind.rawValue }
        else if let k = idleState.kind { st = (k == .sleep || k == .sit ? "rest:" : "solo:") + k.rawValue }
        else if activity == .walking || activity == .coming { st = "walk" } else { st = "stand" }
        NSLog("[emotespot] t=%.1f id=%d x=%.2f z=%.2f %@", variety.now, steerID, px, pz, st)
    }

    func emoteNote(_ p: SIMD2<Float>) { if let rf = roamProvider?() { EmoteSpot.note(p, rf) } }

    func emoteSendWalk(to t: SIMD2<Float>) {
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
        script = .walk(target: t, then: .none); activity = .walking
    }

    /// Best of up to 40 floor points for an emote centred there: within `maxLeg` of every body in `from`, the floor rules leave it alone, `ok` agrees. nil = none beats `here` by the margin.
    func emoteBestSpot(from: [SIMD2<Float>], maxLeg: Float, here: SIMD2<Float>, ok: (SIMD2<Float>) -> Bool) -> SIMD2<Float>? {
        guard let rf = roamProvider?() else { return nil }
        let base = EmoteSpot.score(here, rf)
        var best: (SIMD2<Float>, Float)?
        for _ in 0..<40 {
            let c = rf.sampleArea(rand(), rand(), rand())
            guard rf.contains(c) else { continue }
            let leg = from.map { simd_distance($0, c) }.max() ?? 0
            guard leg <= maxLeg, leg > 0.6 else { continue }
            let s = EmoteSpot.score(c, rf) - EmoteSpot.legCost * leg
            guard s > base + EmoteSpot.margin, best == nil || s > best!.1, ok(c) else { continue }
            best = (c, s)
        }
        return best?.0
    }

    // MARK: solo

    /// idleStart's gate. True = the emote will start at its spot (he walks there first). False = start now, here (the spot is noted).
    func emoteSoloGate(_ kind: IdleKind, _ sim: SoftBody) -> Bool {
        guard emoteSpotLive, EmoteSpot.soloKinds.contains(kind), !emoteSpot.skip, social == nil, !held, !commanded, commandedIdle == nil, pending == nil, bubbleLeash == nil, !race.active else { return false }
        let here = SIMD2(px, pz)
        if let g = emoteBestSpot(from: [here], maxLeg: EmoteSpot.soloLeg, here: here, ok: { [unowned self] c in simd_distance(self.fixed(c), c) < 0.1 && self.peerFree(c) && self.reachable(here, c) }) {
            emoteSpot.soloKind = kind; emoteSpot.soloAt = variety.now
            emoteSendWalk(to: g)
            return true
        }
        emoteNote(here)
        return false
    }

    /// pickAutonomous, first thing: he has walked to the spot of a solo emote - start it.
    func emoteSoloArrived(_ sim: SoftBody) -> Bool {
        guard let k = emoteSpot.soloKind else { return false }
        emoteSpot.soloKind = nil
        guard variety.now - emoteSpot.soloAt < 14, !(anticsEnabled && BlobBrain.fastKinds.contains(k) && fastOthers() >= 2), !varietyPeerJustStarted(k) else { return false }
        emoteSpot.skip = true; defer { emoteSpot.skip = false }
        emoteNote(position)
        if idleStart(k, sim) { emoteSpot.walked = variety.now - emoteSpot.soloAt; return true }
        return false
    }

    // MARK: pair

    /// The pair's meeting: where the two stand for `kind`. If the midpoint they are at is clearly worse than another spot, both walk to it first (`socialBook.meet`), then `socialStart`
    /// runs as always. True = the meeting is on its way (the caller is done); false = start in place.
    func emoteMeetPlan(_ kind: SocialKind, with o: BlobBrain) -> Bool {
        guard emoteSpotLive, !EmoteSpot.pairStay.contains(kind), o.homeRoom, socialFree, o.socialFree else { return false }
        let a = position, b = o.position
        let mid = (a + b) / 2
        // the whole pair moves as it stands (the same shift for both: the start geometry of every kind is what it was)
        guard let m = emoteBestSpot(from: [mid], maxLeg: EmoteSpot.pairLeg, here: mid, ok: { [unowned self] c in
            let pa = a + (c - mid), pb = b + (c - mid), rf = self.roamProvider?()
            return rf?.contains(pa) == true && rf?.contains(pb) == true && simd_distance(self.fixed(pa), pa) < 0.1 && simd_distance(self.fixed(pb), pb) < 0.1 && self.peerFree(pa) && self.peerFree(pb) && self.reachable(a, pa) && self.reachable(b, pb)
        }) else { emoteNote(mid); return false }
        emoteNote(m)
        emoteSendWalk(to: a + (m - mid)); o.emoteSendWalk(to: b + (m - mid))
        socialBook.meet = (kind, o.steerID, 0)
        o.socialBook.meetHeldBy = steerID
        return true
    }

    /// Per tick while no session is on him: the meeting walk. Starts the pair the moment both stand still on their spots; dropped when somebody is taken or it takes too long.
    func socialMeetTick(_ sim: SoftBody, _ dt: Float) {
        guard var m = socialBook.meet else { return }
        m.t += dt
        socialBook.meet = m
        guard let o = socialBrain(m.id), o.social == nil, !socialTaken, !o.socialTaken, m.t < 14 else { emoteMeetEnd(); return }
        if socialFree, o.socialFree {
            let t = m.t
            emoteMeetEnd()
            emoteSpot.walked = t
            if !socialStart(m.kind, with: o, sim) { socialBook.cooldown = max(socialBook.cooldown, 5); emoteSpot.walked = 0 }
        }
    }
    func emoteMeetEnd() {
        if let m = socialBook.meet, let o = socialBrain(m.id) { o.socialBook.meetHeldBy = -1 }
        socialBook.meet = nil
    }
    /// The partner of a meeting stands and waits on his spot (nothing new starts) while the meeting runs.
    var socialMeetHeld: Bool {
        guard socialBook.meetHeldBy >= 0 else { return false }
        if let i = socialBrain(socialBook.meetHeldBy), let m = i.socialBook.meet, m.id == steerID { return true }
        socialBook.meetHeldBy = -1
        return false
    }

    // MARK: group

    /// The ring centre of a group: a spot every member can walk to (the ring plan checks the legs and the floor), clearly better than the centroid they stand round. nil = the centroid.
    func emoteGroupCentre(_ crew: [BlobBrain], here: SIMD2<Float>) -> SIMD2<Float>? {
        guard emoteSpotLive, crew.allSatisfy({ $0.homeRoom }) else { return nil }
        if let c = emoteBestSpot(from: crew.map(\.position), maxLeg: EmoteSpot.pairLeg, here: here, ok: { _ in true }) { emoteNote(c); return c }
        emoteNote(here)
        return nil
    }
}
