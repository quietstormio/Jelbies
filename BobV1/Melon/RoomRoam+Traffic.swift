import Foundation
import simd

/// Step 1 of the home room round (2026-11-15; the user: "stop running into each other so much"). Live only where `roomTraffic` says so (RoomRoam.swift): a free body
/// in the home room that is not in a social session. `-RoomTraffic 0` gives the steering from before the round.
///  T1  the look-ahead predicts with the speed he really walks at (a room walk is about 1.44 u/s, a dash about 1.8; `ContactTuning.walkerSpeed` is 0.8);
///  T2  at a crossing the one who gets there SECOND gives way and passes BEHIND the other (before: always the lower id, to the side away from the other);
///  T5  on a waypoint leg (where nothing looked ahead) the one who gets there second stands a beat, at most `waitMax` s per waypoint;
///  T6  a wander goal whose leg would meet another's leg in space and time scores lower; such a dash goal is skipped;
///  T7  one alone at home roams the whole visible floor from launch (before: the old box until his first trip out); the stage's `syncRoam` reads `loneFloorLive`;
///  T8  one alone picks fewer wander goals in the far back (the pockets beside the sofa, where he reads tiny): a candidate behind `loneBackFrom` is dropped with a
///      chance that grows to `loneBackChance` at `loneBackFull`.
/// T7 and T8 (one alone) are ON by default; `-RoomTrafficLone 0` / `-RoomTrafficLoneBack 0` (dev builds) or the environment `ROOMTRAFFIC_OFF=lone,loneback` turn them off.
/// T1, T2, T5 and T6 (two or more bodies) are OPT-IN, OFF by default, until their own proof with three bodies: with them off, two or more bodies steer and pick goals
/// exactly as before the round. `-RoomTrafficSpeed 1`, `-RoomTrafficOrder 1`, `-RoomTrafficWait 1`, `-RoomTrafficGoals 1` (dev builds) or, in a headless run, the
/// environment `ROOMTRAFFIC_ON=speed,order,wait,goals` turn parts on; `ROOMTRAFFIC_OFF` wins over both. The numbers have environment seams for the measuring test only.
/// Remedy D1 (ON by default): after a floor change (a rotation) the stage's `syncRoam` sends every free home body that stands outside the new floor on a walk to the
/// nearest floor spot (`BlobBrain.roomWalkIn`, at the end of this file). `-RoomTrafficWalkIn 0` (dev builds) or `ROOMTRAFFIC_OFF=walkin` turn it off.
nonisolated enum RoomTraffic {
    private static func devOn(_ key: String) -> Bool {
        !(DevArgs.enabled && UserDefaults.standard.object(forKey: key) != nil && UserDefaults.standard.integer(forKey: key) == 0)
    }
    /// An opt-in part: on only when a dev argument asks for it (`-<key> 1`; `DevArgs.enabled` builds only).
    private static func devAsked(_ key: String) -> Bool {
        DevArgs.enabled && UserDefaults.standard.integer(forKey: key) == 1
    }
    private static let envOff = Set((ProcessInfo.processInfo.environment["ROOMTRAFFIC_OFF"] ?? "").split(separator: ",").map { String($0) })
    private static let envOn = Set((ProcessInfo.processInfo.environment["ROOMTRAFFIC_ON"] ?? "").split(separator: ",").map { String($0) })
    private static func env(_ name: String, _ fallback: Float) -> Float { Float(ProcessInfo.processInfo.environment[name] ?? "") ?? fallback }

    nonisolated(unsafe) static var realSpeed = (devAsked("RoomTrafficSpeed") || envOn.contains("speed")) && !envOff.contains("speed")          // (T1, opt-in: off by default)
    nonisolated(unsafe) static var arrivalOrder = (devAsked("RoomTrafficOrder") || envOn.contains("order")) && !envOff.contains("order")          // (T2, opt-in)
    nonisolated(unsafe) static var waypointWait = (devAsked("RoomTrafficWait") || envOn.contains("wait")) && !envOff.contains("wait")          // (T5, opt-in)
    nonisolated(unsafe) static var goalAware = (devAsked("RoomTrafficGoals") || envOn.contains("goals")) && !envOff.contains("goals")          // (T6, opt-in)
    nonisolated(unsafe) static var loneFloor = devOn("RoomTrafficLone") && !envOff.contains("lone")
    nonisolated(unsafe) static var loneBack = devOn("RoomTrafficLoneBack") && !envOff.contains("loneback")
    nonisolated(unsafe) static var walkIn = devOn("RoomTrafficWalkIn") && !envOff.contains("walkin")          // (remedy D1: on by default)
    /// T7, read by the stage every frame: one alone at home gets the roaming floor too.
    static var loneFloorLive: Bool { RoomRoam.traffic && loneFloor }

    nonisolated(unsafe) static var speedMul = env("ROOMTRAFFIC_SPEED_MUL", 1.0)          // x his computed speed
    nonisolated(unsafe) static var dashMul = env("ROOMTRAFFIC_DASH_MUL", 1.27)          // a dash against a plain room walk
    nonisolated(unsafe) static var tieBand = env("ROOMTRAFFIC_TIE", 0.3)          // |roomAhead| below this = too close to call (u * u/s)
    nonisolated(unsafe) static var waitMax = env("ROOMTRAFFIC_WAIT_MAX", 0.5)          // s stood per waypoint
    nonisolated(unsafe) static var waitNear = env("ROOMTRAFFIC_WAIT_NEAR", 0.78)          // x peerGap: closer than this = stand
    nonisolated(unsafe) static var waitTime = env("ROOMTRAFFIC_WAIT_TIME", 0.9)          // s looked ahead on a waypoint leg
    nonisolated(unsafe) static var goalPenalty = env("ROOMTRAFFIC_GOAL_PENALTY", 3.0)
    nonisolated(unsafe) static var goalNear = env("ROOMTRAFFIC_GOAL_NEAR", 0.85)          // x peerGap: the whole penalty below
    nonisolated(unsafe) static var goalFar = env("ROOMTRAFFIC_GOAL_FAR", 1.2)          // x peerGap: none above
    nonisolated(unsafe) static var dashTries = Int(env("ROOMTRAFFIC_DASH_TRIES", 60))
    nonisolated(unsafe) static var loneBackChance = env("ROOMTRAFFIC_LONE_BACK", 0.85)          // the drop chance at `loneBackFull` and behind it
    nonisolated(unsafe) static var loneBackFrom = env("ROOMTRAFFIC_LONE_BACK_FROM", -2.6)          // z: nothing is dropped in front of this
    nonisolated(unsafe) static var loneBackFull = env("ROOMTRAFFIC_LONE_BACK_FULL", -3.4)          // z: the whole chance from here back
    nonisolated(unsafe) static var walkInMin = env("ROOMTRAFFIC_WALKIN_MIN", 0.3)          // D1: a body nearer than this to the floor's outline is left alone
    nonisolated(unsafe) static var walkInInset = env("ROOMTRAFFIC_WALKIN_INSET", 0.2)          // D1: the spot he is sent to lies this far inside the floor's edge

    /// T5's wait budget by `steerID`: the waypoint it belongs to, and the seconds already stood for it.
    nonisolated(unsafe) static var waitFor: [Int: SIMD2<Float>] = [:]
    nonisolated(unsafe) static var waited: [Int: Float] = [:]
    /// What ran: 0 crossing ticks where I gave way, 1 where I walked on, 2 ticks stood on a waypoint leg, 3 wander candidates marked down, 4 dash candidates skipped, 5 wander candidates of one alone dropped in the far back.
    nonisolated(unsafe) static var counts = [0, 0, 0, 0, 0, 0]
    /// D1: the walks sent since launch.
    nonisolated(unsafe) static var walkIns = 0
    /// T8: true = drop this wander candidate of one alone (`u` = one number 0..<1 from the brain's own generator).
    static func loneBackDrop(_ z: Float, _ u: Float) -> Bool {
        guard z < loneBackFrom else { return false }
        guard u < loneBackChance * min(1, (loneBackFrom - z) / max(loneBackFrom - loneBackFull, 0.01)) else { return false }
        counts[5] += 1
        return true
    }
    static var report: String { "roomtraffic giveWay=\(counts[0]) walkOn=\(counts[1]) waitTicks=\(counts[2]) wanderMarked=\(counts[3]) dashSkipped=\(counts[4]) loneBack=\(counts[5])" }
}

