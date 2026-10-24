//
//  JellyJiggle.swift
//  A very slight jelly follow-through on the DRAWN body while he moves (the user: "when he moves and walks give him very slight jiggle,
//  we're going to lean into the jelly aspect"). Purely a render-side, additive layer: three damped springs driven by what the brain already
//  does, applied to the skinned vertices as the last displacement before the normals (Skinner.update). It never touches the sim, the brain
//  or the feet.
//
//    squash   a vertical ripple on every footfall (and on a hop landing): ~2 % H at 7.5 Hz, settles in ~0.25 s. The body is compressed
//             toward the floor (displacement 0 at the soles, growing to the crown) with a tiny sideways bulge to keep the volume.
//    sway     the upper body lags the root when it starts / stops / changes speed and wobbles back (3.5 Hz). The crown trails by ~2 % H.
//    twist    the same for turning: the crown lags the heading a hair and wobbles back.
//
//  Everything is weighted by height so the lowest ~10 % of the body (the feet, the planted soles) is never moved: MotionGrounded /
//  MotionSlip are unaffected. At rest (no motion for a moment) all three states decay to exactly zero and `active` goes false, so the
//  skin is byte-identical to the plain skin (BaseBodyLock goldens).
//
//  Hooks: `Skinner.update` calls `jelly.apply` (one line); MelonStage calls `jelly.tick(brain:sim:dt:)` after each brain tick (one line).
//  Tests / haptics read `squash` (fraction of H the body is compressed, + = squashed) and `intensity` (0...1).
//

import simd

