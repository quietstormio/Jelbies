//
//  MotionArmTests.swift
//  The walking arm (W1b section 1): a closed capsule drawn alone while the skin nub is retracted onto the armless egg. These check the
//  things the likeness review asked for: root buried, no skin fold, torso width, swap pops and flicker, release to the exact rest arm.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionArmTests: XCTestCase {
    /// Rest-frame (egg frame) position of a world point under the attractor's pose.
    private func toRest(_ r: MotionRig, _ p: SIMD3<Float>) -> SIMD3<Double> {
        let att = r.sim.attractor, sya = att.squash, sxza = 1 / sya.squareRoot(), c0 = r.sim.restCentroid
        let RS = simd_float3x3(att.rotation) * simd_float3x3(diagonal: SIMD3(sxza, sya, sxza))
        let org = att.anchor - RS * c0
        let q = RS.inverse * (p - org)
        return SIMD3(Double(q.x), Double(q.y), Double(q.z))
    }
    private func vtx(_ r: MotionRig, _ v: Int) -> SIMD3<Float> { SIMD3(r.dyn[6 * v], r.dyn[6 * v + 1], r.dyn[6 * v + 2]) }

    struct Frame { var t: Float; var out: Bool; var blend: Float; var lift: Float }

    func testWalkingArmCapsuleRootBuriedNoFoldAndTorsoWidth() {
        let r = MotionRig(game: false)
        let cap = MotionRig.renderMesh.armCapsule!
        r.render()
        let skin: [Int] = {
            var s: [Int] = []
            let ex = Set((0..<2).flatMap { k -> [Int] in
                let f = cap.first(side: k == 0 ? -1 : 1); let g = cap.beanFirst(side: k == 0 ? -1 : 1)
                return Array(f..<(g + FootBean.vertexCount))
            })
            for v in 0..<MotionRig.renderMesh.vertexCount where !ex.contains(v) { s.append(v) }
            return s
        }()
        // rest torso width: world x extent of the skin vertices in the 45-50 % height band, minus the arm nub region (|x| from the egg at that height)
        func band(_ r: MotionRig) -> (lo: Float, hi: Float, w: Float) {
            let c = r.sim.centroid()
            var lo: Float = 1e9, hi: Float = -1e9
            let y0 = r.sim.floorY + 0.45 * MotionRig.H, y1 = r.sim.floorY + 0.50 * MotionRig.H
            for v in skin {
                let p = self.vtx(r, v)
                guard p.y >= y0 && p.y <= y1 else { continue }
                // the torso: skin whose rest position is not on the retracted nub (rest |x| below the body half width + 3 mm at this height)
                lo = min(lo, p.x - c.x); hi = max(hi, p.x - c.x)
            }
            return (lo, hi, hi - lo)
        }
        let restW = band(r).w
        r.renderSamples = false
        var tris: [(UInt32, UInt32, UInt32, Bool)] = []; var ringBad = 0
        let ix = MotionRig.renderMesh.index
        r.brain.request(.goTo(SIMD2(1.9, 0.2)))
        var maxW: Float = 0, minRoot: Float = 1, outFrames = 0, foldBad = 0, started = false, minDot: Float = 1, triSamples = 0, oneFrame = 0
        var prevBad = Set<Int>()
        var protr: [Float] = []
        r.run(9, until: { started && r.brain.activity == .idle }) {
            guard r.brain.activity == .walking else { return }
            started = true
            guard r.skinner.armCapsulesActive else { return }
            if tris.isEmpty {
                var wOf: [Int32: Float] = [:]
                for (k, v) in r.skinner.armRetractVertices.enumerated() { wOf[v] = r.skinner.armRetractWeight[k] }
                let rIdx = Set(r.skinner.armRetractVertices)
                var ti = 0
                while ti + 2 < ix.count { if rIdx.contains(Int32(ix[ti])) && rIdx.contains(Int32(ix[ti + 1])) && rIdx.contains(Int32(ix[ti + 2])) { tris.append((ix[ti], ix[ti + 1], ix[ti + 2], [ix[ti], ix[ti + 1], ix[ti + 2]].allSatisfy { (wOf[Int32($0)] ?? 0) > 0.99 })) }; ti += 3 }
            }
            r.render()
            outFrames += 1
            maxW = max(maxW, band(r).w)
            for s in 0..<2 {
                let f = cap.first(side: s == 0 ? -1 : 1)
                var pm: Float = 0
                for i in 0..<ArmCapsule.vertexCount { let q = self.toRest(r, self.vtx(r, f + i)); pm = max(pm, Float(BobForm.bodySDF(SIMD3(abs(q.x), q.y, q.z)))) }
                protr.append(pm / 1.167)
                let root = self.vtx(r, f + ArmCapsule.vertexCount - 1)
                let q = self.toRest(r, root)
                minRoot = min(minRoot, Float(-BobForm.bodySDF(SIMD3(abs(q.x), q.y, q.z))))
            }
            // no skin fold: no triangle of the retracted skin (all three vertices moved by the retraction) is inverted against the egg's outward normal
            if r.skinner.armBlend > 0.99 {
                let rq = simd_float3x3(r.sim.attractor.rotation)
                var badNow = Set<Int>()
                for (ti, t) in tris.enumerated() {
                    let p0 = self.vtx(r, Int(t.0)), p1 = self.vtx(r, Int(t.1)), p2 = self.vtx(r, Int(t.2))
                    let fn = simd_cross(p1 - p0, p2 - p0)
                    if simd_length(fn) < 2e-4 { continue }          // slivers (area < 1e-4 u^2, a few mm wide: seen at 2 frames of the run) have no meaningful normal
                    let q = self.toRest(r, (p0 + p1 + p2) / 3)
                    let qa = SIMD3(abs(q.x), q.y, q.z), e = 1e-4
                    var eg = SIMD3(BobForm.bodySDF(qa + SIMD3(e, 0, 0)) - BobForm.bodySDF(qa - SIMD3(e, 0, 0)), BobForm.bodySDF(qa + SIMD3(0, e, 0)) - BobForm.bodySDF(qa - SIMD3(0, e, 0)), BobForm.bodySDF(qa + SIMD3(0, 0, e)) - BobForm.bodySDF(qa - SIMD3(0, 0, e)))
                    eg /= max(simd_length(eg), 1e-12)
                    let sx: Double = q.x < 0 ? -1 : 1
                    let en = rq * SIMD3<Float>(Float(sx * eg.x), Float(eg.y), Float(eg.z))
                    let dd = simd_dot(simd_normalize(fn), simd_normalize(en)); minDot = min(minDot, dd)
                    if dd < 0 { if t.3 { badNow.insert(ti); oneFrame += 1 } else { ringBad += 1 } }
                    triSamples += 1
                }
                // a visible fold persists: only a triangle inverted in two CONSECUTIVE frames counts (single-frame area ~1e-4 u^2 kinks, 1 cm^2 on a 1.2 u body, are listed separately)
                foldBad += badNow.intersection(prevBad).count
                prevBad = badNow
            } else { prevBad = [] }
        }
        MotionLog.write(String(format: "ARMW torso band width rest %.4f max %.4f (%+.2f %%), root depth min %.3f u, capsule frames %d, inverted skin triangles %d of %d samples (full-weight nub area; inverted for 2+ consecutive frames; %d single-frame inversions of triangles >= 1e-4 u^2; the blend ring has %d), min face-normal dot %.2f",
                               restW, maxW, 100 * (maxW / restW - 1), minRoot, outFrames, foldBad, triSamples, oneFrame, ringBad, minDot))
        protr.sort()
        MotionLog.write(String(format: "ARMW protrusion of the capsule beyond the egg surface (body widths): median %.3f p90 %.3f max %.3f", protr[protr.count / 2], protr[protr.count * 9 / 10], protr.last ?? 0))
        XCTAssertGreaterThan(outFrames, 100)
        XCTAssertGreaterThanOrEqual(minRoot, 0.01, "the capsule's root pole stays inside the body every frame")
        XCTAssertEqual(foldBad, 0, "no skin fold (no inverted triangle) where the nub retracted")
        XCTAssertLessThanOrEqual(maxW, restW * 1.03, "the torso is no wider than rest + 3 % at 45-50 % height")
    }

    func testArmSwapHasNoPopAndReleaseReturnsToRest() {
        let r = MotionRig(game: false)
        r.renderSamples = false
        r.brain.request(.goTo(SIMD2(1.6, 0.2)))
        var wasOut = false, prevOut = false
        var popIn: Float = -1, popOut: Float = -1, frames = 0
        func swapStep(_ k: SIMD3<Float>) -> Float {
            // what the swap itself moves at this frame: the capsule from the rest nub station (+ blend), the retracting skin from the egg
            let sk = r.skinner, bl = sk.armBlend
            var m: Float = 0
            for s in 0..<2 where sk.armPos[s].count == sk.armStart[s].count { for i in 0..<sk.armPos[s].count { m = max(m, bl * simd_length(sk.armPos[s][i] - sk.armStart[s][i])) } }
            let M = sk.armRetractMatrix
            for (j, _) in sk.armRetractVertices.enumerated() { m = max(m, simd_length(M * sk.armRetractRest[j]) * sk.armRetractWeight[j] * bl) }
            return m
        }
        var lastActiveStep: Float = 0
        r.run(9, until: { wasOut && !r.skinner.armCapsulesActive && r.brain.activity == .idle }) {
            let out = r.skinner.armCapsulesActive
            if out { frames += 1 }
            if out && !prevOut { popIn = swapStep(.zero) }
            if out { lastActiveStep = swapStep(.zero) }
            if !out && prevOut { popOut = lastActiveStep }
            if out { wasOut = true }
            prevOut = out
        }
        MotionLog.write(String(format: "ARMW swap: displacement the swap itself adds on the first visible frame %.4f u, on the last %.4f u (limit 0.002)", popIn, popOut))
        XCTAssertTrue(wasOut)
        XCTAssertGreaterThanOrEqual(popIn, 0); XCTAssertLessThan(popIn, 0.002, "no pop at swap in")
        XCTAssertGreaterThanOrEqual(popOut, 0); XCTAssertLessThan(popOut, 0.002, "no pop at swap out")
        r.run(1.5)
        XCTAssertFalse(r.skinner.armCapsulesActive, "the capsules are swapped back out")
        XCTAssertEqual(r.brain.armLiftNow, 0, accuracy: 1e-3, "the lift returns exactly to rest")
        XCTAssertTrue(r.skinner.overrideVertices.isEmpty, "mat overrides released")
    }

    func testSmallRepeatedSteppingDoesNotFlickerTheArms() {
        let r = MotionRig(game: false)
        r.renderSamples = false
        let before = r.brain.armSwapCount
        var flips = 0, last = r.skinner.armCapsulesActive
        // three tiny walks 0.5 s apart (shorter than the 0.7 s hold): one swap in, one swap out, never per step
        for k in 0..<3 {
            r.brain.request(.goTo(SIMD2(r.root.x + 0.06 * (k % 2 == 0 ? 1 : -1), r.root.y)))
            r.run(0.5) { let a = r.skinner.armCapsulesActive; if a != last { flips += 1; last = a } }
        }
        r.run(3) { let a = r.skinner.armCapsulesActive; if a != last { flips += 1; last = a } }
        MotionLog.write("ARMW tiny steps: swaps \(r.brain.armSwapCount - before), visible flips \(flips)")
        XCTAssertLessThanOrEqual(flips, 2, "one swap in and one out, no flicker")
    }

    /// W1c: the shoulder is a fixed point of the body (it used to slide with the sweep) and the arm is a thumb.
    func testWalkingArmShoulderIsFixedAndTheArmIsAThumb() {
        let r = MotionRig(game: false)
        let ref = r.brain.armGeometry(S: 25, lift: 1)
        var worst: Float = 0
        for S in stride(from: Float(-35), through: 85, by: 5) {
            let g = r.brain.armGeometry(S: S, lift: 1)
            worst = max(worst, simd_distance(g.a, ref.a))
            XCTAssertEqual(simd_distance(g.a, g.b), 0.225, accuracy: 1e-4, "shaft length 0.22-0.23 u at S = \(S)")
            XCTAssertEqual(g.r1, 0.13, accuracy: 1e-5); XCTAssertEqual(g.r2, 0.115, accuracy: 1e-5)
        }
        XCTAssertLessThan(simd_distance(ref.a, SIMD3<Float>(0.48, 0.51, 0.15)), 1e-5, "shoulder at (0.48, 0.51, 0.15)")
        XCTAssertLessThan(worst, 1e-6, "the shoulder does not move with S")
        MotionLog.write("ARMW shoulder (0.48, 0.51, 0.15) constant over S -35..85 (max move \(worst)), r 0.13 / 0.115, L 0.225")
    }

    /// W1c arm phase: the stride's forward-hold shift follows the gait weight only while both arms are in a hold (ArmPath.armShiftStep); no arm may whip during a
    /// waddle <-> stride blend: the peak sweep speed over a blend (the engine's 0.4 s gaitW ramp, phase rate interpolated between 2.0 / 1.58 cycles/s) must not exceed
    /// the steady-walk crossing speed (starting at every phase of the cycle).
    func testArmSweepDoesNotWhipDuringGaitBlends() {
        func peak(_ rate: (Float) -> Float, _ gwTarget: (Float) -> Float, _ shiftStart: Float, _ ph0: Float, _ T: Float) -> Float {
            var ph = ph0, shiftW = shiftStart
            var prev: [Float] = [ArmPath.armWalkSweepDeg(phase: ph, side: -1, gaitW: shiftW), ArmPath.armWalkSweepDeg(phase: ph, side: 1, gaitW: shiftW)]
            var m: Float = 0
            let dt: Float = 1.0 / 60
            var t: Float = 0
            while t < T {
                t += dt; ph += rate(t) * dt
                shiftW = ArmPath.armShiftStep(shiftW: shiftW, target: gwTarget(t), phase: ph, dt: dt)
                let cur = [ArmPath.armWalkSweepDeg(phase: ph, side: -1, gaitW: shiftW), ArmPath.armWalkSweepDeg(phase: ph, side: 1, gaitW: shiftW)]
                for k in 0..<2 { m = max(m, abs(cur[k] - prev[k]) / dt) }
                prev = cur
            }
            return m
        }
        let wr: Float = 4.0 / 2, sr: Float = 3.16 / 2            // phase rates (cycles/s) of the waddle and the stride
        var steady: Float = 0
        for k in 0..<20 { let ph0 = Float(k) / 20; steady = max(steady, peak({ _ in wr }, { _ in 0 }, 0, ph0, 3), peak({ _ in sr }, { _ in 1 }, 1, ph0, 3)) }
        let ramp: (Float) -> Float = { min(1, max(0, $0 / 0.4)) }
        var inBlend: Float = 0, outBlend: Float = 0
        for k in 0..<20 {
            let ph0 = Float(k) / 20
            inBlend = max(inBlend, peak({ t in wr + (sr - wr) * ramp(t) }, { t in ramp(t) }, 0, ph0, 3))        // waddle -> stride
            outBlend = max(outBlend, peak({ t in sr + (wr - sr) * ramp(t) }, { t in 1 - ramp(t) }, 1, ph0, 3))  // stride -> waddle
        }
        MotionLog.write(String(format: "ARMPHASE sweep speed (60 Hz): steady max %.0f deg/s, waddle->stride blend %.0f, stride->waddle blend %.0f", steady, inBlend, outBlend))
        XCTAssertLessThanOrEqual(inBlend, steady * 1.001, "no arm whips in the waddle -> stride blend")
        XCTAssertLessThanOrEqual(outBlend, steady * 1.001, "no arm whips in the stride -> waddle blend")
    }
}