extension BlobBrain {
    /// T8 is live for this body. (No gate count of its own: `pickRoamGoal` reads `roomTraffic` once per pick already.)
    var roomLoneBack: Bool { RoomTraffic.loneBack && homeRoom && RoomRoam.traffic && roomFree && social == nil }

    /// T1: what the walk really moves him by right now (u/s): stride x cadence with the run / boost / free-locomotion factors of the moment.
    var roomWalkSpeed: Float {
        min(max(stride * runStrideMul * stepRate * runRateMul * locoRateMul * RoomTraffic.speedMul, ContactTuning.walkerSpeed), 2.4)
    }
    /// The speed of a plain room walk, for a leg that has not begun yet (T6).
    var roomNominalWalk: Float { stride * stepRate * Self.locoRate * Self.walkBoost * RoomTraffic.speedMul }

    /// > 0: when the two of us are closest, he is ahead of me (he gets to the crossing first). The other brain computes the same number with the opposite sign,
    /// because my own velocity is taken the way HE measures it (`peerVel` of his brain): exactly one of the two gives way. Near 0 (`tieBand`) = too close to call.
    func roomAhead(of id: Int, at pos: SIMD2<Float>, vel: SIMD2<Float>, root: SIMD2<Float>, dir: SIMD2<Float>, vSelf: Float) -> Float {
        let seen = socialBrain(id)?.peerVel[steerID] ?? .zero
        let vMe = simd_length(seen) > 0.18 ? seen : dir * vSelf
        let rel = pos - root, vrel = vMe - vel
        let vv = simd_dot(vrel, vrel)
        guard vv > 1e-3 else { return 0 }
        let tc = min(max(simd_dot(rel, vrel) / vv, 0), ContactTuning.lookTime)
        return simd_dot(rel - vrel * tc, vMe + vel)          // (from me to him at the closest moment) . (both velocities)
    }

