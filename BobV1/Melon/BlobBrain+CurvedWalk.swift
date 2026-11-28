//
//  BlobBrain+CurvedWalk.swift
//  curved-walk-r1: a walking Jelmiko BENDS into a new direction instead of stopping to turn on the spot. Two cases, both in `planWalkStep`:
//   1. a routed walk aims at a point about 0.9 u ahead ON ITS ROUTE (not at the next waypoint), so the corner is rounded at a walk;
//   2. a walk re-aimed while walking by 0.5 ... 2.4 rad arcs into the new direction (the old arc covered only a final target up to 1.2 rad).
//  Every curved step is one of the gait's own steps planned between footfalls: the heading turns by at most the gait's own turn per step (`m`), the step is the gait's shortened arc step (0.6), the body travels
//  along the heading it turns through (heading within about 13 degrees of the travel direction), and the landing must be free floor (the `fixed` rules) and not pushed by a body (`resolve`), otherwise the old
//  stop and turn stays. Not for: stance walks, meal walks, a walk that starts from a stand, toy / race / ball / soccer bodies, sessions. Switch: `-CurvedWalk 0` (DevArgs) / env CURVEDWALK=0 = the old walk.
//

import Foundation
import simd

extension BlobBrain {
    nonisolated(unsafe) static var curvedWalk: Bool = {
        if let e = ProcessInfo.processInfo.environment["CURVEDWALK"] { return e != "0" }
        if DevArgs.enabled, UserDefaults.standard.object(forKey: "CurvedWalk") != nil { return UserDefaults.standard.integer(forKey: "CurvedWalk") != 0 }
        return curvedWalkDefault
    }()
    /// SHIPPING DEFAULT (set by the real-app gate; see the hand-back).
    static let curvedWalkDefault = true          // (SHIPPED ON, Main's decision after the real-app gate; `-CurvedWalk 0` / env CURVEDWALK=0 = the old walk)
    static let curveMaxErr: Float = 2.4
    nonisolated(unsafe) static var curveCounts = [0, 0]          // (test seam: curved steps planned, spot turns while moving)
    static let curveAhead: [Float] = [0.9, 0.6]

    /// A free, autonomous or requested ordinary walk that is already moving (the first step of a walk from a stand is the old turn, then walk).
    var curveBody: Bool {
        guard Self.curvedWalk, enabled, !heldBase, social == nil || social?.kind == .follow, bubbleLeash == nil, !race.active, !volley.active, toy.waitUID < 0, toy.chaseSpot == nil,
              mealFinalYaw == nil, job == nil || crowdCurveRequested, playChase == 0, !tossBusy, !stanceStepFree, !ContactTouchMemory.exact.contains(steerID), peerClock - lastTranslateClock < 0.5 else { return false }
        switch job { case .some(.dine), .some(.sip): return false; default: break }
        switch idleState.kind {
        case nil, .some(.wander), .some(.run): return true
        case .some(.trot): return true          // (a trot and the walk to a window are plain walks to a point)
        case .some(let k): if idleState.windowGo, k != .soccerKick { return true }
            return k != .soccerKick && Self.decorKinds.contains(k) && idleState.decorGo          // (the walk to a piece of decor: a plain walk to a stand; the emote itself is not touched)
        }
    }

