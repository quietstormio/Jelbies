//
//  TailMotion.swift
//  How Pip's long tail moves (2026-10-28). The tail is no longer one stiff piece turned about its root: every RING of the tail block gets its own bend angle
//  (yaw about the vertical, pitch about the horizontal axis across the tail) and the centre line is walked out ring by ring (a chain), so the tail bends like
//  a rope. The angles are a TRAVELLING WAVE: the root moves a little, the tip a lot and later (follow-through).
//
//  Inputs (TailDrive, filled by the brain every tick, BlobBrain+TailPlay.swift):
//    walking   a swish locked to the gait (one cycle per stride = two steps), amplitude from the root's speed (livelier at a run), easing out over ~0.5 s
//    carriage  the mood: happy rides higher with a slow wag, grumpy / sad lies flat, slower and smaller
//    wag       the happy wag, hmph's slow swishes, the dizzy wobble after a tail chase (amplitude + rate, same follow-through)
//    bends     sustained yaw / lift (the chase lead, the thump lift, the hug curl), already shaped in time by the brain
//  Output: per-ring rotations (`Skinner.tailRingQ`, world frame) that the spike layer reads so each spike leans with the bent tail.
//

import Foundation
import simd

/// What the brain asks of the tail this tick.
nonisolated struct TailDrive {
    /// Gait phase 0...1 (BlobBrain.stridePhase) and whether the feet are stepping (otherwise the swish runs on its own clock and fades).
    var stride: Float = 0
    var strideLive = false
    /// Run / zoomies blend 0...1.
    var run: Float = 0
    /// Mood -1 (grumpy, sad) ... 0 ... +1 (happy).
    var mood: Float = 0
    /// Extra wag (tip degrees, Hz): hmph swishes, the dizzy wobble.
    var wagDeg: Float = 0, wagHz: Float = 1.4
    /// Sustained yaw of the tip (deg; + = toward the body's +x side) with the shape exponent (1 = even curl, 2 = a hook at the tip).
    var bendYaw: Float = 0, bendPow: Float = 1
    /// Sustained lift (deg): `liftRoot` raises the whole tail from its root, `liftTip` curls the tip up on top of that.
    var liftRoot: Float = 0, liftTip: Float = 0
    /// Turn response in degrees of tail yaw per (deg/s) of body turn rate: negative = the tail trails behind a turn, positive = it leads (the chase).
    var turnGain: Float = -0.05
    /// Reduce Motion: the swish and wag shrink and the antics do not start.
    var reduce = false
}

/// The seat Pip stands on, for the tail's floor: a rounded rectangle (world xz) at height `y`. The tail's floor part lies at `y` over the seat and drapes down to the
/// world floor over `drape` beyond its edge.
nonisolated struct TailSeat {
    var centre = SIMD2<Float>.zero, half = SIMD2<Float>(0.5, 0.5), corner: Float = 0.3, y: Float = 0
    /// A raised rim round the edge (the sandbox's frame): its top height and thickness; the tail climbs over it instead of cutting through.
    var rimTop: Float = 0, rimW: Float = 0
    static let drape: Float = 0.4
    /// Floor height under (x, z) at full seat weight.
    func floor(_ x: Float, _ z: Float) -> Float {
        if y <= 0 { return 0 }
        let q = SIMD2(abs(x - centre.x), abs(z - centre.y)) - (half - SIMD2(repeating: corner))
        let sd = simd_length(simd_max(q, .zero)) + min(max(q.x, q.y), 0) - corner
        var top = y
        if rimTop > y { top = y + (rimTop - y) * simd_smoothstep(-rimW - 0.18, -rimW, sd) }
        return top * (1 - simd_smoothstep(0, max(Self.drape, 0.8 * top), max(0, sd)))          // (a taller seat drapes over a longer run: gentler, never a vertical hang)
    }
}