    /// T2 (from `lookAhead`, a walking hit): at a crossing, who gives way and - when it is me - the side (+1 my right, -1 my left) that takes me BEHIND him.
    func roomCross(idYield: Bool, cosA: Float, his id: Int, at pos: SIMD2<Float>, vel: SIMD2<Float>, root: SIMD2<Float>, dir: SIMD2<Float>, right: SIMD2<Float>, vSelf: Float) -> (Bool, Float?) {
        guard RoomTraffic.arrivalOrder, abs(cosA) < 0.6 else { return (idYield, nil) }
        let s = roomAhead(of: id, at: pos, vel: vel, root: root, dir: dir, vSelf: vSelf)
        let giveWay = abs(s) > RoomTraffic.tieBand ? s > 0 : idYield
        RoomTraffic.counts[giveWay ? 0 : 1] += 1
        return (giveWay, giveWay ? (simd_dot(vel, right) > 0 ? -1 : 1) : nil)
    }

    /// T5 (from `steerTarget` while a waypoint is ahead): true = stand this tick. Only for a CROSSING walker who is ahead of me at the closest moment
    /// (head on both would stand; a standing body is `legClear`'s business), and for at most `waitMax` s per waypoint.
    func roomWaypointWait(_ root: SIMD2<Float>, _ w: SIMD2<Float>) -> Bool {
        guard RoomTraffic.waypointWait, roomTraffic else { return false }
        let d = w - root, L = simd_length(d)
        guard L > 0.05 else { return false }
        if RoomTraffic.waitFor[steerID].map({ simd_distance($0, w) < 0.05 }) != true { RoomTraffic.waitFor[steerID] = w; RoomTraffic.waited[steerID] = 0 }
        guard RoomTraffic.waited[steerID, default: 0] < RoomTraffic.waitMax else { return false }
        let dir = d / L, vSelf = roomWalkSpeed
        let horizon = min(L / vSelf, RoomTraffic.waitTime)
        for p in steerPeers() where p.id < Int.max / 4 {
            let vel = peerVel[p.id] ?? .zero, speed = simd_length(vel)
            guard speed > 0.18, abs(simd_dot(dir, vel / speed)) < 0.6 else { continue }
            let rel = p.pos - root, vrel = dir * vSelf - vel
            let vv = simd_dot(vrel, vrel), closing = simd_dot(rel, vrel)
            guard vv > 1e-3, closing > 0.05 else { continue }
            let tc = min(closing / vv, horizon)
            guard simd_length(rel - vrel * tc) < peerGap * RoomTraffic.waitNear else { continue }
            let s = roomAhead(of: p.id, at: p.pos, vel: vel, root: root, dir: dir, vSelf: vSelf)
            guard s > RoomTraffic.tieBand || (abs(s) <= RoomTraffic.tieBand && steerID < p.id) else { continue }
            RoomTraffic.waited[steerID, default: 0] += runDt
            RoomTraffic.counts[2] += 1
            return true
        }
        return false
    }

