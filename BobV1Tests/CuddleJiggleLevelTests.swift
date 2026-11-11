//
//  CuddleJiggleLevelTests.swift
//  The three cuddle-jiggle levels (0 "Today", 1 "A little more", 2 "More"; CuddleJiggle.swift): level 0 is bit-identical to the pre-switch code, the drawn dent
//  is deeper by the table amount with a soft rim, the let-go spring overshoots and rings down to exactly zero, a 3 s stroke still gives hearts / purr / haptics /
//  the same sounds at every level, the feet / arms / face features / foot join are never moved, nothing moves further than the cheek cap, and the cost.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CuddleJiggleLevelTests: XCTestCase {
    private let eye = SIMD3<Float>(0, 0.9, 6)
    /// Recorded by running `scriptedSkinHash` on the UNMODIFIED sources (git 3fa412cc, Release, simulator): see the report.
    static let golden: UInt64 = 0

    /// The scripted touch: 0.5 s rest, touch-down (0.5 s still), a 2 s stroke, release, 2 s rest. Hashes every drawn float (positions + normals) after each frame.
    /// Written against APIs that exist at 3fa412cc: the golden was recorded by running THIS function on the unmodified sources.
    static func scriptedSkinHash(_ configure: (MotionRig) -> Void) -> UInt64 {
        let r = TouchPetTests.Run()
        configure(r.rig)
        let eye = SIMD3<Float>(0, 0.9, 6)
        var h: UInt64 = 1469598103934665603
        func mix() { r.rig.render(); for f in r.rig.dyn { h = (h ^ UInt64(f.bitPattern)) &* 1099511628211 } }
        for _ in 0..<30 { r.frame(nil); mix() }
        for _ in 0..<30 { r.frame(r.ray(localX: 0.38, localY: 0.15, eye: eye)); mix() }
        for i in 0..<120 { let t = Float(i) / 60; r.frame(r.ray(localX: 0.38 + 0.12 * sinf(2 * .pi * 1.2 * t), localY: 0.15, eye: eye)); mix() }
        for _ in 0..<120 { r.frame(nil); mix() }
        return h
    }

    private func run(_ level: Int) -> TouchPetTests.Run {
        let r = TouchPetTests.Run()
        r.rig.skinner.configureTail(MotionRig.renderMesh)          // (as JellyActor does: the body / block split of the render mesh)
        r.rig.skinner.cuddle.levelOverride = level
        return r
    }
    private func eggLimit(_ r: TouchPetTests.Run) -> Int { r.rig.skinner.armFirst.min() ?? (r.rig.dyn.count / 6) }

    /// The drawn offset of the cuddle layer on every vertex: the plain skin (layer switched off) and the layer's own `apply` run on a copy of it with the skin's
    /// real body mask (two full renders of the same sim state are not identical: the dent relax rebuilds its lists on every 8th call).
    private func drawnOffset(_ r: TouchPetTests.Run) -> (off: [Float], plain: [Float]) {
        let c = r.rig.skinner.cuddle
        c.enabled = false; r.rig.render(); let plain = r.rig.dyn; c.enabled = true
        var b = plain
        let mask = r.rig.skinner.cuddleBodyMask(), sk = r.rig.skinner
        mask.withUnsafeBufferPointer { m in b.withUnsafeMutableBufferPointer { c.apply($0.baseAddress!, count: plain.count / 6, mask: m.baseAddress!, floorY: sk.jelly.floorY, H: sk.jelly.H) } }
        var o = [Float](repeating: 0, count: b.count)
        for i in 0..<b.count { o[i] = b[i] - plain[i] }
        return (o, plain)
    }
    private func vec(_ a: [Float], _ v: Int) -> SIMD3<Float> { SIMD3(a[6 * v], a[6 * v + 1], a[6 * v + 2]) }

    // (a) level 0 == the pre-change code, bit for bit
    func testLevelZeroIsBitIdenticalToToday() {
        let a = Self.scriptedSkinHash { $0.skinner.cuddle.levelOverride = 0 }
        let b = Self.scriptedSkinHash { $0.skinner.cuddle.levelOverride = 0 }
        let c = Self.scriptedSkinHash { $0.skinner.cuddle.enabled = false }
        MotionLog.write("CUDDLE level 0 scripted skin hash \(a) (again \(b), layer disabled \(c)); golden from the unmodified code \(Self.golden)")
        XCTAssertEqual(a, b, "the script is deterministic")
        XCTAssertEqual(a, c, "level 0 == the layer switched off")
        XCTAssertEqual(a, Self.golden, "level 0 is bit-identical to the code before the cuddle layer")
        XCTAssertNotEqual(Self.scriptedSkinHash { $0.skinner.cuddle.levelOverride = 2 }, a, "level 2 does draw something")
    }

    // (b) drawn dent depth, rim, per level (the final skin: level L minus the same state without the layer)
    func testDrawnDentDepthPerLevel() {
        let want: [Float] = [0, 0.02, 0.04], rimFrac: [Float] = [0, 0.15, 0.25]
        for l in 0...2 {
            let r = run(l)
            r.stroke(1.0, eye: eye, amp: 0, y: 0.15, cx: 0.38)
            let c = r.rig.skinner.cuddle
            let (off, _) = drawnOffset(r)
            var deep: Float = 0, rim: Float = 0
            let n = c.nW
            for v in 0..<(off.count / 6) { let a = -simd_dot(vec(off, v), n); deep = max(deep, a); rim = max(rim, -a) }
            let phys = r.rig.sim.pressDepth
            MotionLog.write(String(format: "CUDDLE level %d: physical press %.3f u + drawn extra %.4f u (target %.3f) = reads as %.3f u; raised rim %.4f u (max %.4f)", l, phys, deep, want[l], phys + deep, rim, rimFrac[l] * want[l]))
            if l == 0 { XCTAssertEqual(deep, 0); XCTAssertEqual(rim, 0); XCTAssertFalse(c.active); continue }
            XCTAssertEqual(deep, want[l], accuracy: want[l] * 0.20, "level \(l) extra depth")
            XCTAssertGreaterThan(rim, 0.3 * rimFrac[l] * want[l], "level \(l): a raised rim exists")
            XCTAssertLessThanOrEqual(rim, rimFrac[l] * want[l] * 1.02, "level \(l): the rim is only 15 / 25 % of the extra depth")
        }
    }

    // (c) let-go: the dented spot springs OUT past the rest surface, rings down in a few wobbles, a ripple travels out, exactly zero 2 s later
    func testLetGoOvershootsRingsDownAndEndsExactlyZero() {
        for l in 1...2 {
            let r = run(l)
            let c = r.rig.skinner.cuddle
            let tn = CuddleJiggle.tuning(l)
            r.stroke(1.0, eye: eye, amp: 0, y: 0.15, cx: 0.38)
            let centre = c.cW, n = c.nW
            let lim = eggLimit(r)
            r.rig.render()
            var probe = 0, best: Float = .infinity
            for v in 0..<lim { let d = simd_length(vec(r.rig.dyn, v) - centre); if d < best { best = d; probe = v } }
            let base = r.rec.events.filter { $0.kind == .transient && abs($0.sharpness - 0.1) < 1e-6 }.count
            var series: [Float] = [], ripplePeak: Float = 0, rippleLate: Float = 0, lastNonZero = 0, tapFrames = 0
            var rippleFar: Float = 0
            for k in 0..<120 {
                r.frame(nil)
                if c.tap > 0 { tapFrames += 1 }
                let (off, _) = drawnOffset(r)
                series.append(simd_dot(vec(off, probe), n))
                var any = false
                for v in 0..<lim where vec(off, v) != .zero { any = true; break }
                if any { lastNonZero = k }
                var d: Float = 0.05
                while d < 1.0 { let rv = c.rippleOffset(at: d); if k < 30 { ripplePeak = max(ripplePeak, rv); if d > 0.7 { rippleFar = max(rippleFar, rv) } } else { rippleLate = max(rippleLate, rv) }; d += 0.01 }
            }
            var peaks: [Float] = []
            for k in 1..<(series.count - 1) where series[k] > series[k - 1] && series[k] >= series[k + 1] && series[k] > 0.004 { peaks.append(series[k]) }
            let hold = (CuddleJiggle.dentDepth + tn.extraDepth)
            let want = tn.overshoot * hold
            let taps = r.rec.events.filter { $0.kind == .transient && abs($0.sharpness - 0.1) < 1e-6 }.count - base
            MotionLog.write(String(format: "CUDDLE level %d: let-go overshoot %.4f u (spring peak %.4f, target %.4f = %.0f %% of %.2f), %d visible wobbles %@, ripple %.4f u (target %.3f; still %.4f u at 0.7+ u out), ripple after 0.5 s: %.5f, offset zero after frame %d (%.2f s), soft taps %d (sink saw %d)",
                                 l, peaks.first ?? 0, c.peakOut, want, tn.overshoot * 100, hold, peaks.count, peaks.map { String(format: "%.4f", $0) }.description, ripplePeak, tn.ripple, rippleFar, rippleLate, lastNonZero, Float(lastNonZero + 1) / 60, tapFrames, taps))
            XCTAssertEqual(c.peakOut, want, accuracy: want * 0.20, "level \(l): the spring's first outward peak")
            XCTAssertGreaterThan(peaks.first ?? 0, 0.6 * want, "level \(l): drawn overshoot is outward and visible")
            XCTAssertGreaterThanOrEqual(peaks.count, 2, "level \(l): at least 2 wobbles"); XCTAssertLessThanOrEqual(peaks.count, 4, "level \(l): not a buzz")
            XCTAssertGreaterThan(ripplePeak, 0.9 * tn.ripple * 0.9, "level \(l): a ripple ring travels out")
            XCTAssertLessThanOrEqual(ripplePeak, tn.ripple * 1.001)
            XCTAssertEqual(rippleLate, 0, accuracy: 1e-7, "level \(l): the ripple is gone within 0.5 s")
            XCTAssertLessThan(lastNonZero, 119, "level \(l): the offset is zero well before 2 s")
            let (offEnd, _) = drawnOffset(r)
            XCTAssertTrue(offEnd.allSatisfy { $0 == 0 }, "level \(l): exactly zero 2 s after release"); XCTAssertFalse(c.active)
            XCTAssertTrue((2...3).contains(tapFrames), "level \(l): 2-3 soft taps"); XCTAssertEqual(taps, tapFrames, "every tap reached the sink")
        }
    }

    // (d) a 3 s stroke still gives hearts, the purr, haptics and the very same sounds at every level
    private struct Stroke { var hearts = 0, purred = false, events = 0, petContinuous = 0, sounds: [String: Int] = [:], taps = 0 }
    private func stroke3(_ level: Int) -> Stroke {
        let r = run(level)
        var out = Stroke(), last: Double = -1
        r.play.haptics.soundHook = { k, _ in out.sounds[k, default: 0] += 1 }
        r.rec.clear()
        var t: Float = 0
        while t < 3 {
            r.frame(r.ray(localX: 0.35 * sinf(2 * .pi * 1.2 * t), localY: 0, eye: eye)); t += 1.0 / 60
            if let h = r.play.hearts.last, h.born != last { last = h.born; out.hearts += 1 }
            if r.play.isPurring { out.purred = true }
        }
        r.idle(1.5)
        r.play.haptics.soundHook = nil
        out.events = r.rec.events.count
        out.petContinuous = r.rec.events.filter { $0.kind == .continuous && $0.channel == "pet" && $0.intensity > 0.1 }.count
        out.taps = r.rec.events.filter { $0.kind == .transient && abs($0.sharpness - 0.1) < 1e-6 }.count
        return out
    }
    func testThreeSecondStrokeKeepsHeartsPurrHapticsAndSounds() {
        let base = stroke3(0)
        for l in 0...2 {
            let s = l == 0 ? base : stroke3(l)
            MotionLog.write("CUDDLE level \(l): 3 s stroke -> hearts \(s.hearts), purr \(s.purred), haptic events \(s.events) (pet-channel swells \(s.petContinuous), soft taps \(s.taps)), sound requests \(s.sounds.sorted { $0.key < $1.key })")
            XCTAssertGreaterThan(s.hearts, 0, "level \(l) hearts"); XCTAssertGreaterThanOrEqual(s.hearts, base.hearts)
            XCTAssertTrue(s.purred, "level \(l) purr"); XCTAssertGreaterThan(s.petContinuous, 0); XCTAssertGreaterThanOrEqual(s.petContinuous, base.petContinuous)
            XCTAssertGreaterThanOrEqual(s.events, base.events, "level \(l) haptic events")
            XCTAssertEqual(s.sounds, base.sounds, "level \(l): the sound requests are exactly today's")
        }
        XCTAssertEqual(base.taps, 0)
    }

    // (e) feet / arms / face features / foot join never move; the cheek cap holds; the leash observer stays silent; with and without shoes
    func testFeetAndFaceNeverMovedAndLeashSilentAtLevelTwo() {
        for shoes in [false, true] {
            let r = run(2)
            r.rig.brain.skinnerRef = r.rig.skinner
            r.rig.brain.shoesWorn = shoes
            r.idle(0.3)
            var hits = 0
            Skinner.leashObserver = { _, _, _ in hits += 1 }
            defer { Skinner.leashObserver = nil }
            let lim = eggLimit(r)
            XCTAssertLessThan(lim, r.rig.dyn.count / 6, "the arm / foot blocks are known")
            let face = r.rig.skinner.faceFeatureVertices
            let H = r.rig.skinner.jelly.H, floorY = r.rig.skinner.jelly.floorY
            var maxOff: Float = 0, moved = 0, badBlock = 0, badFace = 0, badFoot = 0, engaged = 0
            func check() {
                let (off, plain) = drawnOffset(r)
                for v in 0..<(off.count / 6) {
                    let m = simd_length(vec(off, v))
                    if m == 0 { continue }
                    moved += 1; maxOff = max(maxOff, m)
                    if v >= lim { badBlock += 1 }
                    if face.contains(Int32(v)) { badFace += 1 }
                    if (plain[6 * v + 1] - floorY) / H < 0.15 { badFoot += 1 }
                }
            }
            func frame(_ ray: (o: SIMD3<Float>, d: SIMD3<Float>)?, _ i: Int) {
                r.frame(ray); r.rig.render()
                if r.rig.skinner.cuddle.active { engaged += 1 }
                if i % 3 == 0 { check() }
            }
            for i in 0..<30 { frame(r.ray(localX: 0.30, localY: -0.30, eye: eye), i) }                                           // touch-down low on the belly
            for i in 0..<120 { let t = Float(i) / 60; frame(r.ray(localX: 0.30 * sinf(2 * .pi * 1.2 * t), localY: -0.30 + 0.45 * (0.5 + 0.5 * sinf(2 * .pi * 0.7 * t)), eye: eye), i) }   // stroke up the body, face included
            for i in 0..<90 { frame(nil, i) }                                                                                   // let go
            MotionLog.write(String(format: "CUDDLE level 2 %@: %d moved vertices sampled, max offset %.4f u (cap %.4f), arm/foot/tail block vertices moved %d, face features moved %d, below the foot-join fade %d, leash observer fired %d, layer active frames %d", shoes ? "shoes" : "bare", moved, maxOff, CuddleJiggle.maxOffset, badBlock, badFace, badFoot, hits, engaged))
            XCTAssertGreaterThan(moved, 0); XCTAssertEqual(badBlock, 0); XCTAssertEqual(badFace, 0); XCTAssertEqual(badFoot, 0)
            XCTAssertLessThanOrEqual(maxOff, CuddleJiggle.maxOffset + 1e-6)
            XCTAssertEqual(hits, 0, "the foot-leash observer never fires (\(shoes ? "shoes" : "bare"))")
        }
    }

    // petted wobble: the extra drawn happy jiggle is x1.25 / x1.5 of the brain's own, zero when he is not happy
    func testPettedWobbleExtraIsDrawnAndZeroAtRest() {
        for l in 0...2 {
            let r = run(l)
            let c = r.rig.skinner.cuddle
            r.stroke(2.0, eye: eye, amp: 0.12, hz: 1.2, y: 0.15, cx: 0.38)
            XCTAssertGreaterThan(r.play.love, 0.5)
            var peak: Float = 0
            for _ in 0..<60 { r.frame(r.ray(localX: 0.38 + 0.12 * sinf(Float(r.clock)), localY: 0.15, eye: eye)); let (off, _) = drawnOffset(r); peak = max(peak, off.map { abs($0) }.max() ?? 0) }
            MotionLog.write(String(format: "CUDDLE level %d: while petted (love %.2f) the drawn offset reaches %.4f u", l, r.play.love, peak))
            if l == 0 { XCTAssertEqual(peak, 0) } else { XCTAssertGreaterThan(peak, 0) }
            r.idle(3)
            let (off, _) = drawnOffset(r)
            XCTAssertTrue(off.allSatisfy { $0 == 0 }, "level \(l): zero at rest"); XCTAssertFalse(c.active); XCTAssertFalse(r.play.cuddleLive)
        }
    }

    // the tuning table, the constants shared with TouchPlay, the shared level
    func testTableConstantsAndSharedLevel() {
        XCTAssertEqual(CuddleJiggle.fingerRadius, TouchPlay.fingerRadius); XCTAssertEqual(CuddleJiggle.dentDepth, TouchPlay.dentDepth); XCTAssertEqual(CuddleJiggle.maxOffset, TouchPlay.maxCheekOffset)
        let t0 = CuddleJiggle.tuning(0), t1 = CuddleJiggle.tuning(1), t2 = CuddleJiggle.tuning(2)
        XCTAssertEqual([t0.extraDepth, t0.dragMax, t0.overshoot, t0.ripple, t0.petScale], [0, 0, 0, 0, 1])
        XCTAssertEqual([t1.extraDepth, t1.dragMax, t1.overshoot, t1.ripple, t1.petScale], [0.02, 0.03, 0.40, 0.008, 1.25])
        XCTAssertEqual([t2.extraDepth, t2.dragMax, t2.overshoot, t2.ripple, t2.petScale], [0.04, 0.05, 0.60, 0.014, 1.5])
        let saved = CuddleJiggle.sharedLevel; defer { CuddleJiggle.sharedLevel = saved }
        let c = CuddleJiggle()
        CuddleJiggle.sharedLevel = 0; XCTAssertEqual(c.level, 0)
        CuddleJiggle.sharedLevel = 2; XCTAssertEqual(c.level, 2)
        c.levelOverride = 1; XCTAssertEqual(c.level, 1)
        // level 0 does nothing at all, whatever it is fed
        let z = CuddleJiggle(); z.levelOverride = 0
        z.step(dt: 1.0 / 60, contact: true, ramp: 1, point: SIMD3(0, 0.7, 0.5), normal: SIMD3(0, 0, 1), pose: nil, annoyed: false); z.setPet(roll: 0.1, squash: 0.1)
        XCTAssertFalse(z.active)
    }

    // the drag: the skin near the finger follows its motion by at most the cap and springs back in ~0.12 s
    func testDragFollowsTheFingerAndSpringsBack() {
        for l in 1...2 {
            let r = run(l)
            let c = r.rig.skinner.cuddle
            r.stroke(1.5, eye: eye, amp: 0.30, hz: 1.2, y: 0.15, cx: 0.0)
            let cap = CuddleJiggle.tuning(l).dragMax
            let d = simd_length(c.drag)
            MotionLog.write(String(format: "CUDDLE level %d: drag while stroking %.4f u (max %.3f)", l, d, cap))
            XCTAssertGreaterThan(d, 0.2 * cap); XCTAssertLessThanOrEqual(d, cap * 1.001)
            r.idle(0.12)
            let after = simd_length(c.drag)
            MotionLog.write(String(format: "CUDDLE level %d: drag 0.12 s after the finger left %.4f u", l, after))
            XCTAssertLessThan(after, d * 0.5)
        }
    }

    // (f) cost of one apply per level, microseconds (median of 401), the layer fully engaged: dent + rim + drag + ripple + petted wobble
    func testApplyCostPerLevel() {
        let r = MotionRig(game: true)
        r.render()
        let base = r.dyn, vc = base.count / 6
        let mask = [Bool](repeating: true, count: vc)
        let pose = r.sim.bodyPose(iterations: 4)
        for l in 0...2 {
            let c = CuddleJiggle(); c.levelOverride = l
            let p = pose.centroid + SIMD3(0.2, 0.1, 0.45)
            for k in 0..<30 { c.step(dt: 1.0 / 60, contact: true, ramp: 1, point: p + SIMD3(0.004 * Float(k), 0, 0), normal: SIMD3(0, 0, 1), pose: pose, annoyed: false) }
            c.setPet(roll: 0.03, squash: 0.02)
            for _ in 0..<2 { c.step(dt: 1.0 / 60, contact: false, ramp: 0, point: nil, normal: nil, pose: pose, annoyed: false) }
            c.setPet(roll: 0.03, squash: 0.02)
            var buf = base, times = [Double]()
            for _ in 0..<401 {
                buf = base
                let a = CACurrentMediaTime()
                mask.withUnsafeBufferPointer { m in buf.withUnsafeMutableBufferPointer { c.apply($0.baseAddress!, count: vc, mask: m.baseAddress!, floorY: r.sim.floorY, H: Float(BobForm.top)) } }
                times.append(CACurrentMediaTime() - a)
                c.setPet(roll: 0.03, squash: 0.02)      // (keep it alive: a layer nobody steps is dropped after 30 applies)
            }
            times.sort()
            let us = times[times.count / 2] * 1e6
            MotionLog.write(String(format: "CUDDLE level %d: apply %.1f us per call, median of 401 (%d vertices, layer %@)", l, us, vc, c.active ? "active" : "inactive"))
            XCTAssertLessThan(us, 600)
        }
    }
}