/// The tail's own state (filters and clocks); Skinner owns one.
nonisolated struct TailMotion {
    var walkAmp: Float = 0, runAmp: Float = 0, carry: Float = 0, wag: Float = 0, slow: Float = 0
    var phase: Float = 0, phaseRate: Float = 0, lastStride: Float = 0, strideSeen = false
    var wagPhase: Float = 0, idlePhase: Float = 0
    var turn: Float = 0, lastYaw: Float = 0, yawSeen = false
    var bob: Float = 0

    /// Tip-angle amplitudes (deg) of the walking swish at a walk / at a full run.
    static let walkDeg: Float = 15, runDeg: Float = 9
    /// Wave lag along the tail (radians from the root to the tip): the tip follows the root by this much of a cycle.
    static let lag: Float = 1.9
    static let idleDeg: Float = 3.5

    /// Envelope along the visible tail, u = 0 (leaves the back) ... 1 (tip): the root moves a little, the tip the most; zero in the buried part.
    static func env(_ u: Float) -> Float { (0.2 + 0.8 * u) * simd_smoothstep(0, 0.1, u) }

    /// Ring k (0-based over the rings) -> its position u along the visible tail.
    static let ringU: [Float] = {
        let s = TailBean.shape
        return (0..<TailBean.rings).map { r in
            let k = min(r + 1, TailBean.bodyRings)
            let t = Float(s.length) * Float(k) / Float(TailBean.bodyRings)
            let h = Float(s.sink + PipBack.shift)          // (the hinge: where the tail leaves the back; a shifted tail leaves it `shift` further along)
            return min(1, max(0, (t - h) / (Float(s.length) - h)))
        }
    }()

    /// One tick: filter the inputs, advance the clocks; `speed01` = ground speed / 0.5 (clamped), `yawNow` = the body's heading (rad).
    mutating func step(_ d: TailDrive, speed: Float, yawNow: Float, dt: Float, happyFlag: Bool) {
        let k = d.reduce ? Float(0.35) : 1
        let sp = min(1, speed / 0.5)
        let run = min(1, max(0, d.run))
        func chase(_ x: inout Float, _ target: Float, _ tau: Float) { x += (target - x) * (1 - expf(-dt / tau)) }
        chase(&walkAmp, sp * Self.walkDeg * k, 0.16)
        chase(&runAmp, sp * run * Self.runDeg * k, 0.16)
        chase(&carry, d.mood, 0.35)
        chase(&slow, d.mood < -0.3 ? 1 : 0, 0.5)
        let happyWag: Float = happyFlag ? 18 : 0
        chase(&wag, (max(d.wagDeg, happyWag) + max(0, d.mood) * 7) * k, 0.12)
        // the gait phase: while he steps, the swish is locked to the stride; otherwise it coasts on at the last rate (and fades with the amplitude)
        if d.strideLive {
            if strideSeen {
                var ds = d.stride - lastStride
                ds -= floorf(ds + 0.5)          // wrapped to -0.5...0.5 (a stride is continuous)
                phase += 2 * .pi * ds
                if dt > 0 { chase(&phaseRate, 2 * .pi * ds / dt, 0.1) }
            }
            lastStride = d.stride; strideSeen = true
        } else {
            phase += phaseRate * dt
            strideSeen = false
        }
        let mul: Float = 1 - 0.3 * slow          // grumpy / sad: everything a little slower
        wagPhase += 2 * .pi * (d.wagDeg > 0.1 ? d.wagHz : (happyFlag ? 3.2 : 1.1 + 0.2 * max(0, d.mood))) * mul * dt
        idlePhase += 2 * .pi * 0.45 * mul * dt
        // turn rate (deg/s), filtered: the tail trails a turn (or leads it in the chase)
        var dy = yawNow - lastYaw
        dy -= 2 * .pi * floorf(dy / (2 * .pi) + 0.5)
        lastYaw = yawNow
        let rate = yawSeen && dt > 0 ? dy / dt * 180 / .pi : 0
        yawSeen = true
        chase(&turn, max(-500, min(500, rate)), 0.08)
    }

    /// How much of each ring lies on the floor (1) rather than hanging from the back (0): the same blend applyTail uses (by the rest height of the ring).
    static let ringFloorW: [Float] = {
        let ys = (0..<TailBean.rings).map { TailBean.ringY[1 + TailBean.around * $0] }
        let low = ys.indices.min { ys[$0] < ys[$1] } ?? 0
        return ys.indices.map { $0 >= low ? 1 : 1 - simd_smoothstep(0.22, 0.5, ys[$0]) }          // (from the lowest ring on, the tail lies on the floor, even where its tip curls up a little)
    }()
    /// Ring radius (horizontal half width) of each ring.
    static let ringRad: [Float] = {
        let s = TailBean.shape
        return (0..<TailBean.rings).map { r in Float(s.radius(s.length * Double(min(r + 1, TailBean.bodyRings)) / Double(TailBean.bodyRings))) }
    }()
    /// If a ring centre (body rest frame) is inside the egg or the leg block (grown by the ring's own radius), the nearest point outside it in the floor plane; else nil.
    static func keepOut(_ q: SIMD3<Float>, radius rad: Float) -> SIMD3<Float>? {
        let t = Double((q.y - Float(BobForm.lift)) / Float(BobForm.bodyH))
        var a: Float = 0, b: Float = 0
        if t > 0 && t < 1 { a = Float(BobForm.halfWidth(t: t)); b = Float(BobForm.halfDepth(t: t)) }
        if q.y < 0.34 { a = max(a, 0.40); b = max(b, 0.30) }          // the feet: x 0.06...0.37, z -0.06...0.26
        if a <= 0 { return nil }
        let m = rad * 0.8
        let ea = a + m, eb = b + m
        let e = ((q.x / ea) * (q.x / ea) + (q.z / eb) * (q.z / eb)).squareRoot()
        if e >= 1 { return nil }
        if e < 1e-4 { return SIMD3(q.x, q.y, q.z - eb) }
        return SIMD3(q.x / e, q.y, q.z / e)
    }

    /// The bend angles of ring r (deg): (yaw, pitch).
    func angles(ring r: Int, drive d: TailDrive) -> (yaw: Float, pitch: Float) {
        let u = Self.ringU[r]
        if u <= 0 { return (0, 0) }
        let e = Self.env(u)
        let lag = Self.lag * u
        let mul: Float = 1 - 0.3 * slow
        var yaw = e * (walkAmp + runAmp) * sinf(phase - lag)
        yaw += e * wag * sinf(wagPhase - lag * 1.15)
        yaw += e * Self.idleDeg * (d.reduce ? 0.3 : 1) * mul * sinf(idlePhase - lag)
        yaw += d.bendYaw * powf(u, d.bendPow)
        let lead = max(-34, min(34, d.turnGain * turn))
        yaw += lead * powf(u, 0.8)
        // carriage: happy lifts the tail a few degrees (more toward the tip), grumpy presses it flat; the gait adds a small bob at the stride rate
        let carriage = carry > 0 ? 13 * carry : 0
        var pitch = carriage * (0.5 + 0.5 * u) * simd_smoothstep(0, 0.12, u)
        pitch += 0.35 * (walkAmp + runAmp) * e * sinf(2 * phase - lag)
        pitch += d.liftRoot * (1 - 0.35 * u) * simd_smoothstep(0, 0.12, u) + d.liftTip * u * u
        if carry < 0 { pitch += 5 * carry * (1 - u) * simd_smoothstep(0, 0.12, u) }          // a sag at the root
        return (yaw, pitch)
    }
}