nonisolated final class JellyJiggle {
    // tuning
    static let squashHz: Float = 7.5, squashZeta: Float = 0.25
    static let swayHz: Float = 3.5, swayZeta: Float = 0.40
    static let footImpulse: Float = 2.4          // squash velocity per footfall at walking speed (peak ~ 3.5 % H; Build B: x1.7 of the first slight jiggle)
    static let hopImpulse: Float = 0.9           // per u/s of landing speed
    static let swayGain: Float = 3.4             // crown lag (u) per u/s of root speed change, before the spring
    static let twistGain: Float = 0.8            // crown lag (rad) per rad/s of turn-rate change, before the spring
    static let walkSpeed: Float = 1.25    // the walk's root speed (u/s, measured; 2026-10-24 free locomotion +10 % cadence: was 1.14; Build B +10 %: was 1.02, 0.853 before that)
    /// Cap scale of the displacement springs (fractions of H / rad at boost 0): Build B 0.022 -> 0.038, twist 0.03 -> 0.05.
    static let capSq: Float = 0.038, capTw: Float = 0.05
    static let stopWobble: Float = 2.0           // squash velocity when he stops dead from a walk / run (scaled by the speed he had)

    /// Height of the body the displacements are fractions of, and the floor they are measured from.
    var H: Float = Float(BobForm.top)
    var floorY: Float = 0
    /// Kill switch (A/B captures, tests). Off = the plain skin exactly.
    var enabled = true
    /// The first slight jiggle (before Build B), for the before / after captures and the amplitude-ratio test.
    var legacy = false
    private var impulseK: Float { legacy ? 1.4 / Self.footImpulse : 1 }
    private var capSqV: Float { legacy ? 0.022 : Self.capSq }
    private var capTwV: Float { legacy ? 0.03 : Self.capTw }
    private var capGrow: Float { legacy ? 0.9 : 1.2 }
    private var swayK: Float { legacy ? 2.2 : Self.swayGain }

    // state
    private(set) var sq: Float = 0, sqV: Float = 0                  // squash fraction of H (+ = compressed)
    private(set) var sway = SIMD2<Float>(0, 0), swayV = SIMD2<Float>(0, 0)   // world xz, units
    private(set) var tw: Float = 0, twV: Float = 0                  // crown heading lag (rad)
    private(set) var active = false
    private(set) var center = SIMD2<Float>(0, 0)
    private var boost: Float = 0                                    // 0 = walking caps ... 1 = run / landing caps
    private var havePrev = false
    private var prevRoot = SIMD2<Float>(0, 0), prevYaw: Float = 0
    private var vel = SIMD2<Float>(0, 0), yawRate: Float = 0
    private var stillT: Float = 0
    private var peakSpeed: Float = 0                                // recent top root speed (decays): a dead stop from it gets a settle wobble
    private var wasSwinging = false
    private var prevVY: Float = 0, prevCY: Float = 0, haveVY = false

    /// Read-only per-frame signal for haptics: the current compression, in fractions of H (+ = squashed, - = stretched).
    var squash: Float { sq }
    /// 0...1 how hard the jelly is working now (squash and sway relative to their walking caps).
    var intensity: Float { active ? min(1, max(abs(sq) / capSqV, simd_length(sway) / (capSqV * H), abs(tw) / capTwV)) : 0 }

    func reset() {
        sq = 0; sqV = 0; sway = .zero; swayV = .zero; tw = 0; twV = 0; active = false
        boost = 0; peakSpeed = 0; havePrev = false; vel = .zero; yawRate = 0; stillT = 0; wasSwinging = false; haveVY = false
    }

    // MARK: drive

    /// One fixed step. `landing`: footfall / impact impulse already scaled (squash velocity added now); `run` 0...1 raises the caps.
    func advance(dt: Float, root: SIMD2<Float>, yaw: Float, landing: Float, run: Float) {
        center = root
        var dv = SIMD2<Float>(0, 0), dw: Float = 0
        if havePrev {
            var raw = (root - prevRoot) / dt
            var wr = wrapPi(yaw - prevYaw) / dt
            if simd_length(raw) > 6 || abs(wr) > 12 { raw = .zero; wr = 0; vel = .zero; yawRate = 0 }     // a teleport / snap, not a walk
            let a = dt / (dt + 0.04)
            let v1 = vel + (raw - vel) * a, w1 = yawRate + (wr - yawRate) * a
            dv = v1 - vel; dw = w1 - yawRate
            vel = v1; yawRate = w1
        }
        havePrev = true; prevRoot = root; prevYaw = yaw

        let speed = simd_length(vel)
        let moving = speed > 0.02 || abs(yawRate) > 0.05 || landing > 0
        stillT = moving ? 0 : stillT + dt
        boost = max(boost - dt / 0.6, min(1, max(run, (speed / Self.walkSpeed - 1) * 0.7)))

        // the settle wobble: he stops dead from a walk / run -> one big squash ripple and a sway kick forward (the sway spring then rocks back)
        peakSpeed = max(speed, peakSpeed - dt * 1.5)
        if !legacy && speed < 0.12 && peakSpeed > 0.5 * Self.walkSpeed {
            let k = min(2, peakSpeed / Self.walkSpeed)
            sqV += Self.stopWobble * (0.6 + 0.4 * k)
            swayV += simd_length(vel) > 1e-4 ? vel / simd_length(vel) * 0.5 * k : SIMD2<Float>(0, 0)
            peakSpeed = 0
        }
        if landing > 0 { sqV += landing }
        swayV -= dv * swayK
        twV -= dw * Self.twistGain

        // springs (2 substeps, semi-implicit), extra damping once he has been still a moment so they settle to exactly 0
        let calm = smooth((stillT - 0.1) / 0.2)
        let n = 2, h = dt / Float(n)
        let ws = 2 * .pi * Self.squashHz, wy = 2 * .pi * Self.swayHz
        for _ in 0..<n {
            let ds = Self.squashZeta * 2 * ws + 14 * calm, dy = Self.swayZeta * 2 * wy + 14 * calm
            sqV += (-ws * ws * sq - ds * sqV) * h; sq += sqV * h
            swayV += (-wy * wy * sway - dy * swayV) * h; sway += swayV * h
            twV += (-wy * wy * tw - dy * twV) * h; tw += twV * h
        }
        if stillT > 0.15, abs(sq) < 2e-4, abs(sqV) < 2e-3, simd_length(sway) < 3e-4, simd_length(swayV) < 3e-3, abs(tw) < 2e-4, abs(twV) < 2e-3 {
            sq = 0; sqV = 0; sway = .zero; swayV = .zero; tw = 0; twV = 0; active = false
        } else {
            active = true
        }
    }

    /// Caps grow from the walking values (boost 0) to the run / landing values (boost 1).
    func capScale(_ b: Float) -> Float { 1 + capGrow * b }

    private func wrapPi(_ a: Float) -> Float {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }
    private func smooth(_ x: Float) -> Float { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }

    // MARK: apply

    /// Displace the skinned vertices (`dyn`: 6 floats per vertex, position first). A no-op unless `active`.
    func apply(_ dyn: UnsafeMutablePointer<Float>, count: Int) {
        guard enabled, active else { return }
        let sc = capScale(boost)
        let capSq = capSqV * sc, capSway = capSqV * H * sc, capTw = capTwV * sc
        let sqE = capSq * tanhf(sq / capSq)
        let swL = simd_length(sway)
        let swE = swL > 1e-7 ? sway * (capSway * tanhf(swL / capSway) / swL) : SIMD2<Float>(0, 0)
        let twE = capTw * tanhf(tw / capTw)
        let invH = 1 / H, cx = center.x, cz = center.y
        for v in 0..<count {
            let o = 6 * v
            let t = min(1, max(0, ((dyn[o + 1] - floorY) * invH - 0.1) * (1 / 0.9)))
            if t == 0 { continue }
            let sm = t * t * (3 - 2 * t)                       // 0 on the feet ... 1 at the crown
            let w = sm * sm                                    // the sway / twist live in the upper body
            let rx = dyn[o] - cx, rz = dyn[o + 2] - cz
            let bulge = 0.5 * sqE * 4 * sm * (1 - sm)          // volume: a little wider at the belly while compressed
            dyn[o] += swE.x * w + twE * w * rz + rx * bulge
            dyn[o + 1] -= sqE * H * sm
            dyn[o + 2] += swE.y * w - twE * w * rx + rz * bulge
        }
    }
}

// MARK: - brain adapter

extension JellyJiggle {
    /// Call once after each `brain.tick` (fixed step). Derives the footfalls (a swing foot landing), hop landings (a sudden stop of the
    /// body falling) and the root / heading from the brain; `sim` supplies the vertical speed.
    @MainActor func tick(brain: BlobBrain, sim: SoftBody, dt: Float) {
        let swinging = brain.feet.swinging
        var landing: Float = 0
        let speed = simd_length(vel)
        if wasSwinging && !swinging {
            landing = Self.footImpulse * impulseK * (0.75 + 0.25 * min(3, speed / Self.walkSpeed))
        }
        wasSwinging = swinging
        let cy = sim.centroid().y
        if haveVY {
            let vy = (cy - prevCY) / dt
            if prevVY < -0.5 && vy - prevVY > 0.6 { landing += min(3, (vy - prevVY)) * Self.hopImpulse }
            prevVY = vy
        } else { haveVY = true; prevVY = 0 }
        prevCY = cy
        if brain.jellyKick > 0 { landing += brain.jellyKick; brain.jellyKick = 0 }
        let impact = landing > Self.footImpulse * 1.2 ? 1 : 0
        advance(dt: dt, root: SIMD2(brain.px, brain.pz), yaw: brain.yaw, landing: landing, run: max(brain.runW, Float(impact)))
    }
}