    /// T6: how much the leg `here -> cand`, begun now at `speed`, would get in the way of the legs the others are walking right now
    /// (0 = not at all ... `goalPenalty` = they would touch). Both bodies are stepped along their legs in 0.15 s samples; one that has arrived stands at its goal.
    /// Only an approach counts (a sample closer than the two are now), so a walker who is already near does not mark every candidate down.
    func roomLegConflict(from here: SIMD2<Float>, to cand: SIMD2<Float>, speed: Float, others: [BlobBrain], dash: Bool) -> Float {
        let L = simd_distance(here, cand)
        guard L > 0.05, speed > 0.1 else { return 0 }
        let T = L / speed
        var closest = Float.greatestFiniteMagnitude
        for o in others {
            guard case .walk(let goal, _) = o.script else { continue }
            let from = o.position, oT = simd_distance(from, goal) / max(o.roomWalkSpeed, 0.1), d0 = simd_distance(here, from)
            var t: Float = 0.15
            while t <= T {
                let a = here + (cand - here) * (t / T)
                let b = oT > 0.01 ? from + (goal - from) * min(1, t / oT) : goal
                let dd = simd_distance(a, b)
                if dd < d0 - 0.1 { closest = min(closest, dd) }
                t += 0.15
            }
        }
        let near = peerGap * RoomTraffic.goalNear, far = peerGap * RoomTraffic.goalFar
        guard closest < far else { return 0 }
        RoomTraffic.counts[dash ? 4 : 3] += 1
        return RoomTraffic.goalPenalty * min(1, (far - closest) / max(far - near, 0.01))
    }
}

// MARK: Remedy D1 (2026-11-15): a free home body the new floor leaves outside walks back in

extension GameCamera.RoamFloor {
    /// A floor point near `p`: z brought into the rows, then x into that row, `inset` inside every edge. Rows only (the OUTLINE): the furniture is the brain's
    /// `fixed` business. A point that is already that far inside comes back unchanged.
    func nearestSpot(to p: SIMD2<Float>, inset: Float = 0) -> SIMD2<Float> {
        guard !zs.isEmpty, p.x.isFinite, p.y.isFinite else { return p }
        let lo = minZ + inset, hi = maxZ - inset
        let z = lo <= hi ? min(max(p.y, lo), hi) : (minZ + maxZ) / 2
        let h = max(halfWidth(at: z) - inset, 0)
        return SIMD2(min(max(p.x, -h), h), z)
    }
}