nonisolated extension Skinner {
    /// The bend: every ring gets its angles (TailMotion.angles), the centre line is walked out ring by ring from the root so the lengths are kept, and each ring's
    /// vertices turn with it about their own (moved) centre. Rings inside the body (u = 0) do not move. `pivot` = where the tail leaves the back (the pop-in scales about it).
    func bendTail(_ dyn: UnsafeMutablePointer<Float>, first f: Int, n: Int, speed: Float, vy: Float, heading: Float, pivot: SIMD3<Float>, base B: SIMD3<Float>, tip T: SIMD3<Float>, rot Rot: simd_float3x3, cs Cs: SIMD3<Float>, cr Cr: SIMD3<Float>) {
        let around = TailBean.around, rings = TailBean.rings, dt = frameDt
        let drive = tailDrive
        tailMotion.step(drive, speed: speed, yawNow: heading, dt: dt, happyFlag: tailHappy)
        tailMotion.bob += (max(-14, min(14, -vy * 4)) - tailMotion.bob) * min(1, dt * 10)
        let D = simd_normalize(T - B)
        var axis = simd_cross(D, SIMD3<Float>(0, 1, 0))
        axis = simd_length(axis) > 1e-4 ? simd_normalize(axis) : SIMD3(1, 0, 0)
        let liftSign: Float = simd_quatf(angle: 0.1, axis: axis).act(D).y >= D.y ? 1 : -1
        func P(_ i: Int) -> SIMD3<Float> { SIMD3(dyn[6 * (f + i)], dyn[6 * (f + i) + 1], dyn[6 * (f + i) + 2]) }
        var qs = [simd_quatf](repeating: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), count: rings)
        var tipYaw: Float = 0, tipPitch: Float = 0
        var oldC = [SIMD3<Float>](repeating: .zero, count: rings), newC = oldC
        var prevOld = B, prevNew = B
        for r in 0..<rings {
            let a = tailMotion.angles(ring: r, drive: drive)
            let u = TailMotion.ringU[r]
            let bob = u > 0 ? tailMotion.bob * simd_smoothstep(0, 0.2, u) : 0
            let q = simd_quatf(angle: a.yaw * .pi / 180, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: (liftSign * a.pitch + bob) * .pi / 180, axis: axis)
            qs[r] = q
            if r == rings - 1 { tipYaw = a.yaw; tipPitch = a.pitch }
            let o = 1 + around * r
            var c = SIMD3<Float>.zero
            for j in 0..<around { c += P(o + j) }
            c /= Float(around)
            oldC[r] = c
            newC[r] = prevNew + q.act(c - prevOld)
            prevOld = c; prevNew = newC[r]
        }
        // keep the tail out of the body: a ring centre that has been swung into the egg (or the legs) is pushed back out along the floor plane; the push is smoothed
        // along the tail so it never kinks. At rest and in the ordinary swish nothing is pushed.
        var push = [SIMD3<Float>](repeating: .zero, count: rings)
        var any = false
        for r in 0..<rings {
            let w = simd_smoothstep(0.12, 0.35, TailMotion.ringU[r])
            if w <= 0 { continue }
            let q = Cr + Rot.transpose * (newC[r] - Cs)
            if let qo = TailMotion.keepOut(q, radius: TailMotion.ringRad[r]) {
                push[r] = (Cs + Rot * (qo - Cr) - newC[r]) * w; any = true
            }
        }
        if any {
            for _ in 0..<3 { var sm = push; for r in 1..<(rings - 1) { sm[r] = (push[r - 1] + 2 * push[r] + push[r + 1]) * 0.25 }; for r in 0..<rings { if simd_length(sm[r]) > simd_length(push[r]) { push[r] = sm[r] } } }
        }
        let sc = tailScaleNow
        tailSeatW += max(-dt / 0.2, min(1, (tailSeat.y > 0.01 && tailSeatOn ? 1 : 0) - tailSeatW))
        let seatW = tailSeatW
        // the floor under the body right now, from the body itself (0 on the room floor): the seat's top can never lift the tail above where he really is, so a hop on / off blends with him
        let underBody = max(0, (Cs.y - Cr.y) + TailBean.restFloor + 0.02) + (tailSeat.rimTop > tailSeat.y ? tailSeat.rimTop - tailSeat.y + 0.02 : 0)          // (a rim may lift the tail above his own floor)
        for r in 0..<rings {
            let o = 1 + around * r
            let q = qs[r], d = push[r]
            let c = newC[r] + d
            let lift = seatW > 0.001 ? seatW * min(tailSeat.floor(c.x, c.z), underBody) * TailMotion.ringFloorW[r] : 0
            for j in 0..<around { writeTail(dyn, f + o + j, newC[r] + d + q.act(P(o + j) - oldC[r]), pivot: pivot, scale: sc, floor: lift) }
        }
        prevOld = oldC[rings - 1]; prevNew = newC[rings - 1] + push[rings - 1]
        let qt = qs[rings - 1]
        writeTail(dyn, f + n - 1, prevNew + qt.act(T - prevOld), pivot: pivot, scale: sc, floor: seatW > 0.001 ? seatW * min(tailSeat.floor(prevNew.x, prevNew.z), underBody) * TailMotion.ringFloorW[rings - 1] : 0)
        setTailTip(yaw: tipYaw, pitch: tipPitch)
        setTailRings(qs)
    }

    private func writeTail(_ dyn: UnsafeMutablePointer<Float>, _ vi: Int, _ pIn: SIMD3<Float>, pivot: SIMD3<Float>, scale sc: Float, floor fl: Float = 0) {
        var p = pIn
        if sc < 1 { p = pivot + (p - pivot) * sc }
        let o = 6 * vi
        dyn[o] = p.x; dyn[o + 2] = p.z
        // soft floor instead of a hard clamp: below 0.04 the height eases down onto 0.004, so the underside rounds into the floor with no flat crease
        dyn[o + 1] = fl + (p.y >= 0.04 ? p.y : 0.004 + 0.036 * expf((p.y - 0.04) / 0.036))
    }
}
