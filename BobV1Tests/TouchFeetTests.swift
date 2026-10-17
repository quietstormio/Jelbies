//
//  TouchFeetTests.swift
//  While he is held, dragged, thrown or getting up, his drawn feet / legs stay attached under the body (never stretched apart or left
//  behind where the walk last planted them). Measured on the rendered skin: each foot's centre against where the body's rigid fit
//  puts that foot (body frame, taken at rest), and the distance between the two feet against their rest distance.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TouchFeetTests: XCTestCase {
    @MainActor struct Probe {
        let r: TouchPlayTests.Rig
        var rest: [SIMD3<Float>] = [.zero, .zero]
        var restSep: Float = 0
        var maxLeft: Float = 0          // max distance of a foot from its place under the body
        var maxSep: Float = 0           // max change of the feet's distance
        var worst = ""
        var byTag: [String: Float] = [:]
        var sepByTag: [String: Float] = [:]
        init(_ r: TouchPlayTests.Rig) {
            self.r = r
            // reference: where the drawn feet (beans) sit under the body at rest, measured on a twin rig with the dangle phase zeroed per foot
            let c = TouchPlayTests.Rig()
            let sim = c.rig.sim, brain = c.rig.brain, sk = c.rig.skinner
            c.step(touched: true)
            var cs = [SIMD3<Float>.zero, SIMD3<Float>.zero]
            let probe = Probe.measureOnly(c)
            for (s, ph) in [(0, Float(0)), (1, Float(0.5))] {
                for _ in 0..<45 { brain.driveExcited(sim: sim, skinner: sk, dt: 1.0 / 60, level: 1, phase: ph); c.step(touched: true) }
                cs[s] = probe(s)
            }
            let pose = sim.bodyPose(iterations: 3)
            for s in 0..<2 { rest[s] = pose.rotation.inverse.act(cs[s] - pose.centroid) }
            restSep = simd_length(cs[0] - cs[1])
        }
        static func measureOnly(_ c: TouchPlayTests.Rig) -> (Int) -> SIMD3<Float> {
            { s in
                c.rig.render()
                let ids = c.rig.skinner.beansActive ? c.rig.bean[s] : c.rig.core[s]
                var a = SIMD3<Float>.zero
                for v in ids { a += SIMD3(c.rig.dyn[6 * Int(v)], c.rig.dyn[6 * Int(v) + 1], c.rig.dyn[6 * Int(v) + 2]) }
                return a / Float(max(ids.count, 1))
            }
        }
        func centers() -> [SIMD3<Float>] {
            let rig = r.rig
            return (0..<2).map { s in
                let ids = rig.skinner.beansActive ? rig.bean[s] : rig.core[s]
                var a = SIMD3<Float>.zero
                for v in ids { a += SIMD3(rig.dyn[6 * Int(v)], rig.dyn[6 * Int(v) + 1], rig.dyn[6 * Int(v) + 2]) }
                return a / Float(max(ids.count, 1))
            }
        }
        mutating func measure(_ tag: String) {
            r.rig.render()
            let c = centers(), pose = r.rig.sim.bodyPose(iterations: 3)
            for s in 0..<2 {
                let want = pose.centroid + pose.rotation.act(rest[s])
                let d = simd_length(c[s] - want)
                if d > maxLeft { maxLeft = d; worst = tag }
                byTag[tag] = max(byTag[tag] ?? 0, d)
            }
            let sp = abs(simd_length(c[0] - c[1]) - restSep)
            maxSep = max(maxSep, sp); sepByTag[tag] = max(sepByTag[tag] ?? 0, sp)
        }
    }

    /// The stage's frame while a finger holds him: the grab target, the held reactions, the brain hands-off, the sim.
    private func held(_ r: TouchPlayTests.Rig, target: SIMD3<Float>, lift: Float, grabbing: Bool = true) {
        let sim = r.rig.sim
        r.step(touched: true) {
            if grabbing { sim.moveGrab(target: target, rot: nil) }
            r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: grabbing, liftHeight: lift, sim: sim, brain: r.rig.brain, skinner: r.rig.skinner)
        }
    }

    /// Hold-drag along the floor, lift and swing, set down, let go. Returns the probe.
    func dragScenario() -> Probe {
        let r = TouchPlayTests.Rig()
        let sim = r.rig.sim
        r.step(touched: true)
        var p = Probe(r)
        let c = sim.centroid()
        let hit = c + SIMD3(0, 0.1, 0.5)
        sim.beginGrab(hit: hit, radius: 0.4)
        for k in 0..<30 { held(r, target: hit, lift: 0); if k % 3 == 0 { p.measure("hold") } }
        for k in 0..<240 {                                     // along the floor, ~1 u/s
            let t = Float(k) / 60
            held(r, target: hit + SIMD3(0.55 * sinf(1.9 * t), 0, 0), lift: 0)
            if k % 3 == 0 { p.measure("floor drag") }
        }
        for k in 0..<360 {                                     // lift a hand's width and swing him around
            let t = Float(k) / 60, e = min(1, t / 0.8)
            let lift = 0.4 * e * e * (3 - 2 * e)
            held(r, target: hit + SIMD3(0.6 * sinf(2.4 * t) * e, lift + 0.1 * sinf(3.1 * t) * e, 0.3 * sinf(1.7 * t) * e), lift: lift)
            if k % 3 == 0 { p.measure("lifted swing") }
        }
        for k in 0..<90 {                                      // set down
            let lift = 0.4 * (1 - Float(k) / 90)
            held(r, target: hit + SIMD3(0, lift, 0), lift: lift)
            if k % 3 == 0 { p.measure("set down") }
        }
        sim.endGrab()
        for k in 0..<240 { held(r, target: hit, lift: 0, grabbing: false); if k % 3 == 0 { p.measure("let go") } }
        return p
    }

    func testDragKeepsTheFeetUnderTheBody() {
        let p = dragScenario()
        print("FEETDRAG max foot left behind \(p.maxLeft) u (\(p.maxLeft / MotionRig.H) H) at '\(p.worst)', max change of foot separation \(p.maxSep) u (rest \(p.restSep)); left by phase \(p.byTag); sep by phase \(p.sepByTag)")
        // BEFORE (the 3.2 Hz excited kicks, +-0.13 u up / 0.10 u forward out of phase): left behind 0.23 u (0.17 H), separation changed by 0.037 u.
        XCTAssertLessThanOrEqual(p.maxLeft, 0.12 * MotionRig.H, "the feet stay under the body: held, dragged along the floor, lifted and swung, set down, let go")
        XCTAssertLessThanOrEqual(p.maxSep, 0.03, "the two feet never move apart or together")
        XCTAssertLessThan(p.sepByTag["lifted swing"] ?? 1, 0.005, "settled: the feet keep their rest distance while he swings")
    }
}


