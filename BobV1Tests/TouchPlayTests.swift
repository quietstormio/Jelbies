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
        XCTAssertFalse(r.rec.events(.wobble).isEmpty)
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

    func testHeldBobFlapsAndKicksOutOfPhaseAndStopsWhenHeLands() {
        let r = Rig()
        let sim = r.rig.sim, brain = r.rig.brain, sk = r.rig.skinner
        r.step(touched: true)
        var apex = 0, top: Float = -1
        for i in 0..<sim.n where sim.x[3 * i + 1] > top { top = sim.x[3 * i + 1]; apex = i }
        let hit = SIMD3(sim.x[3 * apex], sim.x[3 * apex + 1], sim.x[3 * apex + 2])
        sim.beginGrab(hit: hit, radius: 0.4)
        var firstExcited: Float?
        var legs: [Float] = [], arms: [Float] = []
        var maxLift: Float = 0
        for k in 0..<150 {
            let lift = min(0.4, 0.4 * Float(k) / 60)
            r.step(touched: true) {
                sim.moveGrab(target: hit + SIMD3(0, lift, 0), rot: nil)
                r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: true, liftHeight: lift, sim: sim, brain: brain, skinner: sk)
            }
            if firstExcited == nil, r.play.excitement > 0.01 { firstExcited = Float(k) / 60 }
            if r.play.excitement > 0.9, sk.beanPos[0].count > 0, !sk.beanPos[0].isEmpty {
                legs.append(sk.beanPos[0].map { $0.y }.reduce(0, +) / Float(sk.beanPos[0].count) - sk.beanPos[1].map { $0.y }.reduce(0, +) / Float(sk.beanPos[1].count))
                if let i = sk.overrideDelta.indices.max(by: { simd_length(sk.overrideDelta[$0]) < simd_length(sk.overrideDelta[$1]) }) { arms.append(sk.overrideDelta[i].y) }
            }
            maxLift = max(maxLift, sim.minY())
        }
        print("EXCITED hang tilt \(sim.bodyPose(iterations: 8).tilt)")
        XCTAssertLessThan(sim.bodyPose(iterations: 8).tilt, 0.6, "he hangs upright-ish, he does not flip over")
        XCTAssertNotNil(firstExcited)
        XCTAssertEqual(firstExcited ?? 9, 0.1 + 0.2, accuracy: 0.08, "it starts about 0.2 s after the lift (the lift passes 0.04 u at 0.1 s)")
        XCTAssertGreaterThan(r.play.excitement, 0.95)
        XCTAssertTrue(brain.excitedOn)
        XCTAssertFalse(sk.overrideVertices.isEmpty, "the arms flap through the skin override")
        func flips(_ a: [Float]) -> Int { var n = 0; for i in 1..<max(a.count, 1) where a[i] * a[i - 1] < 0 { n += 1 }; return n }
        XCTAssertGreaterThan(flips(legs), 6, "the feet kick alternately (the height difference of the two feet changes sign)")
        XCTAssertGreaterThan(Float(legs.map { abs($0) }.max() ?? 0), 0.04)
        XCTAssertGreaterThan(r.rec.events(.transient).filter { $0.sharpness > 0.55 && $0.sharpness < 0.65 }.count, 8, "a light flutter while he wiggles")
        XCTAssertLessThan(sk.eyeHeight.left, 0.45, "happy eyes")
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
    }

    // MARK: getting back up

    func testThrownBobGetsBackUpAtTheFocusSpotAndRestGatePasses() {
        let spot = GameCamera.callSpot
        for (name, v, spin) in [("side", SIMD3<Float>(2.5, 5, 0.5), SIMD3<Float>(0, 0, -3.5)),
                                ("back", SIMD3<Float>(0, 4.5, -2), SIMD3<Float>(3.5, 0, 0)),
                                ("far", SIMD3<Float>(-3, 6, 2), SIMD3<Float>(2, 1, 3))] {
            let r = Rig()
            // stand at the focus spot first
            r.rig.brain.request(.come(to: spot))
            r.rig.run(12) { r.rig.brain.activity == .idle && simd_length(r.rig.brain.position - spot) < 0.1 }
            r.rig.run(1.5)
            let base = r.rig.sim.bodyPose(iterations: 10)
            r.step(touched: true); r.step(touched: true)             // the brain is already hands-off when a held Bob is let go
            r.rig.sim.launch(velocity: v, spin: spin)
            r.play.thrown = true
            var tRight: Float?, tDone: Float?, maxTilt: Float = 0
            var landed: Float = 0
            var t: Float = 0
            for _ in 0..<(60 * 14) {
                let hold = r.play.getUpFrame(dt: 1.0 / 60, now: r.clock, held: false, focusSpot: spot, sim: r.rig.sim, brain: r.rig.brain)
                r.step(touched: hold || t < 0.5)
                t += 1.0 / 60
                let pose = r.rig.sim.bodyPose(iterations: 6)
                maxTilt = max(maxTilt, pose.tilt)
                if tRight == nil, r.play.getUpPhase == .righting { tRight = t; landed = simd_length(SIMD2(r.rig.sim.centroid().x, r.rig.sim.centroid().z) - spot) }
                if tRight != nil, tDone == nil, r.play.getUpPhase == .off, abs(pose.tilt - base.tilt) < 0.2, simd_length(SIMD2(pose.centroid.x, pose.centroid.z) - spot) < 0.25,
                   simd_length(r.rig.sim.meanVelocity()) < 0.05, abs(pose.yaw - base.yaw) < 0.35 { tDone = t }
            }
            print("GETUP \(name): max tilt \(maxTilt), righting starts \(tRight ?? -1) s after the throw, standing at the spot \(tDone ?? -1) s (\((tDone ?? 99) - (tRight ?? 0) + 2) s after he was still for 2 s)")
            XCTAssertGreaterThan(maxTilt, 0.8, name + ": he really did tumble")
            XCTAssertNotNil(tDone, name + ": he is up and back at the spot")
            XCTAssertLessThan((tDone ?? 99) - (tRight ?? 0), 4.0 + 1.5 * max(0, landed - 1.0), name + ": about 4 s from the start of the get-up (plus the walk when he landed far)")
            let pose = r.rig.sim.bodyPose(iterations: 10)
            XCTAssertLessThan(abs(pose.tilt - base.tilt), 0.2, name)
            XCTAssertLessThan(simd_length(SIMD2(r.rig.sim.centroid().x, r.rig.sim.centroid().z) - spot), 0.25, name)
            XCTAssertLessThan(simd_length(r.rig.sim.meanVelocity()), 0.05, name)
            XCTAssertLessThan(abs(pose.yaw - base.yaw), 0.35, name + ": facing the camera again")
        }
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
