//
//  Snuggle.swift
//  Multi-finger petting: up to two EXTRA fingers (three in all) each rest on / rub a different Jelbie in the close-up.
//  The first finger keeps the full TouchPlay (zones, cheeks, pick up, throw). An extra finger only pets: a soft dent under the
//  fingertip (the Jelbie's own SoftBody press), the happy squint + blush + purr squash, a heart now and then, a soft haptic tick,
//  and attention credit at the normal pet rate. It never grabs, lifts or throws.
//

import Foundation
import CoreGraphics
import simd

final class SnuggleFinger {
    let pointer: ObjectIdentifier
    private(set) var jelly: Int
    var point: CGPoint
    /// Frames the finger has been over a different Jelbie than `jelly` (the swipe hand-over waits two checks so a seam does not flicker).
    var handCandidate: (id: Int, n: Int)?

    private(set) var contact = false
    private(set) var ramp: Float = 0
    private(set) var love: Float = 0
    private(set) var speed: Float = 0
    private var prevLocal: SIMD3<Float>?
    private var lastHit: BodyEllipsoid.Hit?
    private var easedCenter: SIMD3<Float>?
    private var movingT: Float = 0, gapT: Float = 0, restT: Float = 0, calmT: Float = 0
    private var happyOn = false
    private var purrT: Float = 0, purrGap: Float = 0, purrLevel: Float = 0, purrPhase: Float = 0
    private var heartT: Float = 0.4
    private var wasEnjoying = false
    private var hapticAt: Double = -1
    private var eyesTouched = false, savedAutoBlink = true
    private var jiggleT: Float = 0
    private var lean = SIMD2<Float>(0, 0)

    /// Attention earned since the last credit (`dt * rate`).
    var owed: Float = 0

    struct Out { var heart = false; var haptic: Float = 0 }

    init(pointer: ObjectIdentifier, jelly: Int, point: CGPoint) { self.pointer = pointer; self.jelly = jelly; self.point = point }

    var enjoying: Bool { love > 0.85 || purrLevel > 0.5 }

    /// The swipe moved this finger onto another Jelbie: the one it leaves is released by the caller first.
    func retarget(to id: Int) {
        jelly = id; handCandidate = nil
        contact = false; ramp = 0; love = 0; speed = 0; prevLocal = nil; lastHit = nil; easedCenter = nil
        movingT = 0; gapT = 0; restT = 0; calmT = 0; happyOn = false; purrT = 0; purrGap = 0; purrLevel = 0; lean = .zero; wasEnjoying = false
    }

