//
//  FootWallTurnTests.swift
//  2026-11-15 (foot-float, the phone's guest_t2 take): a LONE Jelmiko walked into the back-left corner of the room, stopped and turned to face the camera; for ~0.6 s a foot piece hung
//  beside his body like a teardrop (FootLog: footL top 9-31 cm outside the body before the leash). Mechanism: with one body at home the stage never builds the roaming polygon
//  (MelonStage.syncRoam needs 2+ bodies or a visitor), so his sim keeps configureRoom's round wall ((0, 0.8) r 3.9) while the brain's floor (GameCamera.constrain, the old box
//  rule; the wander box reaches (+-3.2, -2.6)) lets the ROOT stand where the BODY cannot. The wall holds the body in; the feet are placed at root + offset, out past the wall;
//  turning to the camera swings the wall-side foot further out; the skin's leash then drags the piece's TOP along the egg gradient onto the body's flank and the rest of it hangs
//  outside (the leash moves the piece by its top only and nothing bounds it to the hip afterwards).
//  This suite rebuilds that headlessly (the stage's lone-body room: configureRoom only, the room wall on the sim, the tail landmarks configured as JellyActor does), every
//  frame skinned, and measures what is DRAWN: each foot piece's mean against the nearest drawn body vertex. It fails on 0ed16cf3.
//  Env (TEST_RUNNER_ prefix): FOOTWALL_ROAM=1 builds the roaming polygon + its arena (the 2+ body / visitor room) first; FOOTWALL_LOG = a file for the per-spot lines.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FootWallTurnTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let env = ProcessInfo.processInfo.environment
    /// A drawn foot piece whose mean is farther than this from every drawn body vertex is OFF the body (attached: 0.077-0.081 in the controls and at the same corners with the
    /// polygon's wall; the phone's take reproduced: 0.105-0.179).
    static let maxDetach: Float = 0.095
    /// The farthest vertex of a piece from the drawn body (attached: 0.219-0.228; reproduced: 0.285-0.321).
    static let maxFar: Float = 0.25
    /// The FootLog gap: the piece's top outside the body (the leash's frame) before the leash moved it (attached: 0; reproduced: 0.20-0.31; the phone: 0.31).
    static let maxGapPre: Float = 0.05

    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    /// The room as the stage sets it for ONE Jelmiko at home (or, FOOTWALL_ROAM=1, as for two or more / a visitor).
    static func room() {
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        if env["FOOTWALL_ROAM"] == "1" { _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0) } else { GameCamera.clearRoam() }
    }

    struct Probe {
        var detach: Float = 0, detachT: Float = 0, detachSide = -1, gapPre: Float = 0
        var far: Float = 0, farT: Float = 0          // the farthest vertex of a piece from the drawn body (its nearest body vertex)
        var rootOut: Float = 0          // farthest the brain's root got from the wall centre, plus the body half width, minus the wall radius (> 0 = the root stood where the body cannot)
        var centroidR: Float = 0
    }

    /// One body (`feature`) from `start` walking to `spot` (a plain walk), then standing (the idle turn to the camera) for `stand` seconds. Every frame as the stage runs it.
    func run(feature: JellyFeature, start: SIMD2<Float>, spot: SIMD2<Float>, stand: Float = 3) -> Probe {
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let a = JellyActor(id: 0, name: "Solo", simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: start)
        a.skinner.configureTail(rm)
        a.reset(drop: 0.35, shift: false)
        a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius          // (MelonStage.init: every game body gets the room's round wall)
        let b = BlobBrain.forGame()
        b.attach(renderMesh: rm, synchronous: true)
        b.seed = 5; b.steerID = 0; b.feature = feature
        a.brain = b
        Self.keep.append(a); Self.keep.append(b)
        a.sim.teleport(toXZ: start)
        for _ in 0..<150 { a.sim.step() }
        b.currentPose(a.sim)
        b.autonomy = false; b.idleMood = .happy; b.anticsEnabled = false; b.watching = true; b.sleepEnabled = false; b.amplitude = 1
        var dyn = [Float](repeating: 0, count: rm.vertexCount * 6)
        let bodyLimit = a.skinner.bodyVertexLimit > 0 ? a.skinner.bodyVertexLimit : (rm.armCapsule?.firstVertex.min() ?? rm.vertexCount)
        var p = Probe()
        var t: Float = 0, arrived: Float = -1
        func frame() {
            b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false)
            a.skinner.jelly.tick(brain: b, sim: a.sim, dt: a.sim.stepDt)
            if a.updateSleep(forceAwake: false) { a.sim.step() }
            b.refitBeans(a.sim, a.skinner)
            dyn.withUnsafeMutableBufferPointer { a.skinner.update(x: a.sim.x, index: rm.index, into: $0.baseAddress!) }
            t += a.sim.stepDt
            let c = a.sim.centroid()
            p.centroidR = max(p.centroidR, simd_distance(SIMD2(c.x, c.z), GameCamera.arenaCenter))
            p.rootOut = max(p.rootOut, simd_distance(SIMD2(b.px, b.pz), GameCamera.arenaCenter) + 0.45 - GameCamera.arenaRadius)
            let sk = a.skinner
            guard sk.beansActive, sk.beanBlend > 0.5, sk.beanFirst.count == 2 else { return }
            for s in 0..<2 {
                var m = SIMD3<Float>.zero
                for i in 0..<FootBean.vertexCount { let o = 6 * (sk.beanFirst[s] + i); m += SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]) }
                m /= Float(FootBean.vertexCount)
                var best = Float.infinity
                var v = 0
                while v < bodyLimit { let o = 6 * v; best = min(best, simd_distance_squared(SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]), m)); v += 2 }
                let d = best.squareRoot()
                if d > p.detach { p.detach = d; p.detachT = t; p.detachSide = s }
                var farV: Float = 0
                for i in Swift.stride(from: 0, to: FootBean.vertexCount, by: 3) {
                    let o = 6 * (sk.beanFirst[s] + i), q = SIMD3(dyn[o], dyn[o + 1], dyn[o + 2])
                    var bb = Float.infinity, w = 0
                    while w < bodyLimit { let o2 = 6 * w; bb = min(bb, simd_distance_squared(SIMD3(dyn[o2], dyn[o2 + 1], dyn[o2 + 2]), q)); w += 3 }
                    farV = max(farV, bb.squareRoot())
                }
                if farV > p.far { p.far = farV; p.farT = t }
                p.gapPre = max(p.gapPre, -sk.leashPre[s])
            }
        }
        for _ in 0..<60 { frame() }
        b.requestNow(.goTo(spot))
        for f in 0..<(60 * 14) {
            frame()
            if arrived < 0, f > 10, b.activity != .walking, b.activity != .coming, b.isWalkScript == false { arrived = t }
            if arrived > 0, t > arrived + stand { break }
        }
        return p
    }

    static let spots: [(start: SIMD2<Float>, spot: SIMD2<Float>, name: String)] = [
        (SIMD2(-1.6, -1.2), SIMD2(-3.0, -1.6), "back-left (the phone's take)"),
        (SIMD2(1.6, -1.2), SIMD2(3.0, -1.6), "back-right"),
        (SIMD2(-0.8, -1.4), SIMD2(-2.4, -2.4), "back-left corner"),
        (SIMD2(0.8, 0.6), SIMD2(-0.6, 0.6), "control: the middle, walking left"),
        (SIMD2(-0.8, 1.6), SIMD2(0.6, 1.6), "control: the front, walking right"),
        (SIMD2(0.0, 1.8), SIMD2(0.2, 0.2), "control: walking back"),
    ]

    func log(_ s: String) {
        MotionLog.write(s)
        if let f = Self.env["FOOTWALL_LOG"] { let l = s + "\n"; if let h = FileHandle(forWritingAtPath: f) { h.seekToEndOfFile(); h.write(Data(l.utf8)); try? h.close() } else { try? l.write(toFile: f, atomically: true, encoding: .utf8) } }
    }

    /// A lone Lavender walks to the room's back corners and turns to the camera: no foot piece is ever drawn off the body.
    func testLoneBodyCornerTurnKeepsFeetOn() {
        Self.room()
        let fd0 = Skinner.frameDisagreeDist
        if let v = Self.env["FOOTWALL_FRAMEDIST"].flatMap(Float.init) { Skinner.frameDisagreeDist = v }          // (diagnostic: the leash frame's switch distance)
        defer { Skinner.frameDisagreeDist = fd0 }
        log(String(format: "[footwall] room: wall (%.2f, %.2f) r %.2f, roam polygon %@", GameCamera.arenaCenter.x, GameCamera.arenaCenter.y, GameCamera.arenaRadius, GameCamera.roamFloor == nil ? "none (lone body)" : "built"))
        var worst: Float = 0
        for (start, spot, name) in Self.spots {
            let p = run(feature: .wings, start: start, spot: spot)
            log(String(format: "[footwall] %@: piece mean off the drawn body max %.3f (foot %d at t %.2f), farthest piece vertex %.3f (t %.2f), top outside before the leash max %.3f, root past (wall - half width) by %.3f, centroid r %.2f",
                       name, p.detach, p.detachSide, p.detachT, p.far, p.farT, p.gapPre, p.rootOut, p.centroidR))
            worst = max(worst, p.detach)
            XCTAssertLessThan(p.detach, Self.maxDetach, "\(name): a foot piece is drawn \(p.detach) m from the body (foot \(p.detachSide), t \(p.detachT))")
            XCTAssertLessThan(p.far, Self.maxFar, "\(name): a foot piece reaches \(p.far) m off the body (t \(p.farT))")
            XCTAssertLessThan(p.gapPre, Self.maxGapPre, "\(name): a foot piece's top was \(p.gapPre) m outside the body before the leash")
        }
        log(String(format: "[footwall] worst %.3f", worst))
    }
}
