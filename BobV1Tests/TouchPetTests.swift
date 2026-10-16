//
//  TouchPetTests.swift
//  PET (focus mode): the sliding dent, his reactions and the pet haptics, run headless on the shared motion rig.
//  The rest gate: after 2 s hands-off the centroid is within 0.02 H of where it was and its speed is < 0.05 u/s.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TouchPetTests: XCTestCase {
    static let H = Float(BobForm.top)
    let eye = SIMD3<Float>(0, 0.9, 6)

    @MainActor final class Run {
        let rig: MotionRig
        let rec = RecordingHapticSink()
        let play: TouchPlay
        var clock = 100.0
        var maxDepth: Float = 0
        var maxDrift: Float = 0
        var maxDriftXZ: Float = 0
        var depths: [Float] = []
        var drifts: [SIMD3<Float>] = []
        var fingerX: [Float] = []
        let surface = RestSurface(mesh: MotionRig.renderMesh)
        var c0 = SIMD3<Float>(0, 0, 0)
        init() {
            rig = MotionRig(game: true, settle: 2)
            let d = HapticDriver(sinks: [rec])
            rec.clock = { 0 }
            play = TouchPlay(haptics: d)
            d.enabled = true
            d.setWarm(true)
            c0 = rig.sim.centroid()
            rec.clock = { [unowned self] in self.clock }
            rec.clear()
            d.setWarm(false); d.setWarm(true)
        }
        /// Local point (body frame, on the ellipsoid's middle plane) -> a ray from the camera through it.
        func ray(localX: Float, localY: Float, eye: SIMD3<Float>) -> (o: SIMD3<Float>, d: SIMD3<Float>) {
            let e = BodyEllipsoid(sim: rig.sim)
            let p = e.center + e.rot.act(SIMD3(localX, localY, 0))
            return (eye, simd_normalize(p - eye))
        }
        /// One frame: finger (or nil), play, sim tick.
        func frame(_ r: (o: SIMD3<Float>, d: SIMD3<Float>)?) {
            play.petFrame(dt: 1.0 / 60, now: clock, ray: r, screen: r == nil ? nil : SIMD2(0.5, 0.5),
                          sim: rig.sim, brain: rig.brain, skinner: rig.skinner, surface: surface)
            rig.tick()
            clock += 1.0 / 60
            maxDepth = max(maxDepth, rig.sim.pressDepth)
            depths.append(rig.sim.pressDepth)
            drifts.append(rig.sim.centroid() - c0)
            fingerX.append(play.hitLocal.map { $0.x - 0.38 } ?? 0)
            maxDrift = max(maxDrift, simd_length(rig.sim.centroid() - c0))
            let dd = rig.sim.centroid() - c0; maxDriftXZ = max(maxDriftXZ, simd_length(SIMD2(dd.x, dd.z)))
        }
        func stroke(_ seconds: Float, eye: SIMD3<Float>, amp: Float = 0.35, hz: Float = 1.2, y: Float = 0, cx: Float = 0) {
            var t: Float = 0
            while t < seconds { frame(ray(localX: cx + amp * sinf(2 * .pi * hz * t), localY: y, eye: eye)); t += 1.0 / 60 }
        }
        func idle(_ seconds: Float) { for _ in 0..<Int(seconds * 60) { frame(nil) } }
    }

    func testEllipsoidFitsTheBody() {
        let r = Run()
        let e = BodyEllipsoid(sim: r.rig.sim)
        // surface particles of the rest body sit near the ellipsoid: report the spread of the quadratic form
        var lo: Float = 9, hi: Float = 0
        var qs: [Float] = []
        let inv = e.rot.inverse
        for i in 0..<r.rig.sim.n {
            let p = SIMD3(r.rig.sim.x[3 * i], r.rig.sim.x[3 * i + 1], r.rig.sim.x[3 * i + 2])
            let l = inv.act(p - e.center) / e.radii
            let q = simd_length(l)
            lo = min(lo, q); hi = max(hi, q); qs.append(q)
        }
        qs.sort()
        print("ELLIPSOID q range \(lo) ... \(hi), p50 \(qs[qs.count / 2]) p90 \(qs[qs.count * 9 / 10]) p95 \(qs[qs.count * 95 / 100]) p99 \(qs[qs.count * 99 / 100])")
        XCTAssertLessThan(qs[qs.count * 9 / 10], 1.15)   // the egg fits the body (arms and feet are the few outliers)
        let h = e.hit(origin: eye, dir: simd_normalize(e.center - eye))
        XCTAssertNotNil(h)
    }

    func testIdleBaselineDrift() {
        let r = Run()
        r.idle(3)
        print("PET idle baseline drift \(r.maxDrift / Self.H) H xz \(r.maxDriftXZ / Self.H) H")
    }

    func testPetDentFollowsFingerAndDoesNotDrag() {
        let r = Run()
        r.stroke(3, eye: eye, amp: 0.12, hz: 1.2, y: 0.15, cx: 0.38)      // the plain-stroke area: the contact itself must not move the body
        print("PET drift timeline " + stride(from: 0, to: r.drifts.count, by: 15).map { String(format: "(%.3f,%.3f,%.3f)", r.drifts[$0].x, r.drifts[$0].y, r.drifts[$0].z) }.joined(separator: " "))
        print("PET tris \(r.surface.triangleCount)")
        print("PET depth timeline " + stride(from: 0, to: r.depths.count, by: 6).map { String(format: "%.2f", r.depths[$0]) }.joined(separator: " "))
        print("PET stroke: max dent depth \(r.maxDepth), max centroid drift \(r.maxDrift / Self.H) H, xz \(r.maxDriftXZ / Self.H) H")
        XCTAssertGreaterThan(r.maxDepth, 0.03, "the fingertip dents him")
        XCTAssertLessThan(r.maxDepth, 0.10, "a soft dimple, not a crater")  // proxy: deepest per-substep push
        XCTAssertLessThan(r.maxDrift, 0.09 * Self.H, "a stroke only sways him a little (and away from the finger, never after it)")
        XCTAssertTrue(r.rig.sim.pressing)
        // never pulled after the finger: while the finger is on the +x half of its sweep the body is not displaced toward it more than away
        let toward = zip(r.drifts, r.fingerX).filter { $0.1 != 0 }.map { $0.0.x * $0.1 }
        XCTAssertLessThan(toward.reduce(0, +) / Float(max(toward.count, 1)), 0.01, "no net pull toward the finger")
    }

    func testPetReturnsToRest() {
        let r = Run()
        r.idle(1)
        let c0 = r.rig.sim.centroid()
        r.c0 = c0
        r.stroke(3, eye: eye)
        r.idle(2)
        let drift = simd_length(r.rig.sim.centroid() - c0) / Self.H
        let speed = simd_length(r.rig.sim.meanVelocity())
        print("PET rest gate: drift \(drift) H, speed \(speed) u/s, love \(r.play.love)")
        XCTAssertLessThan(drift, 0.02)
        XCTAssertLessThan(speed, 0.05)
        XCTAssertFalse(r.rig.sim.pressing)
        XCTAssertEqual(r.rig.brain.touchSquash, 1)
        XCTAssertEqual(r.rig.brain.touchRoll, 0)
        XCTAssertEqual(r.rig.brain.touchPitch, 0)
    }

    func testHappyEyesAfterStrokingAndOpenAfterABeat() {
        let r = Run()
        XCTAssertGreaterThan(r.rig.skinner.eyeHeight.left, 0.9)
        r.stroke(0.25, eye: eye, amp: 0.1, y: 0.15, cx: 0.38)           // the plain-stroke area (the belly and tickle zones react sooner)
        XCTAssertGreaterThan(r.rig.skinner.eyeHeight.left, 0.9, "not before ~0.4 s of stroking")
        r.stroke(0.9, eye: eye, amp: 0.1, y: 0.15, cx: 0.38)
        XCTAssertLessThan(r.rig.skinner.eyeHeight.left, 0.3, "closed happy eyes while stroking")
        XCTAssertLessThan(r.rig.skinner.eyeHeight.right, 0.3)
        r.idle(0.3)
        XCTAssertLessThan(r.rig.skinner.eyeHeight.left, 0.5, "a beat before they open")
        r.idle(1.5)
        XCTAssertGreaterThan(r.rig.skinner.eyeHeight.left, 0.9)
        XCTAssertTrue(r.rig.skinner.autoBlink, "automatic blinking is back")
    }

    func testLeanIntoTheFinger() {
        for side: Float in [-1, 1] {
            let r = Run()
            r.idle(0.5)
            r.stroke(2.0, eye: eye, amp: 0.15, hz: 0.7, cx: side * 0.30)
            // upper body (above the middle) shifts toward the finger side in the body frame, relative to the lower body
            let rot = simd_quatf(angle: -r.rig.sim.bodyPose(iterations: 6).yaw, axis: SIMD3(0, 1, 0))   // yaw only: the lean itself must show
            let c = r.rig.sim.centroid()
            var up: Float = 0, upN: Float = 0
            for i in 0..<r.rig.sim.n {
                let l = rot.act(SIMD3(r.rig.sim.x[3 * i], r.rig.sim.x[3 * i + 1], r.rig.sim.x[3 * i + 2]) - c)
                if l.y > 0.3 { up += l.x; upN += 1 }
            }
            let shift = up / max(upN, 1)
            print("LEAN side \(side): upper body x offset \(shift), touchRoll \(r.rig.brain.touchRoll)")
            XCTAssertGreaterThan(shift * side, 0.01, "he leans toward the finger side")
        }
    }

    func testPetHapticsDeadZoneAndRate() {
        let r = Run()
        r.stroke(2, eye: eye)
        r.idle(0.4)
        let pet = r.rec.events(.continuous, channel: "pet")
        XCTAssertFalse(pet.isEmpty)
        XCTAssertGreaterThan(pet.map { $0.intensity }.max() ?? 0, 0.3)
        XCTAssertLessThanOrEqual(pet.map { $0.sharpness }.max() ?? 1, 0.31, "low sharpness")
        XCTAssertEqual(pet.last?.intensity, 0, "silent once the finger stops")
        // at most 60 Hz
        for k in 1..<pet.count { XCTAssertGreaterThanOrEqual(pet[k].t - pet[k - 1].t, 1.0 / 60 - 0.001) }
        // only on change
        for k in 1..<pet.count { XCTAssertNotEqual(pet[k].intensity, pet[k - 1].intensity) }
        // a held finger (no motion) makes no pet vibration
        let r2 = Run()
        r2.stroke(0.6, eye: eye)
        r2.rec.clear()
        for _ in 0..<120 { r2.frame(r2.ray(localX: 0.1, localY: 0, eye: eye)) }
        let held = r2.rec.events(.continuous, channel: "pet").filter { $0.t > 0.4 }
        XCTAssertTrue(held.allSatisfy { $0.intensity == 0 }, "dead zone: a still finger is silent")
    }

    func testHapticMappingIsMonotonicWithDeadZone() {
        XCTAssertEqual(HapticMap.petIntensity(speed: 0), 0)
        XCTAssertEqual(HapticMap.petIntensity(speed: HapticMap.petDeadZone * 0.9), 0)
        var prev: Float = 0
        for v in stride(from: HapticMap.petDeadZone + 0.01, through: 8, by: 0.1) {
            let i = HapticMap.petIntensity(speed: Float(v)); XCTAssertGreaterThanOrEqual(i, prev); prev = i
            XCTAssertLessThanOrEqual(i, 1)
            XCTAssertTrue((0.1...0.3).contains(HapticMap.petSharpness(speed: Float(v))))
        }
        prev = 0; var ps: Float = 1
        for d in stride(from: Float(0.01), through: 0.6, by: 0.01) {
            let i = HapticMap.squishIntensity(depth: d), s = HapticMap.squishSharpness(depth: d)
            XCTAssertGreaterThanOrEqual(i, prev, "deeper squish -> higher intensity"); prev = i
            XCTAssertLessThanOrEqual(s, ps, "sharpness falls as it deepens"); ps = s
        }
        var pi: Float = 0
        for v in stride(from: Float(0), through: 10, by: 0.5) { let i = HapticMap.impactIntensity(speed: v); XCTAssertGreaterThanOrEqual(i, pi); pi = i }
        let c = HapticMap.wobbleCurve(tau: HapticMap.wobbleTau, duration: HapticMap.wobbleDuration)
        XCTAssertLessThanOrEqual(c.count, 16)
        for k in 1..<c.count { XCTAssertLessThan(c[k].v, c[k - 1].v) }
    }

    func testHapticsStartAndStopWithFocusAndToggle() {
        let rec = RecordingHapticSink()
        let d = HapticDriver(sinks: [rec])
        d.enabled = true
        d.setWarm(true); XCTAssertTrue(rec.running); XCTAssertEqual(rec.startCount, 1)
        d.setWarm(true); XCTAssertEqual(rec.startCount, 1)
        d.setWarm(false); XCTAssertFalse(rec.running); XCTAssertEqual(rec.stopCount, 1)
        d.update(now: 1, petIntensity: 0.5, petSharpness: 0.2, squishIntensity: 0, squishSharpness: 0.5)
        XCTAssertTrue(rec.events(.continuous).isEmpty, "nothing plays outside focus")
        // the Settings toggle
        let saved = UserDefaults.standard.object(forKey: HapticSettings.key)
        defer { if let s = saved { UserDefaults.standard.set(s, forKey: HapticSettings.key) } else { UserDefaults.standard.removeObject(forKey: HapticSettings.key) } }
        UserDefaults.standard.removeObject(forKey: HapticSettings.key)
        XCTAssertTrue(HapticSettings.enabled, "on by default")
        HapticSettings.enabled = false
        let d2 = HapticDriver(sinks: [rec]); rec.clear()
        d2.setWarm(true)
        d2.update(now: 1, petIntensity: 0.5, petSharpness: 0.2, squishIntensity: 0, squishSharpness: 0.5)
        XCTAssertTrue(rec.events(.continuous).isEmpty, "toggle off: silent")
        d2.setWarm(false)
    }

    func testRippleWhenAWaveCrossesTheFinger() {
        let r = Run()
        r.stroke(0.6, eye: eye)
        for _ in 0..<90 { r.frame(r.ray(localX: 0.1, localY: 0, eye: eye)) }      // a still finger on a still body
        let calm = r.play.ripples
        for i in 0..<r.rig.sim.n where r.rig.sim.x[3 * i + 2] > 0.2 { r.rig.sim.v[3 * i + 2] += 1.5 }   // a slap on the front: a wave runs through the surface
        var peak: Float = 0
        for _ in 0..<60 { r.frame(r.ray(localX: 0.1, localY: 0, eye: eye)); peak = max(peak, abs(r.play.rippleV)) }
        print("RIPPLE peak \(peak) calm \(calm) after nudge \(r.play.ripples)")
        XCTAssertGreaterThan(r.play.ripples, calm, "a wobble wave under the finger gives ripple ticks")
        XCTAssertFalse(r.rec.events(.transient).isEmpty)
    }

    /// Writes the pet parameter stream (CSV) when TEST_RUNNER_TOUCH_CSV names a file: speed, dent depth and every haptic call of a petting session.
    func testWritePetHapticCSV() throws {
        guard let path = ProcessInfo.processInfo.environment["TOUCH_CSV"] else { throw XCTSkip("TOUCH_CSV not set") }
        let r = Run()
        var rows = "t,speed,depth,love,pet_intensity_sent\n"
        var t: Float = 0
        func f(_ ray: (o: SIMD3<Float>, d: SIMD3<Float>)?) {
            r.frame(ray); t += 1.0 / 60
            rows += String(format: "%.3f,%.3f,%.3f,%.3f\n", t, r.play.speed, r.rig.sim.pressDepth, r.play.love)
        }
        for _ in 0..<60 { f(nil) }
        var tt: Float = 0
        while tt < 4 { f(r.ray(localX: 0.4 * sinf(2 * .pi * 0.9 * tt), localY: 0.05 * sinf(2 * .pi * 0.45 * tt), eye: eye)); tt += 1.0 / 60 }
        for _ in 0..<90 { f(r.ray(localX: 0.1, localY: 0, eye: eye)) }
        for _ in 0..<120 { f(nil) }
        try rows.write(toFile: path + ".sim.csv", atomically: true, encoding: .utf8)
        try r.rec.csv.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