extension BlobBrain {
    /// D1: how far this body stands outside the floor's outline (0 = on it).
    func roomOutside(_ floor: GameCamera.RoamFloor) -> Float { simd_distance(position, floor.nearestSpot(to: position)) }

    /// D1: this body may be sent back onto the floor right now. Nothing owns it (`roomFree`), it is at home, it is not in a social session, an idle, a race, a
    /// volleyball game or a toy / bubble game, it is standing (resting, looking around or stepping in place) and it is more than `walkInMin` outside the floor.
    func roomWalkInWanted(_ floor: GameCamera.RoamFloor) -> Bool {
        guard enabled, homeRoom, roomFree, social == nil, idleState.kind == nil, !race.active, !volley.active,
              bubbleLeash == nil, toy.waitUID < 0, toy.chaseSpot == nil else { return false }
        switch script { case .none, .look, .stepInPlace: break; default: return false }
        guard activity == .idle || activity == .lookingAround || activity == .steppingInPlace else { return false }
        return roomOutside(floor) > RoomTraffic.walkInMin
    }

    /// D1: where this body goes. The floor point nearest to it, `walkInInset` inside the edge; when another body stands on that point, walks to it or was just
    /// given it (`taken`, within a body's width), the free point nearest to this body on a ring around it.
    func roomWalkInSpot(_ floor: GameCamera.RoamFloor, taken: [SIMD2<Float>]) -> SIMD2<Float> {
        let plain = fixed(floor.nearestSpot(to: position, inset: RoomTraffic.walkInInset))
        let gap = peerGap * 1.05
        func clear(_ c: SIMD2<Float>) -> Bool { !taken.contains(where: { simd_distance($0, c) < gap }) }
        if clear(plain) { return plain }
        for ring in [peerGap * 1.15, peerGap * 1.45] {
            var best: SIMD2<Float>?
            for k in 0..<12 {
                let a = Float(k) * Float.pi / 6
                let c = plain + SIMD2<Float>(sinf(a), cosf(a)) * ring
                guard floor.contains(c), simd_distance(fixed(c), c) < 0.05, clear(c) else { continue }
                if best.map({ simd_distance($0, position) <= simd_distance(c, position) }) != true { best = c }
            }
            if let best { return best }
        }
        return plain
    }

    /// D1 (the stage's `syncRoam`, right after the wall step of a floor change): every body that `roomWalkInWanted` gets a walk to its `roomWalkInSpot`, the one
    /// nearest to the floor first, so no two are sent to one spot. One shot per floor change: a body that is busy at that moment comes in with its own next walk.
    /// Returns how many were sent.
    @discardableResult
    static func roomWalkIn(_ brains: [BlobBrain?]) -> Int {
        guard RoomTraffic.walkIn, RoomRoam.traffic, let floor = GameCamera.roamFloor else { return 0 }
        let all = brains.compactMap { $0 }.filter { $0.enabled }
        let todo = all.filter { $0.roomWalkInWanted(floor) }.sorted { l, r in
            let dl = l.roomOutside(floor), dr = r.roomOutside(floor)
            return dl != dr ? dl < dr : l.steerID < r.steerID
        }
        var given: [SIMD2<Float>] = []
        for b in todo {
            var taken = given
            for o in all where o !== b {
                taken.append(o.position)
                if case .walk(let goal, _) = o.script { taken.append(goal) }
            }
            let to = b.roomWalkInSpot(floor, taken: taken)
            b.requestNow(.goTo(to))
            RoomTraffic.walkIns += 1
            given.append(to)
        }
        return todo.count
    }
}
