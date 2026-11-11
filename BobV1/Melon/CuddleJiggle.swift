//
//  CuddleJiggle.swift
//  STEP 2 of "lean into the jelly" (the owner: "the close-up cuddle slightly exaggerated"): a purely DRAWN layer on the body skin while a finger pets him.
//  It never touches the sim, the press (`setPress` / `dentDepth` / `fingerRadius`), the brain or the feet: a deeper physical press creases the coarse mesh, so
//  everything here is a smooth skin offset added to the skinned vertices in `Skinner.update` (the same idea as the cheek squeeze), exactly 0 when nobody
//  touches him and once the wobble has died (every state is clamped to 0 below a hair, `active` goes false, the skin is the plain skin).
//
//    dent      extra drawn depth under the fingertip along the inward normal (0 / 0.02 / 0.04 u), smoothstep falloff to ~1.6 x fingerRadius, plus a slight
//              raised rim just outside the finger (15 % / 25 % of the extra depth). Follows the dent engagement `ramp`, so it never pops on touch-down.
//    drag      the skin near the fingertip is pulled along the finger's motion on the surface (max 0 / 0.03 / 0.05 u), springing back in ~0.12 s.
//    let-go    on release the dented spot springs OUT past the rest surface (0 / 40 % / 60 % of the dent depth at release) and rings down at ~6 Hz
//              (zeta 0.22 / 0.16), plus one ripple ring travelling outward at 1.5 u/s (0 / 0.008 / 0.014 u, gone in 0.5 s). The ring-down also yields 2-3 fading
//              soft taps (`tap`), sent by TouchPlay through the one existing haptic driver.
//    petted    the happy "love" roll / squash jiggle that TouchPlay already hands the brain (a physical lean) gets an extra drawn x1.25 / x1.5 on top.
//
//  Level 0 ("Today") does nothing at all. Only body skin is displaced (not the arm / foot / tail blocks, not the eyes / brows), the offset fades out toward the
//  foot join, and no vertex ever moves further than the cheek squeeze's own cap (`maxOffset` = `TouchPlay.maxCheekOffset`).
//

import Foundation
import simd

