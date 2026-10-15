//
//  BlobBrainTests.swift
//  Headless checks of Bob's brain: walking, waving, rest-shape recovery, touch.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BlobBrainTests: XCTestCase {

    private static let simMesh = buildSimMesh()
    private static let renderMesh = buildRenderMesh()

    private struct Rig {
        let sim: SoftBody
        let skinner: Skinner
        let brain: BlobBrain
    }

    private func makeRig() -> Rig {
        let sm = Self.simMesh, rm = Self.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount,
                              eyes: buildEyeRig(render: rm, sim: sm), antennae: buildAntennaRig(render: rm, sim: sm))
        let sim = SoftBody(mesh: sm, firmness: 0.95)
        sim.reset(drop: 0.35)
        for _ in 0..<300 { sim.step() }
        let brain = BlobBrain()
        brain.autonomy = false
        brain.attach(renderMesh: rm, synchronous: true)
        return Rig(sim: sim, skinner: skinner, brain: brain)
    }

    private func run(_ r: Rig, seconds: Float, touched: Bool = false, until: (() -> Bool)? = nil,
                     each: (() -> Void)? = nil) {
        let n = Int(seconds * 60)
        for _ in 0..<n {
            r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: touched)
            r.sim.step()
            each?()
            if let until, until() { break }
        }
    }

    /// Body-frame positions of all particles (rotation and translation of the best-fit pose removed).
    private func bodyFrame(_ sim: SoftBody) -> [SIMD3<Float>] {
        let p = sim.bodyPose(iterations: 20)
        let inv = p.rotation.inverse
        return (0..<sim.n).map { inv.act(SIMD3(sim.x[3 * $0], sim.x[3 * $0 + 1], sim.x[3 * $0 + 2]) - p.centroid) }
    }

    func testWalksToTargetAndArrives() {
        let r = makeRig()
        let start = SIMD2(r.sim.centroid().x, r.sim.centroid().z)
        let target = start + SIMD2<Float>(1.0, -0.7)
        r.brain.request(.goTo(target))
        var minVol = Float.infinity
        var arrived = false
        run(r, seconds: 12, until: { arrived }) {
            minVol = min(minVol, self.tetMin(r.sim).body)
            let c = r.sim.centroid()
            if simd_length(SIMD2(c.x, c.z) - target) < 0.2 && r.brain.activity == .idle { arrived = true }
        }
        let c = r.sim.centroid()
        XCTAssertLessThan(simd_length(SIMD2(c.x, c.z) - target), 0.2)
        XCTAssertTrue(arrived)
        XCTAssertGreaterThan(minVol, 0, "no inverted body tets while walking")
        XCTAssertFalse(r.sim.hasNonFinite())
    }

    func testWaveReturnsToRestShape() {
        let r = makeRig()
        run(r, seconds: 1.5)
        let before = bodyFrame(r.sim)
        r.brain.request(.wave)
        var minVol = Float.infinity
        var sawWaving = false
        var maxBlend: Float = 0
        run(r, seconds: 8) {
            minVol = min(minVol, self.tetMin(r.sim).body)
            if r.brain.activity == .waving {
                sawWaving = true
                maxBlend = max(maxBlend, r.skinner.overrideDelta.map { simd_length($0) }.max() ?? 0)
            }
        }
        XCTAssertTrue(sawWaving)
        print("WAVE maxBlend \(maxBlend) minBodyTetRatio \(minVol) appendage \(self.tetMin(r.sim).appendage)")
        XCTAssertGreaterThan(maxBlend, 0.15, "the arm skin is displaced during the wave")
        XCTAssertGreaterThan(minVol, 0, "no inverted body tets during the wave")
        XCTAssertTrue(r.skinner.overrideVertices.isEmpty, "render override released after the wave")
        run(r, seconds: 3)
        XCTAssertEqual(r.brain.activity, .idle)
        let after = bodyFrame(r.sim)
        var worst: Float = 0
        for i in 0..<before.count { worst = max(worst, simd_length(before[i] - after[i])) }
        print("WAVE rest-shape worst deviation \(worst)")
        XCTAssertLessThan(worst, 0.03)
        XCTAssertTrue(r.sim.targets.isEmpty)
        XCTAssertFalse(r.sim.hasNonFinite())
    }

    func testTouchYieldsAndResumesWhereHeIs() {
        let r = makeRig()
        r.brain.request(.goTo(SIMD2(1.5, 0)))
        run(r, seconds: 1.5)
        XCTAssertEqual(r.brain.activity, .walking)
        run(r, seconds: 0.5, touched: true)
        XCTAssertEqual(r.brain.activity, .touched)
        XCTAssertEqual(r.sim.attractor.strength, 0)
        XCTAssertTrue(r.sim.targets.isEmpty)
        run(r, seconds: 5)
        XCTAssertEqual(r.brain.activity, .idle)
        let c = r.sim.centroid()
        XCTAssertGreaterThan(c.x, 0.1, "he stays where he was released instead of snapping home")
        XCTAssertLessThan(c.x, 1.45)
        XCTAssertEqual(r.brain.gait.home.x, c.x, accuracy: 0.15)
    }

    func testAutonomyStaysAliveAndBounded() {
        let r = makeRig()
        r.brain.autonomy = true
        var seen = Set<String>()
        var byAct: [String: Float] = [:]
        var minVol = Float.infinity
        var maxR: Float = 0
        run(r, seconds: 70) {
            seen.insert("\(r.brain.activity)")
            let mv = self.tetMin(r.sim).body
            minVol = min(minVol, mv)
            byAct["\(r.brain.activity)", default: .infinity] = min(byAct["\(r.brain.activity)", default: .infinity], mv)
            let c = r.sim.centroid(); maxR = max(maxR, hypotf(c.x, c.z))
        }
        print("AUTONOMY minVol by activity \(byAct)")
        print("AUTONOMY saw \(seen.sorted()) maxR \(maxR) minVol \(minVol)")
        XCTAssertGreaterThan(seen.count, 3)
        XCTAssertGreaterThan(minVol, 0)
        XCTAssertLessThan(maxR, 3.6)
        XCTAssertFalse(r.sim.hasNonFinite())
    }

    func testMouthOnlyOpensWhileEatingAndDrinking() {
        let r = makeRig()
        var nonZeroOutside = false
        var maxEat: Float = 0
        func sample() {
            let a = r.brain.activity
            if a == .eating || a == .drinking { maxEat = max(maxEat, r.brain.mouthOpen) }
            else if r.brain.mouthOpen != 0 { nonZeroOutside = true }
        }
        run(r, seconds: 1, each: sample)
        r.brain.request(.goTo(SIMD2(0.8, 0.4)))
        run(r, seconds: 6, each: sample)
        r.brain.request(.wave)
        run(r, seconds: 6, each: sample)
        XCTAssertEqual(r.brain.mouthOpen, 0)
        for req in [BlobRequest.eat(at: SIMD2(0.6, -0.5)), .drink(at: SIMD2(-0.6, -0.5))] {
            var done = false
            r.brain.onFinished = { _ in done = true }
            r.brain.request(req)
            run(r, seconds: 14, until: { done }, each: sample)
            XCTAssertTrue(done)
            XCTAssertEqual(r.brain.mouthOpen, 0, "mouth closes exactly when eating / drinking ends")
        }
        XCTAssertFalse(nonZeroOutside)
        XCTAssertGreaterThan(maxEat, 0.5)
        // interrupted by touch mid-meal
        r.brain.onFinished = nil
        r.brain.request(.eat(at: SIMD2(0.6, 0.0)))
        run(r, seconds: 14, until: { r.brain.activity == .eating && r.brain.mouthOpen > 0.2 })
        XCTAssertGreaterThan(r.brain.mouthOpen, 0.2)
        run(r, seconds: 0.1, touched: true)
        XCTAssertEqual(r.brain.mouthOpen, 0)
    }

    /// Smallest current / rest volume ratio over the body tets, and over the arm / foot apex tets (those touching an appendage
    /// particle). The thin arm apex tets already flip transiently under the existing hop gait (about -18), so only the body
    /// tets are held to "never inverted". Sampled every 6th step to keep Debug runs short.
    private func tetMin(_ sim: SoftBody) -> (body: Float, appendage: Float) {
        let probe = probes[ObjectIdentifier(sim)] ?? TetProbe(sim)
        probes[ObjectIdentifier(sim)] = probe
        return probe.sample()
    }
    private var probes: [ObjectIdentifier: TetProbe] = [:]
}