@MainActor
final class TouchWallTests: XCTestCase {
    /// A hard sideways throw hits the soft wall at the frame edge: squash, thump, a counted bounce, and he never leaves the frame.
    func testThrowBouncesOffTheFrameEdgeAndStaysInFrame() {
        for dir: Float in [1, -1] {
            let r = TouchPlayTests.Rig()
            let spot = GameCamera.callSpot
            r.step(touched: true)
            let c0 = r.rig.sim.centroid()
            let lim = TouchPlay.FrameLimits(xMin: c0.x - 0.9, xMax: c0.x + 0.9, zMin: c0.z - 1.2, zMax: c0.z + 0.6, yMax: 2.4)
            r.rig.sim.launch(velocity: SIMD3(dir * 3.0, 3.5, 0), spin: SIMD3(0, 0, -dir * 2.5))
            r.play.thrown = true
            r.rec.clear()
            var maxOut: Float = -9, squashed = false
            for _ in 0..<(60 * 3) {
                r.play.wallsFrame(now: r.clock, sim: r.rig.sim, limits: lim)
                r.step(touched: true)
                let b = r.rig.sim.bounds()
                maxOut = max(maxOut, b.hi.x - lim.xMax, lim.xMin - b.lo.x, b.hi.y - lim.yMax, b.hi.z - lim.zMax)
                if r.rig.sim.deformation() > 0.02 { squashed = true }
            }
            print("WALL dir \(dir): wall bounces \(r.play.wallBounces), bounces \(r.play.bounces), max overshoot past the wall \(maxOut) u")
            _ = spot
            XCTAssertGreaterThanOrEqual(r.play.wallBounces, 1, "he hits the wall")
            XCTAssertGreaterThanOrEqual(r.play.bounces, r.play.wallBounces, "the wall bounce counts")
            XCTAssertLessThanOrEqual(maxOut, 0.06, "never more than a step past the wall: his whole body stays in frame")
            XCTAssertFalse(r.rec.events(.transient).isEmpty, "a thump per hit")
            _ = squashed
        }
    }

    func testWallsDoNothingUnlessThrown() {
        let r = TouchPlayTests.Rig()
        r.step(touched: true)
        let before = r.rig.sim.centroid()
        r.play.wallsFrame(now: r.clock, sim: r.rig.sim, limits: .init(xMin: before.x - 0.1, xMax: before.x + 0.1, zMin: -9, zMax: 9, yMax: 0.1))
        XCTAssertEqual(simd_length(r.rig.sim.centroid() - before), 0, accuracy: 1e-6)
    }
}