nonisolated final class CuddleJiggle {
    /// Same numbers as `TouchPlay.fingerRadius` / `dentDepth` / `maxCheekOffset` (a test pins them): this file is not main-actor isolated.
    static let fingerRadius: Float = 0.26
    static let dentDepth: Float = 0.10
    static let maxOffset: Float = 0.08 * Float(BobForm.top)
    static let ringHz: Float = 6, rippleSpeed: Float = 1.5, rippleLife: Float = 0.5, rippleWidth: Float = 0.12
    static let dragTau: Float = 0.12
    static let reach: Float = 1.0

    /// The numbers that differ between the three feel levels (TEMPORARY owner A/B: 0 "Today", 1 "A little more", 2 "More").
    struct Tuning {
        var extraDepth: Float, rimFrac: Float, dragMax: Float, overshoot: Float, zeta: Float, ripple: Float, petScale: Float
    }
    static func tuning(_ level: Int) -> Tuning {
        switch level {
        case 1: return Tuning(extraDepth: 0.02, rimFrac: 0.15, dragMax: 0.03, overshoot: 0.40, zeta: 0.22, ripple: 0.008, petScale: 1.25)
        case 2: return Tuning(extraDepth: 0.04, rimFrac: 0.25, dragMax: 0.05, overshoot: 0.60, zeta: 0.16, ripple: 0.014, petScale: 1.5)
        default: return Tuning(extraDepth: 0, rimFrac: 0, dragMax: 0, overshoot: 0, zeta: 0.22, ripple: 0, petScale: 1)
        }
    }
    /// The shared current level (0...2) every Jelbie reads live; default 1. Saved under `CuddleJiggleLevel` by `choose` (so `-CuddleJiggleLevel 2` works); read once at
    /// launch, and only in dev-args builds (the App Store build always uses the default).
    nonisolated(unsafe) static var sharedLevel: Int = {
        if DevArgs.enabled, UserDefaults.standard.object(forKey: "CuddleJiggleLevel") != nil { return min(2, max(0, UserDefaults.standard.integer(forKey: "CuddleJiggleLevel"))) }
        return 1
    }()
    /// The Settings switch: sets the shared level (live, every Jelbie) and saves it.
    static func choose(_ l: Int) { sharedLevel = min(2, max(0, l)); UserDefaults.standard.set(sharedLevel, forKey: "CuddleJiggleLevel") }
    /// Tests: force one instance to a level without touching the shared one.
    var levelOverride: Int? = nil
    var level: Int { levelOverride ?? Self.sharedLevel }
    var tune: Tuning { Self.tuning(level) }
    /// Kill switch (A/B captures, tests).
    var enabled = true

    // state
    private(set) var active = false
    private var contactOn = false
    private(set) var cW = SIMD3<Float>.zero, nW = SIMD3<Float>(0, 0, 1)       // the dent centre / outward normal (world)
    private var cL = SIMD3<Float>.zero, nL = SIMD3<Float>(0, 0, 1)       // the same in the body frame (so the ring-down follows him)
    private var haveCentre = false
    private var prevTarget: SIMD3<Float>? = nil
    private var fingerV = SIMD3<Float>.zero                              // low-passed finger velocity on the surface (world)
    private(set) var drag = SIMD3<Float>.zero
    /// Outward displacement at the dent centre (u): negative while the finger presses (the extra dent), then the let-go spring.
    private(set) var s: Float = 0, sV: Float = 0
    private(set) var depthNow: Float = 0                                 // the drawn extra depth under the finger right now (>= 0)
    private var rimAmt: Float = 0
    private(set) var rippleAge: Float = 99
    private var rippleAmp: Float = 0
    private var wasEngaged: Float = 0
    private var taps = 0
    private var petRoll: Float = 0, petSq: Float = 0
    private var sinceStep = 0
    /// Soft taps fired by the last `step` (intensity 0 = none), read once by TouchPlay.
    private(set) var tap: Float = 0
    /// Peak outward displacement of the let-go spring so far (tests / log).
    private(set) var peakOut: Float = 0

    func reset() {
        active = false; contactOn = false; haveCentre = false; prevTarget = nil; fingerV = .zero; drag = .zero; s = 0; sV = 0; depthNow = 0; rimAmt = 0
        rippleAge = 99; rippleAmp = 0; wasEngaged = 0; taps = 0; petRoll = 0; petSq = 0; tap = 0; peakOut = 0
    }

    /// TouchPlay's happy jiggle gives its roll (rad) and squash fraction (+ = taller) here every frame; the extra drawn part is (scale - 1) of them.
    func setPet(roll: Float, squash: Float) {
        let k = tune.petScale - 1
        if k <= 0 || !enabled { petRoll = 0; petSq = 0; return }
        petRoll = roll * k; petSq = squash * k
        if petRoll != 0 || petSq != 0 { active = true; sinceStep = 0 }
    }

    private func smooth(_ x: Float) -> Float { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }
    private func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float { smooth((x - a) / (b - a)) }

    // MARK: drive

    /// One pet frame. `point` / `normal`: the fingertip hit (world, outward) or nil; `ramp`: TouchPlay's dent engagement 0...1; `pose`: his rigid pose (nil
    /// only when nothing is running). Returns nothing; the soft tap for this frame is in `tap`.
    func step(dt rawDt: Float, contact: Bool, ramp: Float, point: SIMD3<Float>?, normal: SIMD3<Float>?, pose: BodyPose?, annoyed: Bool) {
        tap = 0
        guard enabled, level > 0 else { if active { reset() }; return }
        sinceStep = 0
        let dt = min(max(rawDt, 0), 0.25)
        let tn = tune
        let engaged = contact && !annoyed
        let eng = engaged ? smooth(ramp) : 0

        // the centre: follows the fingertip while it is on him, then rides on his body
        if engaged, let p = point, let n = normal, simd_length(n) > 0.5 {
            let nn = simd_normalize(n)
            if !haveCentre || !contactOn { cW = p; nW = nn }
            else {
                let a = 1 - expf(-dt / 0.03)
                cW += (p - cW) * a
                let m = nW + (nn - nW) * (1 - expf(-dt / 0.04))
                nW = simd_length(m) > 1e-4 ? simd_normalize(m) : nn
            }
            haveCentre = true
            if let pose { let inv = pose.rotation.inverse; cL = inv.act(cW - pose.centroid); nL = inv.act(nW) }
            // the finger's sliding speed on the surface -> the skin drags along it
            var vel = SIMD3<Float>.zero
            if let pt = prevTarget, dt > 0 { vel = (p - pt) / dt; vel -= nW * simd_dot(vel, nW) }
            prevTarget = p
            if vel.x.isFinite && vel.y.isFinite && vel.z.isFinite { fingerV += (vel - fingerV) * (1 - expf(-dt / 0.05)) } else { fingerV = .zero }
        } else {
            prevTarget = nil
            fingerV += (SIMD3<Float>.zero - fingerV) * (1 - expf(-dt / 0.05))
            if haveCentre, let pose { cW = pose.centroid + pose.rotation.act(cL); nW = pose.rotation.act(nL) }
        }

        // drag: the skin lags the finger by about dragTau seconds of its travel (saturating), and springs back when it stops
        var want = fingerV * Self.dragTau
        let wl = simd_length(want)
        if tn.dragMax > 0, wl > 1e-6 { want *= tn.dragMax * tanhf(wl / tn.dragMax) / wl } else { want = .zero }
        if !engaged { want = .zero }
        drag += (want - drag) * (1 - expf(-dt / Self.dragTau))
        if simd_length(drag) < 2e-4 && want == .zero { drag = .zero }

        // dent + let-go spring
        if engaged {
            depthNow = tn.extraDepth * eng
            s = -depthNow; sV = 0
            rimAmt = tn.rimFrac * depthNow
            wasEngaged = eng; taps = 0; peakOut = 0
            rippleAge = 99
            contactOn = true
        } else {
            if contactOn {
                // released: the drawn extra dent springs out past the surface. The kick is chosen so the first outward peak is the wanted fraction of the
                // dent depth at release (the physical 0.10 dent at its engagement plus the drawn extra).
                contactOn = false
                let depth0 = (Self.dentDepth + tn.extraDepth) * wasEngaged
                let P = wasEngaged >= 0.6 ? tn.overshoot * depth0 : 0
                sV = P > 0 ? kick(s0: s, peak: P, zeta: tn.zeta) : 0
                if wasEngaged >= 0.6 { rippleAge = 0; rippleAmp = tn.ripple * wasEngaged }
                taps = 0; peakOut = 0
                wasEngaged = 0
            }
            let w = 2 * Float.pi * Self.ringHz, z = tn.zeta
            let steps = max(1, Int((dt / (1.0 / 240)).rounded(.up))), h = dt / Float(steps)
            let prevV = sV
            for _ in 0..<steps {
                sV += (-w * w * s - 2 * z * w * sV) * h
                s += sV * h
            }
            if !s.isFinite || !sV.isFinite { s = 0; sV = 0 }
            s = max(-0.2, min(0.2, s)); sV = max(-5, min(5, sV))
            peakOut = max(peakOut, s)
            // a soft tap at each extreme of the swing that is still big enough to see, at most 3
            if prevV * sV < 0, abs(s) > 0.004, taps < 3 { taps += 1; tap = min(0.28, 0.08 + 3.2 * abs(s)) }
            if abs(s) < 5e-4 && abs(sV) < 5e-3 { s = 0; sV = 0 }
            depthNow = max(0, -s)
            rimAmt = depthNow * tn.rimFrac
            if rippleAge < Self.rippleLife { rippleAge += dt } else { rippleAge = 99; rippleAmp = 0 }
        }
        let rippling = rippleAge < Self.rippleLife
        active = engaged || contactOn || s != 0 || sV != 0 || drag != .zero || rippling || petRoll != 0 || petSq != 0
        if !active { haveCentre = false; fingerV = .zero; rimAmt = 0; depthNow = 0 }
    }

    /// The initial velocity that makes the first outward peak of the damped spring (start s0, <= 0) exactly `peak` (found by bisection on the closed form).
    private func kick(s0: Float, peak: Float, zeta: Float) -> Float {
        let w = 2 * Float.pi * Self.ringHz, sig = zeta * w, wd = w * (1 - zeta * zeta).squareRoot()
        func best(_ b: Float) -> Float {
            var m: Float = -1
            var t: Float = 0
            while t < 0.2 { let e = expf(-sig * t); m = max(m, e * (s0 * cosf(wd * t) + b * sinf(wd * t))); t += 0.001 }
            return m
        }
        var lo: Float = 0, hi: Float = 4
        for _ in 0..<40 { let mid = 0.5 * (lo + hi); if best(mid) < peak { lo = mid } else { hi = mid } }
        let b = 0.5 * (lo + hi)
        return b * wd - sig * s0
    }

    // MARK: apply

    /// The ripple ring's outward displacement at distance `d` from the release point, `age` s after it (a raised ring 0.12 u wide that travels at 1.5 u/s and fades
    /// linearly to nothing at 0.5 s).
    static func rippleValue(d: Float, age: Float, amp: Float) -> Float {
        guard age < rippleLife, amp > 0 else { return 0 }
        let x = d - (rippleSpeed * age + 0.1)
        guard abs(x) < rippleWidth else { return 0 }
        return amp * (1 - age / rippleLife) * 0.5 * (1 + cosf(.pi * x / rippleWidth))
    }
    /// Tests: the ring's displacement now at distance `d`.
    func rippleOffset(at d: Float) -> Float { Self.rippleValue(d: d, age: rippleAge, amp: rippleAmp) }

    /// Displace the skinned body vertices (`dyn`: 6 floats per vertex, position first; `mask[v]` = a body skin vertex, not an arm / foot / tail piece, not a
    /// face feature). A no-op unless `active`; a layer nobody has stepped for half a second is dropped (it must never freeze on the skin).
    func apply(_ dyn: UnsafeMutablePointer<Float>, count: Int, mask: UnsafePointer<Bool>, floorY: Float, H: Float) {
        guard enabled, active else { return }
        sinceStep += 1
        if sinceStep > 30 { reset(); return }
        let R = Self.fingerRadius
        let c = cW, n = nW
        let nearOn = (s != 0 || rimAmt != 0 || drag != .zero || rippleAge < Self.rippleLife) && haveCentre
        let dragV = drag
        let sOut = s, rim = rimAmt
        let rAge = rippleAge, rAmp0 = rippleAmp, rippling = rippleAge < Self.rippleLife && rippleAmp > 0
        let invH = 1 / H, cap = Self.maxOffset, reach2 = Self.reach * Self.reach
        let pr = petRoll, ps = petSq, petOn = pr != 0 || ps != 0
        let invR = 1 / R
        for v in 0..<count where mask[v] {
            let o = 6 * v
            let px = dyn[o], py = dyn[o + 1], pz = dyn[o + 2]
            let hN = (py - floorY) * invH
            var off = SIMD3<Float>.zero
            let fh = smoothstep(0.15, 0.30, hN)                          // 0 at the foot join, 1 from the lower belly up
            if fh == 0 { continue }
            if nearOn {
                let dv = SIMD3<Float>(px - c.x, py - c.y, pz - c.z)
                let d2 = simd_length_squared(dv)
                if d2 < reach2, simd_dot(dv, n) > -0.5 {
                    if fh > 0 {
                        let d = d2.squareRoot(), u = d * invR
                        let wd = 1 - smoothstep(0.25, 1.6, u)                    // the dent / spring profile
                        var along = sOut * wd
                        let t = (u - 1.0) / 1.2
                        if rim > 0, t > 0, t < 1 { let sn = sinf(.pi * t); along += rim * sn * sn }       // the displaced jelly bunches up just outside the finger
                        if rippling { along += Self.rippleValue(d: d, age: rAge, amp: rAmp0) }
                        off = n * along + dragV * (1 - smoothstep(0, 1.6, u))
                        off *= fh
                    }
                }
            }
            if petOn {
                let t = min(1, max(0, (hN - 0.1) * (1 / 0.9)))
                if t > 0 {
                    let sm = t * t * (3 - 2 * t), w = sm * sm
                    off.x += -pr * (py - floorY) * w * fh
                    off.y += ps * (py - floorY) * sm * fh
                }
            }
            let m = simd_length(off)
            if m == 0 { continue }
            if !m.isFinite { continue }
            if m > cap { off *= cap / m }
            dyn[o] += off.x; dyn[o + 1] += off.y; dyn[o + 2] += off.z
        }
    }
}