nonisolated final class TetProbe {
    private let sim: SoftBody
    private let tets: [Int32]
    private let rest: [Float]
    private let isApp: [Bool]
    private var n = 0
    private var last: (body: Float, appendage: Float) = (.infinity, .infinity)
    init(_ sim: SoftBody) {
        let tl = sim.tets.map { Int32($0) }
        var app = [Bool](repeating: false, count: sim.n)
        for a in sim.appendages { for p in a.particles { app[p] = true } }
        var flags: [Bool] = [], vols: [Float] = []
        for k in 0..<(tl.count / 4) {
            let i = (0..<4).map { Int(tl[4 * k + $0]) }
            flags.append(i.contains { app[$0] })
            vols.append(Self.vol({ sim.restPosition($0) }, i))
        }
        self.sim = sim; tets = tl; isApp = flags; rest = vols
    }
    private static func vol(_ f: (Int) -> SIMD3<Float>, _ i: [Int]) -> Float {
        let a = f(i[0]), b = f(i[1]), c = f(i[2]), d = f(i[3])
        return simd_dot(b - a, simd_cross(c - a, d - a)) / 6
    }
    func sample() -> (body: Float, appendage: Float) {
        n += 1
        if n % 6 != 1 { return last }
        var body = Float.infinity, apx = Float.infinity
        let x = sim.x
        for k in 0..<rest.count {
            let i0 = 3 * Int(tets[4 * k]), i1 = 3 * Int(tets[4 * k + 1]), i2 = 3 * Int(tets[4 * k + 2]), i3 = 3 * Int(tets[4 * k + 3])
            let a = SIMD3(x[i0], x[i0 + 1], x[i0 + 2])
            let b = SIMD3(x[i1], x[i1 + 1], x[i1 + 2]) - a, c = SIMD3(x[i2], x[i2 + 1], x[i2 + 2]) - a, d = SIMD3(x[i3], x[i3 + 1], x[i3 + 2]) - a
            let v = simd_dot(b, simd_cross(c, d)) / 6 / rest[k]
            if isApp[k] { apx = min(apx, v) } else { body = min(body, v) }
        }
        last = (min(last.body, body), min(last.appendage, apx))
        return last
    }

    /// Every spot the brain may pick stays fully on screen: project the extreme body points through the game camera.
    func testConstrainKeepsBodyOnScreen() {
        let aspect = GameCamera.aspect
        let vp = GameCamera.camera(aspect: aspect).viewProj
        var worst: Float = 0
        for zi in 0...24 {
            for xi in 0...40 {
                let p = SIMD3<Float>(-4 + Float(xi) * 0.2, 0, -3 + Float(zi) * 0.25)
                let q = GameCamera.constrain(p, radius: 0.7)
                for dx: Float in [-0.8, 0.8] {
                    for y: Float in [0, 0.7, 1.25] {
                        let c = vp * SIMD4<Float>(q.x + dx, y, q.z, 1)
                        worst = max(worst, abs(c.x / c.w))
                    }
                }
            }
        }
        XCTAssertLessThan(worst, 0.98, "Bob's silhouette must stay inside the frame")
    }
}