    /// The bend of the next step toward a direction `err` off the heading: the travel direction (through half the turn) and the heading change, or nil when the turn would not land on free floor.
    func curvedBend(_ root: SIMD2<Float>, _ err: Float, dist D: Float) -> (u: SIMD2<Float>, dy: Float)? {
        let m = turnRate * min(max(amplitude, 0.5), 1) * feet.stepTime
        let dy = (err < 0 ? -1 : 1) * min(abs(err), m)
        let th = yaw + dy * 0.5
        let u = SIMD2<Float>(sinf(th), cosf(th))
        let stance = 1 - nextSwing
        let s = simd_dot(feet.pos[stance] - (root + rotXZ(geom.off[stance], yaw)), u)
        let L = stride * runStrideMul * min(max(amplitude, 0.6), 1) * 0.6          // (the gait's own shortened arc step)
        let cand = root + u * (s + 0.5 * L)
        // the turn circle (radius = the step's travel / the heading change per step): a target inside it would be orbited, so the old stop and turn
        let R = max(s + 0.5 * L, 0.5 * L) / max(abs(dy), 0.05)
        let lat = D * sinf(abs(err)), fwd = D * cosf(abs(err))
        if simd_length(SIMD2(lat - R, fwd)) < R * 1.05 { return nil }
        let a0 = simd_distance(fixed(root), root)
        for f: Float in [0.5, 1.0] {
            let p = root + (cand - root) * f
            if simd_distance(fixed(p), p) > max(0.012, a0 + 0.004) { return nil }
        }
        let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint)
        if simd_distance(SIMD2(rv.x, rv.z), cand) > 0.01 { return nil }          // (a body would push the landing: the old way)
        return (u, dy)
    }

    /// The point `ahead` along the polyline root -> route waypoints -> the walk's target.
    private func routePoint(_ root: SIMD2<Float>, _ pts: [SIMD2<Float>], ahead: Float) -> SIMD2<Float> {
        var left = ahead, p = root
        for q in pts {
            let d = simd_distance(p, q)
            if d >= left { return d > 1e-5 ? p + (q - p) / d * left : q }
            left -= d; p = q
        }
        return p
    }

    /// Where a routed walk aims this step: the waypoint itself, or (when the bend toward a point ahead on the route lands on free floor) that point, which rounds the corner.
    func curveAim(_ root: SIMD2<Float>, _ eff: SIMD2<Float>) -> SIMD2<Float> {
        guard route.first == eff, case .walk(let tgt, _) = script, simd_distance(root, eff) < Self.curveAhead[0] else { return eff }
        let pts = route + [tgt]
        for la in Self.curveAhead {
            let aim = routePoint(root, pts, ahead: la)
            if simd_distance(aim, eff) < 0.05 { return eff }
            let d = aim - root
            guard simd_length(d) > 0.4 else { continue }
            let err = wrapAngle(atan2f(d.x, d.y) - yaw)
            if job != nil, !crowdCornerClear(root, aim: aim, corner: eff, next: pts.count > 1 ? pts[1] : tgt) { continue }          // (move-crowd-r1: a requested walk rounds a corner only where it comes no nearer to a body than the routed corner does, never under the gap)
            if abs(err) <= 0.5 {
                if curveStraightFree(root, d) { return aim }
            } else if abs(err) <= Self.curveMaxErr, !(simd_length(d) < 0.6 && abs(err) > 1.2), curvedBend(root, err, dist: simd_length(d)) != nil { return aim }
        }
        return eff
    }

    /// A step straight along `d` lands on free floor (no body pushes it).
    private func curveStraightFree(_ root: SIMD2<Float>, _ d: SIMD2<Float>) -> Bool {
        let u = d / simd_length(d)
        let stance = 1 - nextSwing
        let s = simd_dot(feet.pos[stance] - (root + rotXZ(geom.off[stance], yaw)), u)
        let cand = root + u * (s + 0.5 * stride * runStrideMul * min(max(amplitude, 0.6), 1))
        let a0 = simd_distance(fixed(root), root)
        if simd_distance(fixed(cand), cand) > max(0.012, a0 + 0.004) { return false }
        let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint)
        return simd_distance(SIMD2(rv.x, rv.z), cand) <= 0.01
    }

    // MARK: log only (console, `-EmoteLog 1`)

    /// What kind of walk this is (for the measurement of the stops).
    var curveKind: String {
        if ContactTouchMemory.exact.contains(steerID) || stanceStepFree { return "stance" }
        if mealFinalYaw != nil { return "meal" }
        switch job { case .some(.dine), .some(.sip): return "meal"; default: break }
        if race.active || volley.active || toy.waitUID >= 0 || toy.chaseSpot != nil || bubbleLeash != nil { return "toy" }
        if let k = idleState.kind { return "idle:" + k.rawValue }
        if let s = social { return "social:" + s.kind.rawValue }
        if job != nil { return "job" }
        if commanded { return "commanded" }
        return route.isEmpty ? "roam" : "route"
    }
    func curveLogTurn(err: Float, D: Float, intermediate: Bool, exact: Bool) {
        NSLog("[midturn] t=%.2f id=%d kind=%@ inter=%d err=%.2f D=%.2f", variety.now, steerID, curveKind, intermediate ? 1 : 0, abs(err), D)
    }
    func curveLogStep(err: Float, D: Float, intermediate: Bool, dy: Float, bend: Bool, travel: SIMD2<Float>) {
        var slip: Float = 0
        if simd_length(travel) > 0.02 { slip = abs(wrapAngle(atan2f(travel.x, travel.y) - (yaw + dy))) }
        NSLog("[curve] t=%.2f id=%d kind=%@ inter=%d bend=%d err=%.2f D=%.2f dy=%.2f slip=%.2f x=%.2f z=%.2f", variety.now, steerID, curveKind, intermediate ? 1 : 0, bend ? 1 : 0, abs(err), D, dy, slip, px, pz)
    }
    func curveLogPush(got: SIMD2<Float>, cand: SIMD2<Float>, curved: Bool) {
        var nd: Float = 9, nw = false
        for p in steerPeers() { let d = simd_distance(p.pos, cand); if d < nd { nd = d; nw = p.id < Int.max / 4 } }
        // an indirect effect: either body (this one or the nearest other) took a curved step in the previous 1.5 s
        var near: BlobBrain?, od: Float = 9
        for o in socialOthers() where o !== self { let d = simd_distance(o.position, cand); if d < od { od = d; near = o } }
        let recent = (peerClock - lastCurvedClock < 1.5) || (near.map { $0.peerClock - $0.lastCurvedClock < 1.5 } ?? false)
        NSLog("[push] t=%.2f id=%d x=%.2f z=%.2f moved=%.3f kind=%@ nearest=%.2f(%@) curved=%d recent=%d", variety.now, steerID, cand.x, cand.y, simd_distance(got, cand), curveKind, nd, nw ? "walker" : "stander", curved ? 1 : 0, recent ? 1 : 0)
    }
}
