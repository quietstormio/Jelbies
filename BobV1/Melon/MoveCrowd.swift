//
//  MoveCrowd.swift
//  move-crowd-r1 (owner 11-24: "The collisions and crowding is killing the game"). Fewer bumps BY CONSTRUCTION for free, autonomous walkers (no job, no command, no social, no choreography).
//  ONE master switch: `MoveCrowd.on` (DevArgs `-MoveCrowd 0` or env MOVECROWD=0 = exactly the old steering). Parts, each its own sub-switch (env MOVECROWD_OFF=part,goal,... turns parts off
//  for a measurement; every number below has an env seam so a headless iteration needs no rebuild):
//    gap    one constant `gap` (1.45, just outside the 1.4 push radius) for the look-ahead trigger and the detour point (each walker clears the other's predicted spot by it alone)
//    goal   a roam goal is rejected if another body stands within `gap` of it or is walking to a spot within `gap` of it
//    yield  symmetric give-way: the one who is slower to the meeting / has less far to go waits (was always the lower id)
//    look   a walker on a waypoint leg looks ahead too
//    part   after a pair / group moment the members leave to different sides, staggered
//  The gait and the run are untouched (heading, route and start / stop timing only).
//

import Foundation
import simd

nonisolated enum MoveCrowd {
    private static let env = ProcessInfo.processInfo.environment
    private static func master() -> Bool {
        if let e = env["MOVECROWD"] { return e != "0" }
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: "MoveCrowd") else { return defaultOn }
        return !["0", "no", "false", "old", "off"].contains(v.lowercased())
    }
    static let defaultOn = true          // (`-MoveCrowd 0` / MOVECROWD=0 = the old steering)
    nonisolated(unsafe) static var on: Bool = master()
    private static let offParts = Set((env["MOVECROWD_OFF"] ?? "").split(separator: ",").map { String($0) })
    private static func part(_ k: String) -> Bool { !offParts.contains(k) }
    nonisolated(unsafe) static var gapOn = part("gap")
    nonisolated(unsafe) static var goalOn = part("goal")
    nonisolated(unsafe) static var yieldOn = part("yield")
    nonisolated(unsafe) static var lookOn = part("look")
    nonisolated(unsafe) static var partOn = part("part")
    /// speed is OFF by default (iteration 2: the real-speed look-ahead fired more often and raised hard stops ~70% at home); env MOVECROWD_ON=speed turns it on.
    nonisolated(unsafe) static var speedOn = (env["MOVECROWD_ON"] ?? "").contains("speed") && part("speed")
    nonisolated(unsafe) static var allOn = part("all")
    nonisolated(unsafe) static var legOn = part("leg")
    nonisolated(unsafe) static var spotOn = part("spot")
    /// reqcurve: a come / goTo walk (café customers, the Show line, the groomer, park calls; never a meal) curves round its route corners like a free walk (it used to stop and turn at every corner over 29 degrees).
    /// OFF by default (café landscape table 0, two 150 s takes each way: corner stops of the customers 16 -> 23, not fewer; the clearance rule refuses most corners beside seated bodies): env MOVECROWD_ON=reqcurve turns it on.
    nonisolated(unsafe) static var reqCurveOn = (env["MOVECROWD_ON"] ?? "").contains("reqcurve") && part("reqcurve")
    private static func num(_ k: String, _ d: Float) -> Float { Float(env[k] ?? "") ?? d }

    /// The one clearance (u, centre to centre): trigger, detour offset, goal rejection.
    nonisolated(unsafe) static var gap = num("MOVECROWD_GAP", 1.45)

    static var text: String { "MoveCrowd on=\(on) gap=\(gapOn) goal=\(goalOn) yield=\(yieldOn) look=\(lookOn) part=\(partOn) speed=\(speedOn) all=\(allOn) leg=\(legOn) spot=\(spotOn) reqcurve=\(reqCurveOn) gapU=\(gap)" }
}

/// Read by the scoreboard (tests): the switches as they stand.
enum MoveCrowdInfo { static var text: String { MoveCrowd.text } }

struct CrowdBook {
    var lookClock: Float = -10
}

extension MoveCrowd {
    /// part: the extra wait (s) per earlier-leaving mate after a moment, and the least angle between two strollers' directions (cos: below this).
    nonisolated(unsafe) static var partStagger = num("MOVECROWD_PART_STAGGER", 1.0)
    nonisolated(unsafe) static var partSplitCos = num("MOVECROWD_PART_SPLIT", -0.2)
    /// look: how often (s) a walker on a waypoint leg looks ahead.
    nonisolated(unsafe) static var lookEvery = num("MOVECROWD_LOOK_EVERY", 0.5)
    /// yield: the head-on walker with the right of way still veers by this share of `gap` to his right (the other clears by the whole gap alone).
    nonisolated(unsafe) static var headOnKeep = num("MOVECROWD_HEADON_KEEP", 0.25)
}

