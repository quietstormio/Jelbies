//
//  TouchPlayTests.swift
//  PICK UP, BOUNCE and CHEEKS of focus mode, run headless on the shared motion rig. Every interaction must return to rest:
//  after settling, the centroid is within 0.02 H of where it was, its speed is < 0.05 u/s and no particle is further than
//  0.02 H from its pre-touch settled position (the rest shape itself is never edited: the base-body lock tests cover that).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TouchPlayTests: XCTestCase {
    static let H = Float(BobForm.top)

    @MainActor final class Rig {
        let rig: MotionRig
        let rec = RecordingHapticSink()
        let play: TouchPlay
        let surface = RestSurface(mesh: MotionRig.renderMesh)
        var clock = 100.0
        var base: [Float] = []
        var c0 = SIMD3<Float>.zero
        var p0: BodyPose
        init() {
            rig = MotionRig(game: true, settle: 2)
            p0 = rig.sim.bodyPose(iterations: 10)
            let d = HapticDriver(sinks: [rec])
            rec.clock = { 0 }
            play = TouchPlay(haptics: d)
            d.enabled = true
            d.setWarm(true)
            rec.clear()
            rec.clock = { [unowned self] in self.clock }
            rig.run(1)
            base = rig.sim.x
            p0 = rig.sim.bodyPose(iterations: 10)
            c0 = rig.sim.centroid()
        }
        func ray(_ x: Float, _ y: Float) -> (o: SIMD3<Float>, d: SIMD3<Float>) {
            let e = BodyEllipsoid(sim: rig.sim)
            let p = e.center + e.rot.act(SIMD3(x, y, 0))
            let eye = SIMD3<Float>(0, 0.9, 6)
            return (eye, simd_normalize(p - eye))
        }
        func step(touched: Bool, _ extra: (() -> Void)? = nil) {
            extra?()
            play.trackImpacts(now: clock, sim: rig.sim)
            rig.tick(touched: touched)
            clock += 1.0 / 60
        }
        var deviation: Float {
            var m: Float = 0
            for i in 0..<rig.sim.n {
                let d = SIMD3(rig.sim.x[3 * i] - base[3 * i], rig.sim.x[3 * i + 1] - base[3 * i + 1], rig.sim.x[3 * i + 2] - base[3 * i + 2])
                m = max(m, simd_length(d))
            }
            return m
        }
        /// Shape deviation after aligning the current rigid fit with the pre-touch one (he may be set down a little elsewhere).
        var shapeDeviation: Float {
            let sim = rig.sim
            let p1 = sim.bodyPose(iterations: 10)
            var m: Float = 0
            for i in 0..<sim.n {
                let w = p1.rotation.inverse.act(SIMD3(sim.x[3 * i], sim.x[3 * i + 1], sim.x[3 * i + 2]) - p1.centroid)
                let r = p0.rotation.inverse.act(SIMD3(base[3 * i], base[3 * i + 1], base[3 * i + 2]) - p0.centroid)
                m = max(m, simd_length(w - r))
            }
            return m
        }
        func assertShapeRest(_ msg: String, moveLimit: Float, file: StaticString = #filePath, line: UInt = #line) {
            let move = simd_length(rig.sim.centroid() - c0) / TouchPlayTests.H
            let speed = simd_length(rig.sim.meanVelocity())
            let dev = shapeDeviation / TouchPlayTests.H
            print("REST \(msg): moved \(move) H, speed \(speed), shape deviation \(dev) H, tilt \(rig.sim.bodyPose(iterations: 8).tilt)")
            XCTAssertLessThan(speed, 0.05, msg, file: file, line: line)
            XCTAssertLessThan(dev, 0.02, msg + " (his shape is back to rest)", file: file, line: line)
            XCTAssertLessThan(move, moveLimit, msg + " (set down near his spot)", file: file, line: line)
            XCTAssertLessThan(abs(rig.sim.bodyPose(iterations: 8).tilt - p0.tilt), 0.1, msg + " (same stance as before)", file: file, line: line)
        }
        func assertRest(_ msg: String, file: StaticString = #filePath, line: UInt = #line) {
            let drift = simd_length(rig.sim.centroid() - c0) / TouchPlayTests.H
            let speed = simd_length(rig.sim.meanVelocity())
            print("REST \(msg): centroid drift \(drift) H, speed \(speed), max particle deviation \(deviation / TouchPlayTests.H) H")
            XCTAssertLessThan(drift, 0.02, msg, file: file, line: line)
            XCTAssertLessThan(speed, 0.05, msg, file: file, line: line)
            XCTAssertLessThan(deviation, 0.02 * TouchPlayTests.H, msg + " (every particle back at rest)", file: file, line: line)
        }
    }

    func testCheeksPinchSqueezeAndPopBack() {
        let r = Rig()
        var maxDepth: Float = 0
        func frame(_ rays: [(o: SIMD3<Float>, d: SIMD3<Float>)]?, gap: Float) {
            r.play.cheeksFrame(dt: 1.0 / 60, now: r.clock, rays: rays, gap: gap, sim: r.rig.sim, brain: r.rig.brain, skinner: r.rig.skinner, surface: r.surface)
            r.rig.tick(); r.clock += 1.0 / 60
            maxDepth = max(maxDepth, r.rig.sim.pressDepth)
        }
        for k in 0..<60 { let g = 0.5 - 0.3 * Float(k) / 60; frame([r.ray(-g, 0.25), r.ray(g, 0.25)], gap: g * 400) }
        for _ in 0..<60 { frame([r.ray(-0.2, 0.25), r.ray(0.2, 0.25)], gap: 80) }
        XCTAssertGreaterThan(r.play.pinch, 0.5, "the pinch deepens as the fingers come together")
        XCTAssertFalse(r.rig.skinner.extraVertices.isEmpty, "the squeeze is a smooth skin offset")
        XCTAssertGreaterThan(r.play.visPinch, 0.5)
        XCTAssertLessThan(r.rig.skinner.eyeHeight.left, 0.8, "he squints a little")
        let press = r.rec.events(.continuous, channel: "squish")
        XCTAssertGreaterThan(press.map { $0.intensity }.max() ?? 0, 0.5, "a firm press")
        var last: Float = 0
        for e in press.prefix(while: { $0.intensity > 0 }).prefix(20) { XCTAssertGreaterThanOrEqual(e.intensity, last - 0.001); last = e.intensity }   // grows with the pinch
        for _ in 0..<2 { frame(nil, gap: 0) }
        XCTAssertEqual(r.play.cheekReleases, 1)
        XCTAssertFalse(r.rec.events(.transient).isEmpty, "a bloop on release")
        for _ in 0..<(60 * 3) { frame(nil, gap: 0) }
        XCTAssertEqual(r.rig.skinner.eyeHeight.left, 1, accuracy: 0.05)
        XCTAssertTrue(r.rig.skinner.extraVertices.isEmpty, "exactly 0 at rest")
        r.assertRest("cheeks")
    }

    func testPickUpDangleDropAndSettle() {
        let r = Rig()
        let sim = r.rig.sim
        r.step(touched: true)
        // grab the crown
        var apex = 0, top: Float = -1
        for i in 0..<sim.n where sim.x[3 * i + 1] > top { top = sim.x[3 * i + 1]; apex = i }
        let hit = SIMD3(sim.x[3 * apex], sim.x[3 * apex + 1], sim.x[3 * apex + 2])
        sim.beginGrab(hit: hit, radius: 0.4)
        var feetUp: Float = 0
        var strains: [Float] = []
        for k in 0..<90 {
            let lift = 0.9 * Float(k) / 90
            r.step(touched: true) { sim.moveGrab(target: hit + SIMD3(0, lift, 0), rot: nil) }
            if k % 10 == 9 { strains.append(sim.deformation()) }
            feetUp = max(feetUp, sim.minY())
        }
        for _ in 0..<60 { r.step(touched: true) { sim.moveGrab(target: hit + SIMD3(0, 0.9, 0), rot: nil) } }
        print("PICKUP hang: lowest particle \(sim.minY()) u above the floor, strains \(strains)")
        XCTAssertGreaterThan(sim.minY(), 0.1, "his feet are off the floor while he dangles")
        XCTAssertGreaterThan(strains.last ?? 0, strains.first ?? 0, "the stretch deepens as he is lifted")
        let hang = HapticMap.squishIntensity(depth: min(0.5, sim.deformation() * TouchPlay.liftDepthGain))
        XCTAssertGreaterThan(hang, 0.12, "the stretch is felt")
        sim.endGrab()
        for _ in 0..<(60 * 8) { r.step(touched: false) }
        XCTAssertGreaterThanOrEqual(r.play.impacts, 1, "the drop lands with a thump")
        print("PICKUP drop: impacts \(r.play.impacts) speed \(r.play.lastImpactSpeed)")
        // he may be set down a little off his spot: judge the shape, not the position
        r.assertShapeRest("pick up", moveLimit: 0.4)
    }

    // MARK: excitement while held

    /// Superseded spec: "shake his arms and legs like he's excited" (3.2 Hz flapping, out-of-phase leg kicks, 11 Hz haptic flutter) ->
    /// a happy held Bob: closed happy eyes, a slow ~1 Hz sway, feet dangling together and swinging softly, a small arm lift, and a slow warm
    /// haptic swell. Still starts ~0.2 s after the lift and still stops when he lands.
    func testHeldBobIsHappyNotFreakingOutAndStopsWhenHeLands() {
        let r = Rig()
        let sim = r.rig.sim, brain = r.rig.brain, sk = r.rig.skinner
        r.step(touched: true)
        var apex = 0, top: Float = -1
        for i in 0..<sim.n where sim.x[3 * i + 1] > top { top = sim.x[3 * i + 1]; apex = i }
        let hit = SIMD3(sim.x[3 * apex], sim.x[3 * apex + 1], sim.x[3 * apex + 2])
        sim.beginGrab(hit: hit, radius: 0.4)
        var firstExcited: Float?
        var legs: [Float] = [], armLo: Float = 9, armHi: Float = -9, sways: [Float] = [], gaps: [Float] = []
        for k in 0..<240 {
            let lift = min(0.4, 0.4 * Float(k) / 60)
            r.step(touched: true) {
                sim.moveGrab(target: hit + SIMD3(0, lift, 0), rot: nil)
                r.play.petFrameIdle(dt: 1.0 / 60, now: r.clock)          // the stage's order while he is held: the haptic levels, then the held reactions
                r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: true, liftHeight: lift, sim: sim, brain: brain, skinner: sk)
            }
            if firstExcited == nil, r.play.excitement > 0.01 { firstExcited = Float(k) / 60 }
            if r.play.excitement > 0.95 {
                sways.append(r.play.heldSway)
                if sk.beanPos[0].count > 0 {
                    let y0 = sk.beanPos[0].map { $0.y }.reduce(0, +) / Float(sk.beanPos[0].count), y1 = sk.beanPos[1].map { $0.y }.reduce(0, +) / Float(sk.beanPos[1].count)
                    legs.append(y0 - y1)
                    let z0 = sk.beanPos[0].map { $0.z }.reduce(0, +) / Float(sk.beanPos[0].count), z1 = sk.beanPos[1].map { $0.z }.reduce(0, +) / Float(sk.beanPos[1].count)
                    gaps.append(abs(z0 - z1))
                }
                if let i = sk.overrideDelta.indices.max(by: { simd_length(sk.overrideDelta[$0]) < simd_length(sk.overrideDelta[$1]) }) { let a = simd_length(sk.overrideDelta[i]); armLo = min(armLo, a); armHi = max(armHi, a) }
            }
        }
        XCTAssertLessThan(sim.bodyPose(iterations: 8).tilt, 0.6, "he hangs upright-ish, he does not flip over")
        XCTAssertEqual(firstExcited ?? 9, 0.1 + 0.2, accuracy: 0.08, "it starts about 0.2 s after the lift (the lift passes 0.04 u at 0.1 s)")
        XCTAssertGreaterThan(r.play.excitement, 0.95)
        XCTAssertTrue(brain.excitedOn)
        // feet dangle TOGETHER: the two feet never differ in height by more than a hair (the old out-of-phase kick was +-0.13 u), and swing softly
        XCTAssertLessThan(legs.map { abs($0) }.max() ?? 1, 0.03, "no leg kicks: the feet hang level")
        XCTAssertLessThan(gaps.max() ?? 1, 0.05, "the feet swing together, not against each other")
        // the sway is ~1 Hz and small
        var cross = 0; for i in 1..<max(sways.count, 1) where sways[i] * sways[i - 1] < 0 { cross += 1 }
        let secs = Float(sways.count) / 60
        XCTAssertEqual(Float(cross) / 2 / secs, 1.0, accuracy: 0.3, "about one sway a second")
        XCTAssertLessThanOrEqual(sways.map { abs($0) }.max() ?? 1, 0.08, "a few degrees only")
        XCTAssertLessThan(armHi - armLo, 0.12, "a small happy arm lift that barely moves, no flapping (the old flap swung it by ~0.3 u)")
        XCTAssertFalse(sk.overrideVertices.isEmpty, "a small arm lift through the skin override")
        // haptics: no flutter (no transients while held), a soft slow swell on the pet channel
        XCTAssertTrue(r.rec.events(.transient).filter { $0.sharpness > 0.55 && $0.sharpness < 0.65 }.isEmpty, "no 11 Hz flutter")
        let pulse = r.rec.events(.continuous, channel: "pet").map { $0.intensity }
        XCTAssertGreaterThan(pulse.max() ?? 0, 0.15, "a warm swell is felt")
        XCTAssertLessThan(pulse.max() ?? 0, 0.4, "soft")
        XCTAssertLessThan(sk.eyeHeight.left, 0.15, "closed happy eyes")
        XCTAssertGreaterThan(sim.minY(), 0.05, "still lifted")
        // let go: it lasts until he lands, then everything goes back
        sim.endGrab()
        var landedAt: Int?
        for k in 0..<(60 * 4) {
            r.step(touched: true) { r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: false, liftHeight: 0.4, sim: sim, brain: brain, skinner: sk) }
            if landedAt == nil, r.play.impacts > 0 { landedAt = k }
        }
        XCTAssertNotNil(landedAt, "he lands")
        XCTAssertEqual(r.play.excitement, 0, "it stops when he lands")
        XCTAssertFalse(brain.excitedOn)
        XCTAssertTrue(sk.overrideVertices.isEmpty, "arms back to the rest skin")
        XCTAssertEqual(r.rec.events(.continuous, channel: "pet").last?.intensity ?? 0, 0, "the held swell is switched off")
    }

    // MARK: getting back up

    /// Superseded spec: "after 2 s untouched he gets up" -> a ~0.35 s calm window after the last bounce, righting in <= 0.8 s, then a run
    /// back (the idle run blend); release -> back in place <= 3 s for a typical throw, <= 4.5 s for a far one.
    /// The close-up's visible frame at his depth (what MelonStage derives from the camera), for the headless throws.
    static func frame(_ spot: SIMD2<Float>) -> TouchPlay.FrameLimits {
        TouchPlay.FrameLimits(xMin: spot.x - 0.9, xMax: spot.x + 0.9, zMin: spot.y - 1.2, zMax: spot.y + 0.3, yMax: 2.3)
    }

    func testThrownBobBouncesThenRunsBackToTheFocusSpot() {
        let spot = GameCamera.callSpot
        // (name, velocity, spin, limit s). The stage caps a throw at 0.9 u/s sideways and 2.5...4.2 u/s up.
        for (name, v, spin, limit) in [("typical", SIMD3<Float>(0.6, 2.8, 0.2), SIMD3<Float>(0, 0, -2.5), Float(3.0)),
                                       ("typical back", SIMD3<Float>(0.2, 3.0, -0.6), SIMD3<Float>(2.5, 0, 0), Float(3.0)),
                                       ("far side", SIMD3<Float>(0.9, 4.2, 0.3), SIMD3<Float>(0, 0, -2.5), Float(4.5)),
                                       ("far", SIMD3<Float>(-0.9, 4.2, 0.6), SIMD3<Float>(0, 0, 2.5), Float(4.5))] {
            let r = Rig()
            r.rig.brain.request(.come(to: spot))
            r.rig.run(12) { r.rig.brain.activity == .idle && simd_length(r.rig.brain.position - spot) < 0.1 }
            r.rig.run(1.5)
            let base = r.rig.sim.bodyPose(iterations: 10)
            r.step(touched: true); r.step(touched: true)             // the brain is already hands-off when a held Bob is let go
            r.rig.sim.launch(velocity: v, spin: spin)
            r.play.thrown = true
            var tRight: Float?, tUp: Float?, tBack: Float?, tNear: Float?, maxTilt: Float = 0, maxRun: Float = 0, maxOut: Float = -9
            var outWhere = "", outAt: Float = 0
            var t: Float = 0
            var landedFar = false
            let impacts0 = r.play.impacts
            for _ in 0..<(60 * 10) {
                let hold = r.play.getUpFrame(dt: 1.0 / 60, now: r.clock, held: false, focusSpot: spot, sim: r.rig.sim, brain: r.rig.brain)
                r.play.wallsFrame(now: r.clock, sim: r.rig.sim, limits: Self.frame(spot))             // the stage's soft walls at the close-up's edges
                r.step(touched: hold || t < 0.3)
                t += 1.0 / 60
                let bb = r.rig.sim.bounds()
                let fr = Self.frame(spot)
                let ox = max(bb.hi.x - fr.xMax, fr.xMin - bb.lo.x), oy = bb.hi.y - fr.yMax
                if max(ox, oy) > maxOut { maxOut = max(ox, oy); outWhere = ox > oy ? "x" : "y"; outAt = t }
                let pose = r.rig.sim.bodyPose(iterations: 6)
                maxTilt = max(maxTilt, pose.tilt)
                maxRun = max(maxRun, r.rig.brain.runW)
                if tRight == nil, r.play.getUpPhase == .righting { tRight = t; landedFar = simd_length(SIMD2(pose.centroid.x, pose.centroid.z) - spot) > 0.5 }
                if tRight != nil, tUp == nil, r.play.getUpPhase == .off { tUp = t }
                if tUp != nil, tNear == nil, simd_length(SIMD2(pose.centroid.x, pose.centroid.z) - spot) < 0.25 { tNear = t }
                if tUp != nil, tBack == nil, simd_length(r.rig.sim.meanVelocity()) < 0.25, abs(pose.tilt - base.tilt) < 0.3, simd_length(SIMD2(pose.centroid.x, pose.centroid.z) - spot) < 0.25,
                   abs(pose.yaw - base.yaw) < 0.35 { tBack = t }
            }
            print("THROW \(name): worst frame overshoot \(maxOut) on \(outWhere) at \(outAt) s; bounces \(r.play.bounces) (wall \(r.play.wallBounces); impacts \(r.play.impacts - impacts0)), max tilt \(maxTilt), righting starts \(tRight ?? -1) s, up at \(tUp ?? -1) s, within 0.25 u of the spot \(tNear ?? -1) s, back in place and still \(tBack ?? -1) s after release, run blend peak \(maxRun)")
            XCTAssertGreaterThanOrEqual(r.play.bounces, 2, name + ": he bounces two or three times (the walls count)")
            XCTAssertLessThanOrEqual(r.play.bounces, 8, name)
            XCTAssertLessThanOrEqual(maxOut, 0.06, name + ": he stays inside the frame (within one step of the wall)")
            XCTAssertGreaterThan(maxTilt, 0.45, name + ": he really did roll a bit")
            XCTAssertNotNil(tBack, name + ": he is up and back at the spot")
            XCTAssertLessThanOrEqual((tUp ?? 99) - (tRight ?? 0), 0.8, name + ": rights himself in at most 0.8 s")
            if landedFar { XCTAssertGreaterThan(maxRun, 0.9, name + ": he RUNS back (the idle run blend), not the plain walk") }
            XCTAssertLessThanOrEqual(tNear ?? 99, limit, name + ": release -> back at the spot (within 0.25 u)")
            XCTAssertLessThanOrEqual(tBack ?? 99, limit + 0.2 - (limit > 4 ? 0.2 : 0), name + ": ... and settled, facing the camera: <= 3.2 s typical, <= 4.5 s far")
            let pose = r.rig.sim.bodyPose(iterations: 10)
            XCTAssertLessThan(abs(pose.tilt - base.tilt), 0.3, name)
            XCTAssertLessThan(simd_length(SIMD2(r.rig.sim.centroid().x, r.rig.sim.centroid().z) - spot), 0.25, name)
            XCTAssertLessThan(abs(pose.yaw - base.yaw), 0.35, name + ": facing the camera again")
            r.rig.run(2)
            XCTAssertEqual(r.rig.brain.runW, 0, "the run blend ends on arrival")
            XCTAssertFalse(r.rig.brain.hurry, name)
        }
    }

    /// The bounce restitution is for a THROWN Bob only: a plain drop from a lift (and a hop) lands exactly as before.
    func testOnlyAThrownBobBounces() {
        let r = Rig()
        let sim = r.rig.sim
        r.step(touched: true)
        sim.launch(velocity: SIMD3(0, 3.5, 0), spin: .zero)                 // flung up but NOT marked as thrown
        for _ in 0..<(60 * 4) { r.step(touched: true) }
        XCTAssertEqual(r.play.bounces, 0, "no throw, no bounce")
        XCTAssertGreaterThanOrEqual(r.play.impacts, 1)
    }

    func testLeftLyingAnywhereHeGetsUpWhereHeIs() {
        let r = Rig()
        r.step(touched: true); r.step(touched: true)
        r.rig.sim.launch(velocity: SIMD3(0, 4, 0), spin: SIMD3(0, 0, 4))
        var done = false
        for _ in 0..<(60 * 10) {
            let hold = r.play.getUpFrame(dt: 1.0 / 60, now: r.clock, held: false, focusSpot: nil, sim: r.rig.sim, brain: r.rig.brain)
            r.step(touched: hold)
            if r.play.getUps > 0 && r.rig.sim.bodyPose(iterations: 6).tilt < 0.4 { done = true }
        }
        print("LYING tilt \(r.rig.sim.bodyPose(iterations: 6).tilt) getUps \(r.play.getUps)")
        XCTAssertTrue(done || r.rig.sim.bodyPose(iterations: 6).tilt < 0.4, "upright again")
    }
}