    func update(dt: Float, now: Double, hit: BodyEllipsoid.Hit?, sim: SoftBody, skinner: Skinner, brain: BlobBrain?) -> Out {
        var out = Out()
        let wasContact = contact
        contact = hit != nil
        var raw: Float = 0
        if let h = hit, let p = prevLocal, dt > 0 { raw = simd_length(h.local - p) / dt }
        prevLocal = hit?.local
        speed += (raw - speed) * (1 - expf(-dt / 0.05))
        if speed < 0.002 { speed = 0 }

        // the dent: the same fingertip sphere as the first finger, on this Jelbie's own body
        ramp = max(0, min(1, ramp + (contact ? 1 / 0.12 : -1 / 0.10) * dt))
        if let h = hit { lastHit = h }
        if let h = hit ?? lastHit, ramp > 0 {
            let depth = TouchPlay.dentDepth * ramp * ramp * (3 - 2 * ramp)
            let target = h.point + h.normal * (TouchPlay.fingerRadius - depth)
            if let e = easedCenter, sim.pressing { easedCenter = e + (target - e) * (1 - expf(-dt * 28)) } else { easedCenter = target }
            sim.setPress(center: easedCenter!, radius: TouchPlay.fingerRadius)
            skinner.normalSmoothing = ramp
            skinner.smoothCenter = h.point
        } else if ramp <= 0 {
            if sim.pressing { sim.endPress() }
            lastHit = nil; easedCenter = nil; skinner.normalSmoothing = 0
        }
        if contact && !wasContact { out.haptic = 0.22 }

        // happiness: stroking (or a finger that rests a moment) closes the eyes; a beat after it stops they open
        if contact && speed > TouchPlay.strokeSpeed { movingT += dt; gapT = 0 } else { gapT += dt; if gapT > 0.25 { movingT = 0 } }
        restT = contact ? restT + dt : 0
        if movingT > TouchPlay.happyAfter || restT > 1.0 { happyOn = true; calmT = 0 }
        else if happyOn { calmT += dt; if calmT > TouchPlay.openAfter { happyOn = false } }
        love = max(0, min(1, love + (happyOn ? 1 / 0.25 : -1 / 0.35) * dt))

        // purr after ~2 s of good stroking
        let good = contact && speed > 0.25 && speed < 4.5
        if contact && speed > 5 { purrT = 0; purrGap = 0 }
        else if good { purrT += dt; purrGap = 0 }
        else { purrGap += dt; if purrGap > 0.5 { purrT = 0 } }
        purrLevel = max(0, min(1, purrLevel + (purrT > TouchPlay.purrAfter ? 1 / 0.5 : -1 / 0.3) * dt))
        purrPhase += dt * TouchPlay.purrHz; if purrPhase > 1 { purrPhase -= 1 }

        // expression: eyes, blush, a small lean into the finger, a slight squash
        let k = love * love * (3 - 2 * love)
        let want = 1 - k
        if want < 0.999 {
            if !eyesTouched { eyesTouched = true; savedAutoBlink = skinner.autoBlink }
            skinner.autoBlink = false
            skinner.setEyeOpenness(want)
        } else if eyesTouched {
            eyesTouched = false; skinner.setEyeOpenness(1); skinner.autoBlink = savedAutoBlink
        }
        var wantLean = SIMD2<Float>(0, 0)
        if let l = hit?.local, love > 0 { wantLean = SIMD2(0.07 * love, -0.22 * max(-1, min(1, l.x / 0.66)) * love) }
        lean += (wantLean - lean) * (1 - expf(-dt * 5))
        jiggleT += dt
        let jig = love * love
        let roll = lean.y + 0.03 * jig * sinf(2 * .pi * 2.0 * jiggleT)
        let sq = 1 + 0.025 * jig * sinf(2 * .pi * 4.0 * jiggleT) + 0.016 * purrLevel * sinf(2 * .pi * purrPhase)
        if let brain {
            if enjoying { brain.blushBump(hold: 2.2, peak: 0.7) }
            if enjoying && !wasEnjoying { brain.postEvent(.petted) }
            if lean.x == 0 && roll == 0 && sq == 1 { brain.clearTouch() } else { brain.applyTouch(pitch: lean.x, roll: roll, squash: sq) }
        }
        wasEnjoying = enjoying

        // hearts while he really enjoys it
        if enjoying { heartT -= dt; if heartT <= 0 { heartT = 0.8 + 0.5 * Float(now.truncatingRemainder(dividingBy: 1)); out.heart = true } }
        else { heartT = min(heartT, 0.4) }

        // a soft tick while the finger moves over him (the caller rate-limits across all fingers)
        if ramp > 0.4, speed > TouchPlay.strokeSpeed, now - hapticAt > 0.22 {
            hapticAt = now
            out.haptic = max(out.haptic, min(0.3, 0.10 + 0.10 * min(1, speed / 2)) + 0.1 * purrLevel)
        }
        return out
    }

    /// Credit this frame (the normal pet rates), called every frame the finger is down.
    func credit(dt: Float) {
        if (contact && speed > TouchPlay.strokeSpeed * 0.5) || purrLevel > 0.5 {
            owed += dt * (purrLevel > 0.5 ? NeedsTuning.purrRate : NeedsTuning.petRate)
        }
    }

    /// The finger left (or was cancelled): the dent springs back, eyes and lean are given back.
    func release(sim: SoftBody, skinner: Skinner, brain: BlobBrain?) {
        if sim.pressing { sim.endPress() }
        skinner.normalSmoothing = 0
        if eyesTouched { eyesTouched = false; skinner.setEyeOpenness(1); skinner.autoBlink = savedAutoBlink }
        brain?.clearTouch()
        retarget(to: jelly)
    }
}