extension BlobBrain {
    /// A free, autonomous walker at home or on a park visit (no job, no command, no social, no toy / ball game, no race): the only bodies MoveCrowd steers.
    /// Meals never qualify (`homeRoom` is false while the tray is out), nor the café, the Show, the race or any choreographed walk.
    var crowdLive: Bool {
        MoveCrowd.on && (homeRoom || outingPlay) && roomFree && social == nil && !race.active && !volley.active && toy.waitUID < 0 && toy.chaseSpot == nil && bubbleLeash == nil && !tossBusy
    }
    /// goal: nobody stands within `gap` of the spot, and nobody is walking to a spot within `gap` of it.
    func crowdGoalFree(_ p: SIMD2<Float>) -> Bool {
        let g = MoveCrowd.gap
        for o in socialOthers() where o !== self {
            if simd_distance(o.position, p) < g { return false }
            if case .walk(let t, _) = o.script, simd_distance(t, p) < g { return false }
        }
        return true
    }
    /// yield: at a crossing, do I give way? The one who reaches the meeting second gives way (`roomAhead`); too close to call: the one with less far to go; then the lower id.
    func crowdGiveWay(his id: Int, at pos: SIMD2<Float>, vel: SIMD2<Float>, root: SIMD2<Float>, dir: SIMD2<Float>, vSelf: Float, myLeft: Float) -> Bool {
        let s = roomAhead(of: id, at: pos, vel: vel, root: root, dir: dir, vSelf: vSelf)
        if abs(s) > RoomTraffic.tieBand { return s > 0 }
        if let o = socialBrain(id), case .walk(let t, _) = o.script {
            let hisLeft = simd_distance(t, pos)
            if abs(hisLeft - myLeft) > 0.5 { return myLeft < hisLeft }
        }
        return steerID < id
    }
}

extension BlobBrain {
    /// look (from `steerTarget` while a waypoint is ahead): every `lookEvery` s the leg to the waypoint is looked at like a plain leg. nil = carry on to the waypoint;
    /// .some(nil) = stand this beat (give way); .some(w2) = a detour point put in front of the waypoint.
    func crowdWaypointLook(_ root: SIMD2<Float>, _ w: SIMD2<Float>) -> SIMD2<Float>?? {
        guard MoveCrowd.lookOn, crowdLive else { return nil }
        if yieldT > 0 {          // (already giving way on this leg: keep asking every step until clear)
        } else { guard peerClock - crowd.lookClock >= MoveCrowd.lookEvery else { return nil } }
        crowd.lookClock = peerClock
        switch lookAhead(root, w) {
        case .via(let w2):
            guard route.count < 4, simd_distance(w2, w) > 0.3 else { return nil }
            route.insert(w2, at: 0)
            return .some(w2)
        case .wait: return .some(nil)
        case .clear: return nil
        }
    }
}

extension BlobBrain {
    /// all: a detour point `w` is at least `gap` x 0.9 from every other body (but `except`, the one being passed), at its position now and where it will be when I get to `w`.
    func crowdDetourFree(_ w: SIMD2<Float>, root: SIMD2<Float>, vSelf: Float, except: Int) -> Bool {
        let t = min(simd_distance(root, w) / max(vSelf, 0.3), ContactTuning.lookTime)
        let r = MoveCrowd.gap * 0.9
        for p in steerPeers() where p.id != except {
            if simd_distance(p.pos, w) < r { return false }
            if p.id < Int.max / 4, let v = peerVel[p.id], simd_distance(p.pos + v * t, w) < r { return false }
        }
        return true
    }
}

extension BlobBrain {
    /// leg: my straight leg here -> cand, walked at my speed, keeps `gap` from every other body: a walker along its route and goal at its speed, a stander where he stands
    /// (pairs already closer than the gap at the start only must not get closer).
    func crowdLegFree(from here: SIMD2<Float>, to cand: SIMD2<Float>) -> Bool {
        let g = MoveCrowd.gap, L = simd_distance(here, cand), v = max(roomNominalWalk, 0.3)
        guard L > 0.05 else { return true }
        let T = L / v
        for o in socialOthers() where o !== self {
            var pts = [o.position]
            var ov: Float = 0
            if case .walk(let goal, _) = o.script { pts += o.steerRoute; pts.append(goal); ov = max(o.roomWalkSpeed, 0.3) }
            let d0 = simd_distance(here, o.position)
            var t: Float = 0.2
            while t <= T + 0.01 {
                let a = here + (cand - here) * min(1, t / T)
                var b = pts[0], left = ov * t
                if ov > 0 { for k in 1..<pts.count { let seg = simd_distance(pts[k - 1], pts[k]); if left <= seg { b = pts[k - 1] + (pts[k] - pts[k - 1]) * (seg > 1e-4 ? left / seg : 0); break }; left -= seg; b = pts[k] } }
                let dd = simd_distance(a, b)
                if dd < g && dd < d0 - 0.05 { return false }
                t += 0.2
            }
        }
        return true
    }
}

extension BlobBrain {
    /// The stand-off fix (the requested walk's standing patience is not reset while a peer holds the leg) applies to come / goTo / commanded walks only, never to a meal, drink or dining walk.
    var crowdStandOffKeep: Bool {
        switch job {
        case .eat?, .drink?, .dine?, .sip?: return false
        default: return true
        }
    }
}

extension BlobBrain {
    /// reqcurve: this body serves a come / goTo request (never eat / drink / dine / sip).
    var crowdCurveRequested: Bool {
        guard MoveCrowd.on, MoveCrowd.reqCurveOn else { return false }
        switch job {
        case .goTo?, .come?: return true
        default: return false
        }
    }
    /// The shortcut root -> aim keeps from every other body at least the smaller of the gap and what the routed corner (root -> corner -> next) keeps.
    func crowdCornerClear(_ root: SIMD2<Float>, aim: SIMD2<Float>, corner: SIMD2<Float>, next: SIMD2<Float>) -> Bool {
        func segD(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            let ab = b - a, l2 = simd_dot(ab, ab)
            let t = l2 > 1e-6 ? min(max(simd_dot(p - a, ab) / l2, 0), 1) : 0
            return simd_distance(p, a + ab * t)
        }
        for o in socialOthers() where o !== self {
            let p = o.position
            let routed = min(segD(p, root, corner), segD(p, corner, next))
            if segD(p, root, aim) < min(MoveCrowd.gap, routed) - 0.02 { return false }
        }
        return true
    }
}
